package com.example.fitness_os.huawei

import android.util.Log
import java.io.ByteArrayOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Gate A session orchestration (clean-room).
 *
 * Sends link-params after SDP connect. HiChain crypto is NOT independently
 * specified yet (see docs/wire-specs/huawei-br-gt5-gate-a.md) — auth fails
 * closed with R11 hints unless a prior auth_material secret exists from a
 * future capture-backed path.
 */
class HuaweiSession(
    private val transport: RfcommTransport,
    private val secrets: HuaweiSecretStore,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    companion object {
        private const val TAG = "HuaweiSession"
        private const val SERVICE_DEVICE_CONFIG = 0x01
        private const val CMD_LINK_PARAMS = 0x01
        private const val AUTH_TIMEOUT_MS = 20_000L
    }

    private val inbound = AtomicReference<CountDownLatch?>(null)
    private val lastFrame = AtomicReference<HuaweiFraming.Frame?>(null)
    private val reassembly = ByteArrayOutputStream()

    fun onRawBytes(bytes: ByteArray) {
        reassembly.write(bytes)
        drainBuffer()
    }

    private fun drainBuffer() {
        val buf = reassembly.toByteArray()
        var offset = 0
        while (offset < buf.size) {
            val slice = buf.copyOfRange(offset, buf.size)
            when (val result = HuaweiFraming.tryParse(slice)) {
                is HuaweiFraming.ParseResult.IncompleteFrame -> {
                    val remaining = buf.copyOfRange(offset, buf.size)
                    reassembly.reset()
                    reassembly.write(remaining)
                    return
                }
                is HuaweiFraming.ParseResult.Error -> {
                    Log.w(TAG, "frame error: ${result.reason}")
                    offset += 1 // resync attempt
                }
                is HuaweiFraming.ParseResult.Ok -> {
                    offset += result.bytesConsumed
                    lastFrame.set(result.frame)
                    inbound.get()?.countDown()
                    emit(
                        mapOf(
                            "type" to "session_frame",
                            "serviceId" to result.frame.serviceId,
                            "commandId" to result.frame.commandId,
                        ),
                    )
                }
            }
        }
        reassembly.reset()
    }

    /**
     * Run post-connect auth sequence. Call after RFCOMM is up.
     */
    fun authenticate(): SessionOutcome {
        emit(mapOf("type" to "session_state", "state" to "authenticating"))

        // If we already have persisted material from a prior successful path,
        // mark session ready (reconnect without re-deriving HiChain until captures land).
        if (secrets.hasSecrets() && !secrets.getAuthMaterial().isNullOrBlank()) {
            emit(mapOf("type" to "session_state", "state" to "session_ready"))
            return SessionOutcome.Ready
        }

        return try {
            val linkReq = HuaweiFraming.Frame(
                serviceId = SERVICE_DEVICE_CONFIG,
                commandId = CMD_LINK_PARAMS,
                tlvs = listOf(
                    HuaweiFraming.Tlv(0x01, byteArrayOf(0x02)), // protocol version hint
                ),
            )
            val encoded = HuaweiFraming.encode(linkReq)
            lastFrame.set(null)
            val latch = CountDownLatch(1)
            inbound.set(latch)
            transport.write(encoded)

            val got = latch.await(AUTH_TIMEOUT_MS, TimeUnit.MILLISECONDS)
            inbound.set(null)
            if (!got) {
                emitAuthFailed(
                    "Auth timeout waiting for link-params response",
                    hint = "r11_retry_or_account_id",
                )
                return SessionOutcome.AuthFailed
            }

            val response = lastFrame.get()
            if (response == null) {
                emitAuthFailed("Empty link-params response", hint = "r11_retry")
                return SessionOutcome.AuthFailed
            }

            // Crypto inventory incomplete: cannot complete HiChain challenge clean-room.
            // If owner supplied 17-digit userId, persist it for when captures unlock crypto.
            val userId = secrets.getUserId()
            if (!userId.isNullOrBlank() && userId.length == 17 && userId.all { it.isDigit() }) {
                emitAuthFailed(
                    "Account ID present but HiChain crypto not yet clean-room specified",
                    hint = "r11_hci_capture_needed",
                )
                return SessionOutcome.AuthFailed
            }

            emitAuthFailed(
                "HiChain auth not clean-room ready — provide 17-digit Huawei account userId or factory-reset path (R11)",
                hint = "r11_account_id_or_factory_reset",
            )
            SessionOutcome.AuthFailed
        } catch (e: Exception) {
            Log.e(TAG, "authenticate failed", e)
            emitAuthFailed(e.message ?: "authenticate failed", hint = "r11_retry")
            SessionOutcome.AuthFailed
        }
    }

    /**
     * Dev/test helper: mark session secrets present after a successful future auth path.
     * Not called from production auth until crypto inventory is complete.
     */
    fun persistSessionMaterialForTest(material: String) {
        secrets.setAuthMaterial(material)
    }

    private fun emitAuthFailed(message: String, hint: String) {
        emit(
            mapOf(
                "type" to "session_state",
                "state" to "auth_failed",
                "message" to message,
                "hint" to hint,
            ),
        )
    }

    enum class SessionOutcome {
        Ready,
        AuthFailed,
    }
}
