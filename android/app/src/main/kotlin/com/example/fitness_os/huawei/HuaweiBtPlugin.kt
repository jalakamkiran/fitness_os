package com.example.fitness_os.huawei

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class HuaweiBtPlugin(
    private val activity: Activity,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "fitness_os/huawei_bt"
        const val EVENT_CHANNEL = "fitness_os/huawei_bt_events"
        private const val PERMISSION_REQUEST = 4811
    }

    private var eventSink: EventChannel.EventSink? = null
    private var transport: RfcommTransport? = null
    private var secrets: HuaweiSecretStore? = null
    private var session: HuaweiSession? = null
    private var permissionResult: MethodChannel.Result? = null
    private val sessionIo = Executors.newSingleThreadExecutor()

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler(this)
        EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(this)

        secrets = HuaweiSecretStore(activity.applicationContext)
        transport = RfcommTransport(activity.applicationContext) { event ->
            forwardEvent(event)
        }
        session = HuaweiSession(
            transport = transport!!,
            secrets = secrets!!,
            emit = { event -> emitOnUi(event) },
        )
    }

    fun dispose() {
        transport?.dispose()
        transport = null
        session = null
        secrets = null
        eventSink = null
        sessionIo.shutdownNow()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        events?.success(
            mapOf(
                "type" to "adapter_state",
                "state" to (transport?.adapterState() ?: "unavailable"),
            ),
        )
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getAdapterState" -> result.success(transport?.adapterState() ?: "unavailable")
                "checkPermissions" -> result.success(hasAllPermissions())
                "requestPermissions" -> requestPermissions(result)
                "startBleDiscovery" -> {
                    ensurePermissions()
                    transport?.startBleDiscovery()
                    result.success(null)
                }
                "stopBleDiscovery" -> {
                    val emitDisconnected =
                        call.argument<Boolean>("emitDisconnected") ?: true
                    transport?.stopBleDiscovery(emitDisconnected = emitDisconnected)
                    result.success(null)
                }
                "connect" -> {
                    ensurePermissions()
                    val mac = call.argument<String>("mac")
                        ?: throw IllegalArgumentException("mac required")
                    val sdpUuid = call.argument<String>("sdpUuid")
                    transport?.connect(mac, sdpUuid)
                    result.success(null)
                }
                "authenticate" -> {
                    // Serialize on sessionIo — reject pile-up by checking transport.
                    sessionIo.execute {
                        val outcome = try {
                            if (transport?.isConnected() != true) {
                                android.util.Log.w(
                                    "FOS_HUAWEI",
                                    "authenticate skipped — not connected",
                                )
                                HuaweiSession.SessionOutcome.AuthFailed
                            } else {
                                session?.authenticate()
                            }
                        } catch (e: Exception) {
                            android.util.Log.e("FOS_HUAWEI", "authenticate error", e)
                            HuaweiSession.SessionOutcome.AuthFailed
                        }
                        activity.runOnUiThread {
                            result.success(outcome?.name ?: "AuthFailed")
                        }
                    }
                }
                "syncWorkouts" -> {
                    val startUnix = (call.argument<Number>("startUnix")?.toLong())
                        ?: HuaweiWorkoutSync.FALLBACK_START_UNIX
                    val endUnix = (call.argument<Number>("endUnix")?.toLong())
                        ?: (System.currentTimeMillis() / 1000L)
                    sessionIo.execute {
                        val payload = try {
                            if (transport?.isConnected() != true) {
                                mapOf(
                                    "status" to "not_ready",
                                    "message" to "Not connected",
                                    "workouts" to emptyList<Map<String, Any?>>(),
                                )
                            } else {
                                session?.syncWorkouts(startUnix, endUnix)
                                    ?: mapOf(
                                        "status" to "error",
                                        "message" to "No session",
                                        "workouts" to emptyList<Map<String, Any?>>(),
                                    )
                            }
                        } catch (e: Exception) {
                            android.util.Log.e("FOS_HUAWEI", "syncWorkouts error", e)
                            mapOf(
                                "status" to "error",
                                "message" to (e.message ?: "sync failed"),
                                "workouts" to emptyList<Map<String, Any?>>(),
                            )
                        }
                        activity.runOnUiThread { result.success(payload) }
                    }
                }
                "setAuthKey" -> {
                    val key = call.argument<String>("userId")?.trim().orEmpty()
                    when {
                        key.isEmpty() -> {
                            secrets?.setUserId(null)
                            secrets?.setPhoneMac(null)
                        }
                        HuaweiSecretStore.looksLikeMac(key) -> {
                            secrets?.setPhoneMac(key)
                            android.util.Log.i(
                                "FOS_HUAWEI",
                                "stored phone MAC override (privacy-MAC workaround)",
                            )
                        }
                        else -> secrets?.setUserId(key)
                    }
                    result.success(null)
                }
                "hasSecrets" -> result.success(secrets?.hasSecrets() == true)
                "clearSecrets" -> {
                    secrets?.clearSecrets()
                    result.success(null)
                }
                "write" -> {
                    if (!isDebuggable()) {
                        result.error("debug_only", "write(bytes) is debug-only", null)
                        return
                    }
                    val bytes = call.argument<ByteArray>("bytes")
                        ?: throw IllegalArgumentException("bytes required")
                    transport?.write(bytes)
                    result.success(null)
                }
                "disconnect" -> {
                    transport?.disconnect()
                    result.success(null)
                }
                "lastSocketSecure" -> result.success(transport?.lastSocketSecure())
                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            result.error("permission_denied", e.message, null)
        } catch (e: IllegalStateException) {
            result.error("illegal_state", e.message, null)
        } catch (e: Exception) {
            result.error("error", e.message, null)
        }
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val ok = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        permissionResult?.success(ok)
        permissionResult = null
        return true
    }

    private fun forwardEvent(event: Map<String, Any?>) {
        val type = event["type"] as? String
        if (type == "data") {
            val bytes = event["bytes"] as? ByteArray
            if (bytes != null) {
                session?.onRawBytes(bytes)
            }
        }
        emitOnUi(event)
    }

    private fun emitOnUi(event: Map<String, Any?>) {
        activity.runOnUiThread {
            eventSink?.success(event)
        }
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        if (hasAllPermissions()) {
            result.success(true)
            return
        }
        permissionResult = result
        ActivityCompat.requestPermissions(activity, requiredPermissions(), PERMISSION_REQUEST)
    }

    private fun ensurePermissions() {
        if (!hasAllPermissions()) {
            throw SecurityException("Bluetooth permissions required")
        }
    }

    private fun hasAllPermissions(): Boolean {
        return requiredPermissions().all {
            ContextCompat.checkSelfPermission(activity, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requiredPermissions(): Array<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
            )
        } else {
            arrayOf(
                Manifest.permission.BLUETOOTH,
                Manifest.permission.BLUETOOTH_ADMIN,
                Manifest.permission.ACCESS_FINE_LOCATION,
            )
        }
    }

    private fun isDebuggable(): Boolean {
        return (activity.applicationInfo.flags and
            android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }
}
