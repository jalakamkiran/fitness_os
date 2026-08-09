package com.example.fitness_os.huawei

import android.util.Log

/**
 * TruSleep FileDownload collaborator skeleton (service `0x2c` / `0x0a`).
 *
 * Distinct from FeatureUpload (`0x28`). Soft-fails closed until a night capture
 * promotes `docs/wire-specs/huawei-br-gt5-sleep-files.md`. Never throws into
 * activity Sync; callers treat absent/skipped as enrich-not-present.
 *
 * Privacy: log filename + byte length only — never PPG/ACC payloads.
 */
class HuaweiFileDownload(
    private val exchangeEncrypted: (
        request: HuaweiFraming.Frame,
        expectService: Int,
        expectCmd: Int,
        timeoutMs: Long,
    ) -> HuaweiFraming.Frame?,
    private val isConnected: () -> Boolean = { true },
    /**
     * Soft-skip live exchanges until caps/capture promote the wire.
     * Tests may force an exchange attempt by setting true.
     */
    private val liveProbeEnabled: Boolean = false,
) {
    companion object {
        private const val TAG = "FOS_HUAWEI"
        const val SVC_LEGACY = 0x0a
        const val SVC_NEW = 0x2c
        /** Placeholder consult cmd — not normative until capture cites SS/CC. */
        const val CMD_FILE_CONSULT = 0x01
        private const val PROBE_TIMEOUT_MS = 3_000L
        const val FILE_SLEEP_STATE = "sleep_state"
        const val FILE_SLEEP_DATA = "sleep_data"
    }

    data class FileRef(
        val id: String,
        val len: Int,
    ) {
        fun toMap(): Map<String, Any?> = mapOf("id" to id, "len" to len)
    }

    data class ProbeOutcome(
        val status: String, // present | absent | skipped
        val serviceId: Int,
        val files: List<FileRef> = emptyList(),
        val reason: String? = null,
    ) {
        fun toMap(): Map<String, Any?> = buildMap {
            put("status", status)
            put("serviceId", serviceId)
            put("files", files.map { it.toMap() })
            if (reason != null) put("reason", reason)
        }
    }

    /**
     * Probe `sleep_state` then `sleep_data`. Soft-skip by default (no caps dump /
     * capture yet). When [liveProbeEnabled], attempt a short consult and treat
     * timeout/null as absent — never throws.
     */
    fun probeSleepFiles(preferNewSync: Boolean = true): ProbeOutcome {
        val serviceId = if (preferNewSync) SVC_NEW else SVC_LEGACY
        if (!isConnected()) {
            Log.i(TAG, "file-download probe skipped (disconnected) svc=0x${serviceId.toString(16)}")
            return ProbeOutcome(
                status = "skipped",
                serviceId = serviceId,
                reason = "disconnected",
            )
        }
        if (!liveProbeEnabled) {
            Log.i(
                TAG,
                "file-download probe soft-skip pending capture " +
                    "svc=0x${serviceId.toString(16)} " +
                    "files=$FILE_SLEEP_STATE,$FILE_SLEEP_DATA",
            )
            return ProbeOutcome(
                status = "skipped",
                serviceId = serviceId,
                reason = "pending_capture",
            )
        }
        return try {
            val present = ArrayList<FileRef>()
            for (name in listOf(FILE_SLEEP_STATE, FILE_SLEEP_DATA)) {
                val frame = exchangeEncrypted(
                    consultFrame(serviceId, name),
                    serviceId,
                    CMD_FILE_CONSULT,
                    PROBE_TIMEOUT_MS,
                )
                if (frame == null) {
                    Log.i(TAG, "file-download probe timeout name=$name len=?")
                    return ProbeOutcome(
                        status = "absent",
                        serviceId = serviceId,
                        reason = "timeout:$name",
                    )
                }
                val len = HuaweiFraming.encodeTlvs(frame.tlvs).size
                Log.i(TAG, "file-download probe rx name=$name len=$len")
                // Until wire-spec is promoted, any response is recorded as present
                // with length only — no PPG decode.
                present.add(FileRef(id = name, len = len))
            }
            ProbeOutcome(status = "present", serviceId = serviceId, files = present)
        } catch (t: Throwable) {
            Log.w(TAG, "file-download probe fail-closed: ${t.message}")
            ProbeOutcome(
                status = "absent",
                serviceId = serviceId,
                reason = "error",
            )
        }
    }

    private fun consultFrame(serviceId: Int, fileName: String): HuaweiFraming.Frame {
        val nameBytes = fileName.toByteArray(Charsets.UTF_8)
        return HuaweiFraming.Frame(
            serviceId = serviceId,
            commandId = CMD_FILE_CONSULT,
            tlvs = listOf(
                HuaweiFraming.Tlv(0x01, nameBytes),
            ),
        )
    }
}
