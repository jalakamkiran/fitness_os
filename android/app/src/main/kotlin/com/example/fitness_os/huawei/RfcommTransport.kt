package com.example.fitness_os.huawei

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.ParcelUuid
import android.util.Log
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Dual-radio Huawei transport:
 * BLE discovery (FE86 / name filter) → Classic RFCOMM SDP session socket.
 * Bytes only — no Huawei framing/auth here.
 */
class RfcommTransport(
    private val context: Context,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    companion object {
        private const val TAG = "RfcommTransport"
        val HUAWEI_SDP_UUID: UUID =
            UUID.fromString("82FF3820-8411-400C-B85A-55BDB32CF060")
        val HUAWEI_FE86_UUID: UUID =
            UUID.fromString("0000FE86-0000-1000-8000-00805F9B34FB")
        private const val NAME_PREFIX = "huawei watch gt 5"
        private const val READ_BUFFER = 1024
    }

    private val io = Executors.newSingleThreadExecutor()
    private val adapter: BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private var socket: BluetoothSocket? = null
    private var input: InputStream? = null
    private var output: OutputStream? = null
    private val reading = AtomicBoolean(false)
    private val scanning = AtomicBoolean(false)
    private var usedSecureSocket: Boolean? = null

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device ?: return
            val name = device.name ?: result.scanRecord?.deviceName ?: return
            if (!name.lowercase().startsWith(NAME_PREFIX)) return
            emit(
                mapOf(
                    "type" to "discovery",
                    "mac" to device.address,
                    "name" to name,
                    "rssi" to result.rssi,
                ),
            )
        }

        override fun onScanFailed(errorCode: Int) {
            scanning.set(false)
            emit(
                mapOf(
                    "type" to "error",
                    "code" to "scan_failed",
                    "message" to "BLE scan failed: $errorCode",
                ),
            )
        }
    }

    fun adapterState(): String {
        val a = adapter ?: return "unavailable"
        return when (a.state) {
            BluetoothAdapter.STATE_ON -> "on"
            BluetoothAdapter.STATE_OFF -> "off"
            BluetoothAdapter.STATE_TURNING_ON -> "turning_on"
            BluetoothAdapter.STATE_TURNING_OFF -> "turning_off"
            else -> "unknown"
        }
    }

    @SuppressLint("MissingPermission")
    fun startBleDiscovery() {
        val a = adapter ?: throw IllegalStateException("Bluetooth unavailable")
        if (!a.isEnabled) throw IllegalStateException("Bluetooth adapter is off")
        if (scanning.getAndSet(true)) return

        a.cancelDiscovery()
        val scanner = a.bluetoothLeScanner
            ?: throw IllegalStateException("BLE scanner unavailable")

        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(HUAWEI_FE86_UUID))
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        emit(mapOf("type" to "connection_state", "state" to "scanning"))
        scanner.startScan(listOf(filter), settings, scanCallback)
    }

    @SuppressLint("MissingPermission")
    fun stopBleDiscovery() {
        if (!scanning.getAndSet(false)) return
        try {
            adapter?.bluetoothLeScanner?.stopScan(scanCallback)
        } catch (e: Exception) {
            Log.w(TAG, "stopScan: ${e.message}")
        }
    }

    @SuppressLint("MissingPermission")
    fun connect(mac: String, sdpUuid: String? = null) {
        val a = adapter ?: throw IllegalStateException("Bluetooth unavailable")
        if (!a.isEnabled) throw IllegalStateException("Bluetooth adapter is off")

        stopBleDiscovery()
        a.cancelDiscovery()

        disconnectInternal(emitState = false)
        emit(mapOf("type" to "connection_state", "state" to "connecting"))

        val uuid = sdpUuid?.let { UUID.fromString(it) } ?: HUAWEI_SDP_UUID
        val device = a.getRemoteDevice(mac)

        io.execute {
            try {
                val sock = openSocket(device, uuid)
                socket = sock
                input = sock.inputStream
                output = sock.outputStream
                emit(
                    mapOf(
                        "type" to "connection_state",
                        "state" to "connected",
                        "mac" to mac,
                        "secure" to (usedSecureSocket == true),
                    ),
                )
                startReadLoop()
            } catch (e: Exception) {
                Log.e(TAG, "connect failed", e)
                disconnectInternal(emitState = false)
                emit(
                    mapOf(
                        "type" to "error",
                        "code" to "connect_failed",
                        "message" to (e.message ?: "RFCOMM connect failed"),
                    ),
                )
                emit(mapOf("type" to "connection_state", "state" to "disconnected"))
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun openSocket(device: BluetoothDevice, uuid: UUID): BluetoothSocket {
        // Prefer secure (GB path); fall back to insecure and record outcome.
        return try {
            val secure = device.createRfcommSocketToServiceRecord(uuid)
            secure.connect()
            usedSecureSocket = true
            secure
        } catch (secureError: IOException) {
            Log.w(TAG, "secure RFCOMM failed, trying insecure: ${secureError.message}")
            val insecure = device.createInsecureRfcommSocketToServiceRecord(uuid)
            insecure.connect()
            usedSecureSocket = false
            insecure
        }
    }

    fun write(bytes: ByteArray) {
        val out = output ?: throw IllegalStateException("Not connected")
        io.execute {
            try {
                out.write(bytes)
                out.flush()
            } catch (e: Exception) {
                emit(
                    mapOf(
                        "type" to "error",
                        "code" to "write_failed",
                        "message" to (e.message ?: "write failed"),
                    ),
                )
            }
        }
    }

    fun disconnect() {
        disconnectInternal(emitState = true)
    }

    private fun disconnectInternal(emitState: Boolean) {
        reading.set(false)
        stopBleDiscovery()
        try {
            input?.close()
        } catch (_: Exception) {
        }
        try {
            output?.close()
        } catch (_: Exception) {
        }
        try {
            socket?.close()
        } catch (_: Exception) {
        }
        input = null
        output = null
        socket = null
        if (emitState) {
            emit(mapOf("type" to "connection_state", "state" to "disconnected"))
        }
    }

    private fun startReadLoop() {
        if (!reading.compareAndSet(false, true)) return
        io.execute {
            val buf = ByteArray(READ_BUFFER)
            while (reading.get()) {
                try {
                    val n = input?.read(buf) ?: -1
                    if (n < 0) {
                        reading.set(false)
                        emit(mapOf("type" to "connection_state", "state" to "disconnected"))
                        break
                    }
                    if (n == 0) continue
                    val chunk = buf.copyOf(n)
                    emit(
                        mapOf(
                            "type" to "data",
                            "bytes" to chunk,
                        ),
                    )
                } catch (e: Exception) {
                    if (reading.get()) {
                        emit(
                            mapOf(
                                "type" to "error",
                                "code" to "read_failed",
                                "message" to (e.message ?: "read failed"),
                            ),
                        )
                        emit(mapOf("type" to "connection_state", "state" to "disconnected"))
                    }
                    reading.set(false)
                    break
                }
            }
        }
    }

    fun lastSocketSecure(): Boolean? = usedSecureSocket

    fun dispose() {
        disconnectInternal(emitState = false)
        io.shutdownNow()
    }
}
