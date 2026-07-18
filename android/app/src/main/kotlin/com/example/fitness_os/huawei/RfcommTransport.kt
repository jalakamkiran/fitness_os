package com.example.fitness_os.huawei

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.util.Log
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Dual-radio Huawei transport:
 * Discovery (BLE + Classic + bonded) by GT5 name → Classic RFCOMM SDP session.
 * Bytes only — no Huawei framing/auth here.
 */
class RfcommTransport(
    private val context: Context,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    companion object {
        /** Filter logcat with: adb logcat -s FOS_HUAWEI */
        const val TAG = "FOS_HUAWEI"
        val HUAWEI_SDP_UUID: UUID =
            UUID.fromString("82FF3820-8411-400C-B85A-55BDB32CF060")
        private const val READ_BUFFER = 1024

        /** Match names like "HUAWEI Watch GT 5-A07" / "HUAWEI Watch GT 5 Pro-…". */
        fun matchesGt5Name(name: String): Boolean {
            val n = name.lowercase().trim()
            return n.contains("huawei") && n.contains("gt 5")
        }
    }

    private val connectIo = Executors.newSingleThreadExecutor()
    private val readIo = Executors.newSingleThreadExecutor()
    private val adapter: BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private var socket: BluetoothSocket? = null
    private var input: InputStream? = null
    private var output: OutputStream? = null
    private val reading = AtomicBoolean(false)
    private val scanning = AtomicBoolean(false)
    private val connectInFlight = AtomicBoolean(false)
    private val connectGeneration = AtomicInteger(0)
    private var usedSecureSocket: Boolean? = null
    private var classicReceiverRegistered = false

    private val classicReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            when (intent?.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    val device: BluetoothDevice? =
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra(
                                BluetoothDevice.EXTRA_DEVICE,
                                BluetoothDevice::class.java,
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                        }
                    val name = device?.name
                        ?: intent.getStringExtra(BluetoothDevice.EXTRA_NAME)
                    val rssi = intent.getShortExtra(
                        BluetoothDevice.EXTRA_RSSI,
                        Short.MIN_VALUE,
                    ).toInt()
                    if (device != null) {
                        considerDiscovery(
                            source = "classic",
                            mac = device.address,
                            name = name,
                            rssi = if (rssi == Short.MIN_VALUE.toInt()) null else rssi,
                        )
                    }
                }
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                    Log.i(TAG, "classic discovery finished")
                }
            }
        }
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device ?: return
            val name = device.name ?: result.scanRecord?.deviceName
            // Log named BLE ads so we can see what the radio actually hears.
            if (name != null) {
                Log.d(
                    TAG,
                    "ble hear name=$name mac=${redactMac(device.address)} rssi=${result.rssi}",
                )
            }
            considerDiscovery(
                source = "ble",
                mac = device.address,
                name = name,
                rssi = result.rssi,
            )
        }

        override fun onScanFailed(errorCode: Int) {
            Log.e(TAG, "BLE scan failed errorCode=$errorCode (classic may still run)")
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
        if (scanning.getAndSet(true)) {
            Log.w(TAG, "startBleDiscovery ignored — already scanning")
            return
        }

        a.cancelDiscovery()
        emit(mapOf("type" to "connection_state", "state" to "scanning"))

        // 1) Already-bonded / Settings-visible devices (common for GT5).
        emitBondedMatches(a)

        // 2) Open BLE scan — NO FE86 ScanFilter (that was dropping the watch).
        val scanner = a.bluetoothLeScanner
        if (scanner != null) {
            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build()
            Log.i(TAG, "BLE scan start (no UUID filter; name must contain huawei + gt 5)")
            scanner.startScan(/* filters= */ null, settings, scanCallback)
        } else {
            Log.w(TAG, "BLE scanner unavailable — classic-only discovery")
        }

        // 3) Classic inquiry (what Settings often uses).
        registerClassicReceiver()
        val classicStarted = a.startDiscovery()
        Log.i(TAG, "classic startDiscovery=$classicStarted")
    }

    @SuppressLint("MissingPermission")
    fun stopBleDiscovery(emitDisconnected: Boolean = true) {
        if (!scanning.getAndSet(false)) {
            Log.d(TAG, "stopBleDiscovery noop — was not scanning")
            return
        }
        try {
            adapter?.bluetoothLeScanner?.stopScan(scanCallback)
            Log.i(TAG, "BLE scan stopped")
        } catch (e: Exception) {
            Log.w(TAG, "stopScan: ${e.message}")
        }
        try {
            adapter?.cancelDiscovery()
        } catch (e: Exception) {
            Log.w(TAG, "cancelDiscovery: ${e.message}")
        }
        unregisterClassicReceiver()
        Log.i(TAG, "discovery stopped")
        if (emitDisconnected) {
            emit(mapOf("type" to "connection_state", "state" to "disconnected"))
        }
    }

    @SuppressLint("MissingPermission")
    private fun emitBondedMatches(adapter: BluetoothAdapter) {
        val bonded = adapter.bondedDevices ?: emptySet()
        Log.i(TAG, "checking bonded devices count=${bonded.size}")
        for (device in bonded) {
            considerDiscovery(
                source = "bonded",
                mac = device.address,
                name = device.name,
                rssi = null,
            )
        }
    }

    private fun considerDiscovery(
        source: String,
        mac: String,
        name: String?,
        rssi: Int?,
    ) {
        if (name.isNullOrBlank()) {
            Log.v(TAG, "$source ignored (no name) mac=${redactMac(mac)}")
            return
        }
        if (!matchesGt5Name(name)) {
            Log.d(TAG, "$source filtered name=$name")
            return
        }
        Log.i(
            TAG,
            "discovery HIT source=$source name=$name mac=${redactMac(mac)} rssi=$rssi",
        )
        val payload = mutableMapOf<String, Any?>(
            "type" to "discovery",
            "mac" to mac,
            "name" to name,
            "source" to source,
        )
        if (rssi != null) payload["rssi"] = rssi
        emit(payload)
    }

    private fun registerClassicReceiver() {
        if (classicReceiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(classicReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(classicReceiver, filter)
        }
        classicReceiverRegistered = true
    }

    private fun unregisterClassicReceiver() {
        if (!classicReceiverRegistered) return
        try {
            context.unregisterReceiver(classicReceiver)
        } catch (e: Exception) {
            Log.w(TAG, "unregisterReceiver: ${e.message}")
        }
        classicReceiverRegistered = false
    }

    fun isConnected(): Boolean = socket?.isConnected == true && output != null

    /** Remote watch MAC for the active/last connect attempt. */
    @Volatile
    var remoteMac: String? = null
        private set

    /** Best-effort remote name (for setup-device-status); may be null. */
    @Volatile
    var remoteName: String? = null
        private set

    /**
     * Phone Classic BT identity address used in Normal bond TLVs.
     * Android 6+ / 12+ often returns the privacy placeholder `02:00:00:00:00:00`.
     */
    @SuppressLint("HardwareIds", "MissingPermission", "PrivateApi")
    fun localBluetoothAddress(): String? {
        fun usable(raw: String?): String? {
            val addr = raw?.uppercase()?.trim() ?: return null
            if (addr.isBlank() || addr == "02:00:00:00:00:00") return null
            if (!addr.matches(Regex("^([0-9A-F]{2}:){5}[0-9A-F]{2}$"))) return null
            return addr
        }

        usable(adapter?.address)?.let { return it }

        // Older devices / some OEMs still expose Settings.Secure.bluetooth_address.
        try {
            val secure = android.provider.Settings.Secure.getString(
                context.contentResolver,
                "bluetooth_address",
            )
            usable(secure)?.let {
                Log.i(TAG, "phone MAC from Settings.Secure")
                return it
            }
        } catch (e: Exception) {
            Log.d(TAG, "Settings.Secure bluetooth_address: ${e.message}")
        }

        // Last-ditch: BluetoothManager service binder (may be blocked on modern Android).
        try {
            val getService = BluetoothAdapter::class.java.getDeclaredMethod("getBluetoothService")
            getService.isAccessible = true
            val managerService = getService.invoke(null)
            val getAddress = managerService.javaClass.getMethod("getAddress")
            usable(getAddress.invoke(managerService) as? String)?.let {
                Log.i(TAG, "phone MAC from BluetoothManagerService")
                return it
            }
        } catch (e: Exception) {
            Log.d(TAG, "reflection MAC lookup failed: ${e.message}")
        }

        Log.w(TAG, "phone BT MAC unavailable (privacy MAC / blocked)")
        return null
    }

    @SuppressLint("MissingPermission")
    fun connect(mac: String, sdpUuid: String? = null) {
        val a = adapter ?: throw IllegalStateException("Bluetooth unavailable")
        if (!a.isEnabled) throw IllegalStateException("Bluetooth adapter is off")

        if (!connectInFlight.compareAndSet(false, true)) {
            Log.w(TAG, "connect ignored — already in flight mac=${redactMac(mac)}")
            return
        }

        // Stop discovery without flipping UI to disconnected mid-pair.
        stopBleDiscovery(emitDisconnected = false)
        a.cancelDiscovery()

        // Tear down any prior socket without invalidating this attempt yet.
        disconnectInternal(emitState = false, invalidateInFlightConnect = false)
        val generation = connectGeneration.incrementAndGet()
        Log.i(TAG, "connect requested mac=${redactMac(mac)} gen=$generation")

        emit(mapOf("type" to "connection_state", "state" to "connecting"))

        val uuid = sdpUuid?.let { UUID.fromString(it) } ?: HUAWEI_SDP_UUID
        val device = a.getRemoteDevice(mac)
        remoteMac = mac.uppercase()
        remoteName = try {
            device.name?.takeIf { it.isNotBlank() }
        } catch (_: SecurityException) {
            null
        }

        connectIo.execute {
            try {
                if (generation != connectGeneration.get()) {
                    Log.w(TAG, "connect aborted — superseded gen=$generation")
                    return@execute
                }
                val sock = openSocket(device, uuid)
                if (generation != connectGeneration.get()) {
                    Log.w(TAG, "connect discarded — superseded after open gen=$generation")
                    try {
                        sock.close()
                    } catch (_: Exception) {
                    }
                    return@execute
                }
                socket = sock
                input = sock.inputStream
                output = sock.outputStream
                Log.i(
                    TAG,
                    "RFCOMM connected mac=${redactMac(mac)} secure=$usedSecureSocket gen=$generation",
                )
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
                Log.e(TAG, "connect failed mac=${redactMac(mac)} gen=$generation", e)
                if (generation == connectGeneration.get()) {
                    disconnectInternal(emitState = false, invalidateInFlightConnect = false)
                    emit(
                        mapOf(
                            "type" to "error",
                            "code" to "connect_failed",
                            "message" to (e.message ?: "RFCOMM connect failed"),
                        ),
                    )
                    emit(mapOf("type" to "connection_state", "state" to "disconnected"))
                }
            } finally {
                if (generation == connectGeneration.get()) {
                    connectInFlight.set(false)
                }
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun openSocket(device: BluetoothDevice, uuid: UUID): BluetoothSocket {
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

    /**
     * Write must NOT share the read-loop thread — a blocking read would starve
     * outbound link-params and cause auth timeouts (observed on GT5-A07).
     */
    fun write(bytes: ByteArray) {
        val out = output ?: throw IllegalStateException("Not connected")
        try {
            Log.d(TAG, "RFCOMM write ${bytes.size} bytes hex=${bytes.toHexPreview()}")
            out.write(bytes)
            out.flush()
            Log.i(TAG, "RFCOMM write ok (${bytes.size}B)")
        } catch (e: Exception) {
            Log.e(TAG, "RFCOMM write failed", e)
            emit(
                mapOf(
                    "type" to "error",
                    "code" to "write_failed",
                    "message" to (e.message ?: "write failed"),
                ),
            )
            throw e
        }
    }

    fun disconnect() {
        disconnectInternal(emitState = true)
    }

    private fun disconnectInternal(
        emitState: Boolean,
        invalidateInFlightConnect: Boolean = true,
    ) {
        reading.set(false)
        if (invalidateInFlightConnect) {
            connectGeneration.incrementAndGet()
            connectInFlight.set(false)
        }
        stopBleDiscovery(emitDisconnected = false)
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
        readIo.execute {
            Log.i(TAG, "RFCOMM read loop started")
            val buf = ByteArray(READ_BUFFER)
            while (reading.get()) {
                try {
                    val n = input?.read(buf) ?: -1
                    if (n < 0) {
                        reading.set(false)
                        Log.w(TAG, "RFCOMM read EOF")
                        emit(mapOf("type" to "connection_state", "state" to "disconnected"))
                        break
                    }
                    if (n == 0) continue
                    val chunk = buf.copyOf(n)
                    Log.d(TAG, "RFCOMM read $n bytes hex=${chunk.toHexPreview()}")
                    emit(
                        mapOf(
                            "type" to "data",
                            "bytes" to chunk,
                        ),
                    )
                } catch (e: Exception) {
                    if (reading.get()) {
                        Log.e(TAG, "RFCOMM read failed", e)
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
            Log.i(TAG, "RFCOMM read loop exit")
        }
    }

    fun lastSocketSecure(): Boolean? = usedSecureSocket

    fun dispose() {
        Log.d(TAG, "dispose transport")
        disconnectInternal(emitState = false)
        connectIo.shutdownNow()
        readIo.shutdownNow()
    }

    private fun redactMac(mac: String): String {
        val parts = mac.split(":")
        if (parts.size < 3) return "••:••:••"
        return "••:••:••:" + parts.takeLast(3).joinToString(":")
    }
}

private fun ByteArray.toHexPreview(max: Int = 32): String {
    val n = minOf(size, max)
    val hex = take(n).joinToString("") { "%02X".format(it) }
    return if (size > max) "$hex…(+${size - max}B)" else hex
}
