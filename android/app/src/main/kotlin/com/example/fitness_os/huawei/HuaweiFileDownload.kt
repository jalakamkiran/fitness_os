package com.example.fitness_os.huawei

import android.util.Log
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale

/**
 * TruSleep FileDownload collaborator (service `0x2c` new-sync / `0x0a` legacy).
 *
 * Distinct from FeatureUpload (`0x28`). Clean-room SM from public LPv2 /
 * community wire shapes (init → info → block×N → complete). Never throws into
 * activity Sync; callers treat absent/skipped as enrich-not-present.
 *
 * Privacy: log filename + byte length + sleep_state interval unix ranges only —
 * never PPG/ACC payloads.
 */
class HuaweiFileDownload(
    private val exchangeEncrypted: (
        request: HuaweiFraming.Frame,
        expectService: Int,
        expectCmd: Int,
        timeoutMs: Long,
    ) -> HuaweiFraming.Frame?,
    /** Fire-and-forget encrypted TLV frame (block request). */
    private val sendEncrypted: (HuaweiFraming.Frame) -> Unit = {},
    /** Fire-and-forget plaintext TLV frame (block request when noEncrypt). */
    private val sendPlain: (HuaweiFraming.Frame) -> Unit = {},
    /**
     * Await next FileDownload block push (`cmd=0x05`) raw body
     * (fileId + offset + unk + data), already decrypted.
     */
    private val awaitRawBlock: (serviceId: Int, timeoutMs: Long) -> ByteArray? = { _, _ -> null },
    private val isConnected: () -> Boolean = { true },
    /**
     * Soft-skip live exchanges until caps/capture promote the wire.
     * Product Sync enables live download.
     */
    private val liveDownloadEnabled: Boolean = false,
    /** Persist downloaded bytes under app-private storage; return relative path or null. */
    private val persistFile: ((id: String, bytes: ByteArray) -> String?)? = null,
    /** Format unix with last synced watch zone (falls back to phone default). */
    private val formatUnix: (unixSec: Int) -> String = { unix ->
        java.text.SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US)
            .apply { timeZone = java.util.TimeZone.getDefault() }
            .format(java.util.Date(unix.toLong() * 1000L))
    },
    private val watchZoneLabel: () -> String = {
        val tz = java.util.TimeZone.getDefault()
        val off = tz.rawOffset + tz.dstSavings
        val sign = if (off >= 0) "+" else "-"
        val abs = kotlin.math.abs(off) / 1000
        val h = abs / 3600
        val m = (abs / 60) % 60
        "${tz.id} UTC$sign${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}"
    },
) {
    companion object {
        private const val TAG = "FOS_HUAWEI"
        const val SVC_LEGACY = 0x0a
        const val SVC_NEW = 0x2c
        const val CMD_INIT = 0x01
        const val CMD_INFO = 0x03
        const val CMD_REQUEST_BLOCK = 0x04
        const val CMD_BLOCK = 0x05
        const val CMD_COMPLETE = 0x06
        private const val STEP_TIMEOUT_MS = 8_000L
        private const val BLOCK_TIMEOUT_MS = 20_000L
        private const val PROGRESS_EVERY_BYTES = 64 * 1024
        const val FILE_SLEEP_STATE = "sleep_state.bin"
        const val FILE_SLEEP_DATA = "sleep_data.bin"
        /** New-sync SEQUENCE_DATA basename (dict-class pull; not sleep_data.bin). */
        const val FILE_SEQUENCE_DATA = "sequence_data"
        const val TYPE_SLEEP_STATE: Byte = 0x0e
        const val TYPE_SLEEP_DATA: Byte = 0x0f
        /** FileDownload type byte for dict/sequence pulls (community wire: SEQUENCE_DATA). */
        const val TYPE_SEQUENCE_DATA: Byte = 0x16
        /**
         * SLEEP_DETAILS dict class id for TruSleep summary+stages on HarmonyOS 5+
         * devices (community behavioral id — clean-room invent, not AGPL paste).
         */
        const val DICT_SLEEP_DETAILS_CLASS: Int = 700_013
        private const val BLOCK_HEADER_LEN = 6 // fileId + offset + unk
        private const val STATE_RECORD_LEN = 16

        private val OVERNIGHT_SUMMARY_KEY_HINTS = setOf(
            "avghrv", "avgheartrate", "avgbreathrate", "avgoxygensaturation",
            "hrv", "respiratoryrate", "spo2", "sleephr", "rmssd",
        )

        /**
         * Known SLEEP_DETAILS field ids (names only). Presence scan is privacy-safe —
         * reports `dictField:<id>` without values.
         */
        private val SLEEP_DETAILS_FIELD_IDS: Map<Int, String> = mapOf(
            700_013_245 to "sleepScore",
            700_013_436 to "minHeartRate",
            700_013_468 to "avgOxygenSaturation",
            700_013_492 to "maxBreathRate",
            700_013_502 to "maxHeartRate",
            700_013_580 to "avgHeartRate",
            700_013_646 to "minBreathRate",
            700_013_878 to "avgHrv",
            700_013_886 to "avgBreathRate",
            700_013_026 to "maxOxygenSaturation",
            700_013_340 to "minOxygenSaturation",
        )

        /**
         * Parse sleep_state.bin LE records (start u32, end u32, 8 B pad).
         * Privacy-safe — returns unix pairs only.
         */
        fun parseSleepStateIntervals(stateData: ByteArray): List<StateInterval> {
            if (stateData.size < STATE_RECORD_LEN) return emptyList()
            val buf = ByteBuffer.wrap(stateData).order(ByteOrder.LITTLE_ENDIAN)
            val out = ArrayList<StateInterval>()
            while (stateData.size - buf.position() >= STATE_RECORD_LEN) {
                val start = buf.int
                val end = buf.int
                buf.position(buf.position() + 8)
                if (end > start && start > 0) {
                    out.add(StateInterval(beginUnix = start, endUnix = end))
                }
            }
            return out
        }

        /**
         * Privacy-safe binary inventory: TLV-like tag histogram + printable key runs.
         * Never returns payload bodies or numeric series.
         */
        fun observeBinaryStructure(bytes: ByteArray): StructureObserve {
            val hist = linkedMapOf<Int, Pair<Int, Int>>() // tag -> (count, totalLen)
            var i = 0
            while (i + 3 <= bytes.size) {
                val tag = bytes[i].toInt() and 0xFF
                val len = (bytes[i + 1].toInt() and 0xFF) or
                    ((bytes[i + 2].toInt() and 0xFF) shl 8)
                if (len <= 0 || i + 3 + len > bytes.size) {
                    i++
                    continue
                }
                val prev = hist[tag]
                hist[tag] = if (prev == null) {
                    1 to len
                } else {
                    (prev.first + 1) to (prev.second + len)
                }
                i += 3 + len
            }
            val tagHistogram = hist.entries
                .sortedByDescending { it.value.second }
                .take(32)
                .map { (tag, pair) ->
                    mapOf(
                        "tag" to tag,
                        "count" to pair.first,
                        "totalLen" to pair.second,
                    )
                }
            val keys = extractRedactedKeys(bytes).toMutableList()
            val dictFields = scanSleepDetailsFieldIds(bytes)
            for (name in dictFields) {
                if (!keys.contains(name)) keys.add(name)
            }
            val overnight = linkedSetOf<String>()
            for (key in keys) {
                if (OVERNIGHT_SUMMARY_KEY_HINTS.any { hint ->
                        key.lowercase(Locale.US).contains(hint)
                    }
                ) {
                    overnight.add(key)
                }
            }
            overnight.addAll(dictFields)
            return StructureObserve(
                status = "present",
                serviceId = SVC_NEW,
                id = "structure",
                len = bytes.size,
                tagHistogram = tagHistogram,
                redactedKeys = keys.take(64),
                overnightSummaryKeys = overnight.toList().take(64),
            )
        }

        /** Scan LE/BE u32 for known SLEEP_DETAILS field ids — names only, no values. */
        fun scanSleepDetailsFieldIds(bytes: ByteArray): List<String> {
            if (bytes.size < 4) return emptyList()
            val found = linkedSetOf<String>()
            fun consider(id: Int) {
                val name = SLEEP_DETAILS_FIELD_IDS[id] ?: return
                found.add(name)
            }
            var i = 0
            while (i + 4 <= bytes.size) {
                val be = ((bytes[i].toInt() and 0xFF) shl 24) or
                    ((bytes[i + 1].toInt() and 0xFF) shl 16) or
                    ((bytes[i + 2].toInt() and 0xFF) shl 8) or
                    (bytes[i + 3].toInt() and 0xFF)
                val le = (bytes[i].toInt() and 0xFF) or
                    ((bytes[i + 1].toInt() and 0xFF) shl 8) or
                    ((bytes[i + 2].toInt() and 0xFF) shl 16) or
                    ((bytes[i + 3].toInt() and 0xFF) shl 24)
                consider(be)
                consider(le)
                i++
            }
            return found.toList()
        }

        fun extractRedactedKeys(bytes: ByteArray): List<String> {
            val text = runCatching { String(bytes, Charsets.UTF_8) }.getOrNull().orEmpty()
            val fromJson = Regex("\"([A-Za-z_][A-Za-z0-9_]{1,63})\"\\s*:")
                .findAll(text)
                .map { it.groupValues[1] }
                .toList()
            if (fromJson.isNotEmpty()) {
                // Prefer JSON object keys only — never quoted string values.
                return fromJson.distinct().take(64)
            }
            val fromAscii = Regex("[A-Za-z_][A-Za-z0-9_]{2,31}")
                .findAll(text)
                .map { it.value }
                .filter { candidate ->
                    candidate.any { it.isLowerCase() } || candidate.any { it.isUpperCase() }
                }
                .toList()
            return fromAscii.distinct().take(64)
        }

        /** Redacted JSON/ASCII key inventory — names only; never values. */
        fun redactedJsonKeyInventory(bytes: ByteArray): List<String> = extractRedactedKeys(bytes)
    }

    data class StateInterval(
        val beginUnix: Int,
        val endUnix: Int,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "beginUnix" to beginUnix,
            "endUnix" to endUnix,
        )
    }

    data class FileRef(
        val id: String,
        val len: Int,
        val path: String? = null,
    ) {
        fun toMap(): Map<String, Any?> = buildMap {
            put("id", id)
            put("len", len)
            if (path != null) put("path", path)
        }
    }

    data class ProbeOutcome(
        val status: String, // present | absent | skipped
        val serviceId: Int,
        val files: List<FileRef> = emptyList(),
        val stateIntervals: List<StateInterval> = emptyList(),
        /**
         * Parsed SLEEP_DETAILS SEQUENCE_DATA sessions (structured maps only —
         * never raw bodies). Empty when SEQUENCE absent/fail.
         */
        val sequenceSessions: List<Map<String, Any?>> = emptyList(),
        val reason: String? = null,
    ) {
        fun toMap(): Map<String, Any?> = buildMap {
            put("status", status)
            put("serviceId", serviceId)
            put("files", files.map { it.toMap() })
            if (stateIntervals.isNotEmpty()) {
                put("stateIntervals", stateIntervals.map { it.toMap() })
            }
            if (sequenceSessions.isNotEmpty()) {
                put("sequenceSessions", sequenceSessions)
            }
            if (reason != null) put("reason", reason)
        }
    }

    private data class SleepFileSpec(
        val fileName: String,
        val fileType: Byte,
        val shortId: String,
        /** Dict class for SEQUENCE_DATA (`0x16`); 0 = omit TLV `0x0c`. */
        val dictId: Int = 0,
    )

    data class StructureObserve(
        val status: String, // present | absent | skipped
        val serviceId: Int,
        val id: String,
        val len: Int = 0,
        /** Privacy-safe tag+count+totalLen rows — never body bytes. */
        val tagHistogram: List<Map<String, Any?>> = emptyList(),
        /** Printable identifier-like runs / JSON keys — names only. */
        val redactedKeys: List<String> = emptyList(),
        /** Keys that look like typed overnight-summary scalars (names only). */
        val overnightSummaryKeys: List<String> = emptyList(),
        /** Relative path when [persistFile] wrote the body (debug keep-cut). */
        val path: String? = null,
        val reason: String? = null,
    ) {
        /** Tag+len histogram and identifier names only — never values or bodies. */
        fun privacyInventoryLog(): String {
            val hist = tagHistogram.joinToString(",") { row ->
                "t=${row["tag"]}:n=${row["count"]}:len=${row["totalLen"]}"
            }
            val names = redactedKeys.joinToString(",")
            return "tagHist=[$hist] keyNames=[$names]"
        }

        fun toMap(): Map<String, Any?> = buildMap {
            put("status", status)
            put("serviceId", serviceId)
            put("id", id)
            put("len", len)
            put("tagHistogram", tagHistogram)
            put("redactedKeys", redactedKeys)
            put("overnightSummaryKeys", overnightSummaryKeys)
            if (path != null) put("path", path)
            if (reason != null) put("reason", reason)
        }
    }

    /**
     * Download `sleep_state.bin` + optional SEQUENCE_DATA SLEEP_DETAILS over
     * FileDownload new-sync (`0x2c`). SEQUENCE body is parsed then wiped —
     * only structured session maps cross the channel.
     * Legacy (`0x0a`) list path remains soft-absent until owned.
     */
    fun downloadSleepFiles(
        preferNewSync: Boolean = true,
        startUnix: Int = 0,
        endUnix: Int = (System.currentTimeMillis() / 1000L).toInt(),
    ): ProbeOutcome {
        val serviceId = if (preferNewSync) SVC_NEW else SVC_LEGACY
        if (!isConnected()) {
            Log.i(TAG, "file-download skipped (disconnected) svc=0x${serviceId.toString(16)}")
            return ProbeOutcome(
                status = "skipped",
                serviceId = serviceId,
                reason = "disconnected",
            )
        }
        if (!liveDownloadEnabled) {
            Log.i(
                TAG,
                "file-download soft-skip pending capture " +
                    "svc=0x${serviceId.toString(16)} " +
                    "files=$FILE_SLEEP_STATE,$FILE_SEQUENCE_DATA",
            )
            return ProbeOutcome(
                status = "skipped",
                serviceId = serviceId,
                reason = "pending_capture",
            )
        }
        if (!preferNewSync) {
            Log.i(TAG, "file-download legacy svc=0x0a not implemented — absent")
            return ProbeOutcome(
                status = "absent",
                serviceId = serviceId,
                reason = "legacy_unimplemented",
            )
        }
        return try {
            val present = ArrayList<FileRef>()
            var stateIntervals: List<StateInterval> = emptyList()
            var sequenceSessions: List<Map<String, Any?>> = emptyList()
            var lastReason: String? = null

            // 1) sleep_state — timing SoT
            val stateSpec = SleepFileSpec(FILE_SLEEP_STATE, TYPE_SLEEP_STATE, "sleep_state")
            val stateBytes = downloadOneNewSync(serviceId, stateSpec, startUnix, endUnix)
            when {
                stateBytes == null -> {
                    lastReason = "fail:sleep_state"
                    Log.i(TAG, "file-download miss name=${stateSpec.fileName}")
                }
                stateBytes.isEmpty() -> {
                    Log.i(TAG, "file-download empty name=${stateSpec.fileName} len=0")
                }
                else -> {
                    Log.i(TAG, "file-download ok name=${stateSpec.fileName} len=${stateBytes.size}")
                    stateIntervals = parseSleepStateIntervals(stateBytes)
                    logSleepStateIntervals(stateIntervals, raw = stateBytes)
                    val path = try {
                        persistFile?.invoke(stateSpec.shortId, stateBytes)
                    } catch (t: Throwable) {
                        Log.w(TAG, "file-download persist fail id=${stateSpec.shortId}: ${t.message}")
                        null
                    }
                    present.add(
                        FileRef(id = stateSpec.shortId, len = stateBytes.size, path = path),
                    )
                }
            }

            // 2) SEQUENCE_DATA — TruSleep summary + stages (parse, wipe; soft-fail)
            val seqSpec = SleepFileSpec(
                FILE_SEQUENCE_DATA,
                TYPE_SEQUENCE_DATA,
                "sequence_data",
                dictId = DICT_SLEEP_DETAILS_CLASS,
            )
            val seqBytes = downloadOneNewSync(serviceId, seqSpec, startUnix, endUnix)
            when {
                seqBytes == null -> {
                    Log.i(TAG, "file-download miss name=${seqSpec.fileName} (soft)")
                }
                seqBytes.isEmpty() -> {
                    Log.i(TAG, "file-download empty name=${seqSpec.fileName} len=0 (soft)")
                }
                else -> {
                    Log.i(TAG, "file-download ok name=${seqSpec.fileName} len=${seqBytes.size}")
                    val parsed = HuaweiSleepDetailsSequenceParser.parse(seqBytes)
                    if (parsed != null && parsed.sessions.isNotEmpty()) {
                        sequenceSessions = parsed.sessions.map { it.toMap() }
                        Log.i(
                            TAG,
                            "file-download sequence parsed sessions=${parsed.sessions.size} " +
                                "scores=${parsed.sessions.mapNotNull { it.sleepScore }}",
                        )
                        present.add(
                            FileRef(id = seqSpec.shortId, len = seqBytes.size, path = null),
                        )
                    } else {
                        Log.i(TAG, "file-download sequence present but parse empty")
                    }
                    seqBytes.fill(0)
                }
            }

            if (present.isEmpty() && stateIntervals.isEmpty() && sequenceSessions.isEmpty()) {
                ProbeOutcome(
                    status = "absent",
                    serviceId = serviceId,
                    reason = lastReason ?: "empty",
                )
            } else if (stateIntervals.isEmpty() && sequenceSessions.isEmpty()) {
                // Files present without usable SoT — still report present refs.
                ProbeOutcome(
                    status = "present",
                    serviceId = serviceId,
                    files = present,
                    reason = lastReason,
                )
            } else {
                ProbeOutcome(
                    status = "present",
                    serviceId = serviceId,
                    files = present,
                    stateIntervals = stateIntervals,
                    sequenceSessions = sequenceSessions,
                )
            }
        } catch (t: Throwable) {
            Log.w(TAG, "file-download fail-closed: ${t.message}")
            ProbeOutcome(
                status = "absent",
                serviceId = serviceId,
                reason = "error",
            )
        }
    }

    /**
     * Diagnostic FileDownload pull for an invented dict/sequence filename.
     * Observes redacted keys then wipes the body — never feeds product SoT.
     *
     * For HarmonyOS 5+ TruSleep stages/summaries, prefer
     * [FILE_SEQUENCE_DATA] + [TYPE_SEQUENCE_DATA] + [DICT_SLEEP_DETAILS_CLASS]
     * (not bare `SLEEP_DETAILS` / type `0x00` invents).
     */
    fun downloadDiagnosticNamedFileObserve(
        fileName: String,
        fileType: Byte,
        shortId: String,
        startUnix: Int = 0,
        endUnix: Int = (System.currentTimeMillis() / 1000L).toInt(),
        dictId: Int = 0,
        persist: Boolean = false,
    ): StructureObserve {
        val serviceId = SVC_NEW
        if (!isConnected()) {
            return StructureObserve(
                status = "skipped",
                serviceId = serviceId,
                id = shortId,
                reason = "disconnected",
            )
        }
        if (!liveDownloadEnabled) {
            return StructureObserve(
                status = "skipped",
                serviceId = serviceId,
                id = shortId,
                reason = "pending_capture",
            )
        }
        return try {
            val spec = SleepFileSpec(fileName, fileType, shortId, dictId = dictId)
            val result = downloadOneNewSync(serviceId, spec, startUnix, endUnix)
            when {
                result == null -> StructureObserve(
                    status = "absent",
                    serviceId = serviceId,
                    id = shortId,
                    reason = "fail:$shortId",
                )
                result.isEmpty() -> StructureObserve(
                    status = "absent",
                    serviceId = serviceId,
                    id = shortId,
                    reason = "empty",
                )
                else -> {
                    val observed = observeBinaryStructure(result)
                    Log.i(
                        TAG,
                        "file-download diagnostic ok name=$fileName " +
                            "type=${fileType.toInt() and 0xFF} dictId=$dictId " +
                            "len=${result.size} ${observed.privacyInventoryLog()}",
                    )
                    var path: String? = null
                    var persistReason: String? = null
                    if (persist) {
                        val writer = persistFile
                        if (writer == null) {
                            persistReason = "persist_unavailable"
                        } else {
                            path = writer(shortId, result)
                            if (path == null) persistReason = "persist_failed"
                        }
                    }
                    result.fill(0)
                    StructureObserve(
                        status = "present",
                        serviceId = serviceId,
                        id = shortId,
                        len = observed.len,
                        tagHistogram = observed.tagHistogram,
                        redactedKeys = observed.redactedKeys,
                        overnightSummaryKeys = observed.overnightSummaryKeys,
                        path = path,
                        reason = persistReason,
                    )
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "file-download diagnostic fail-closed: ${t.message}")
            StructureObserve(
                status = "absent",
                serviceId = serviceId,
                id = shortId,
                reason = "error",
            )
        }
    }

    /**
     * Diagnostic one-shot: SEQUENCE_DATA (`0x16`) + SLEEP_DETAILS dict class.
     * Privacy-safe observe — never product SoT.
     *
     * When [persist] is true and [persistFile] is set, writes
     * `vitals/sleep_files/sequence_data.bin` before wiping memory.
     */
    fun downloadSleepDetailsSequenceObserve(
        startUnix: Int = 0,
        endUnix: Int = (System.currentTimeMillis() / 1000L).toInt(),
        persist: Boolean = false,
    ): StructureObserve =
        downloadDiagnosticNamedFileObserve(
            fileName = FILE_SEQUENCE_DATA,
            fileType = TYPE_SEQUENCE_DATA,
            shortId = "sequence_data",
            startUnix = startUnix,
            endUnix = endUnix,
            dictId = DICT_SLEEP_DETAILS_CLASS,
            persist = persist,
        )

    /**
     * Post-Sync diagnostic: download `sleep_data.bin`, observe structure, then wipe body.
     * Never adds sleep_data to product [downloadSleepFiles] specs.
     *
     * When [persist] is true and [persistFile] is set, writes the body under
     * `vitals/sleep_files/` **before** wiping memory (debug keep-cut only).
     */
    fun downloadSleepDataStructureObserve(
        startUnix: Int = 0,
        endUnix: Int = (System.currentTimeMillis() / 1000L).toInt(),
        wipeBody: ((ByteArray) -> Unit)? = null,
        persist: Boolean = false,
    ): StructureObserve {
        val serviceId = SVC_NEW
        val id = "sleep_data"
        if (!isConnected()) {
            return StructureObserve(
                status = "skipped",
                serviceId = serviceId,
                id = id,
                reason = "disconnected",
            )
        }
        if (!liveDownloadEnabled) {
            return StructureObserve(
                status = "skipped",
                serviceId = serviceId,
                id = id,
                reason = "pending_capture",
            )
        }
        return try {
            val spec = SleepFileSpec(FILE_SLEEP_DATA, TYPE_SLEEP_DATA, id)
            val result = downloadOneNewSync(serviceId, spec, startUnix, endUnix)
            when {
                result == null -> StructureObserve(
                    status = "absent",
                    serviceId = serviceId,
                    id = id,
                    reason = "fail:$id",
                )
                result.isEmpty() -> StructureObserve(
                    status = "absent",
                    serviceId = serviceId,
                    id = id,
                    reason = "empty",
                )
                else -> {
                    var path: String? = null
                    var persistReason: String? = null
                    if (persist) {
                        path = try {
                            persistFile?.invoke(id, result)
                        } catch (t: Throwable) {
                            Log.w(TAG, "file-download sleep_data persist fail: ${t.message}")
                            null
                        }
                        if (path == null) {
                            persistReason = if (persistFile == null) {
                                "persist_callback_missing"
                            } else {
                                "persist_failed"
                            }
                        }
                    }
                    val observed = observeBinaryStructure(result)
                    Log.i(
                        TAG,
                        "file-download sleep_data observe len=${result.size} " +
                            "persist=${persist} path=$path " +
                            observed.privacyInventoryLog(),
                    )
                    try {
                        wipeBody?.invoke(result)
                    } catch (t: Throwable) {
                        Log.w(TAG, "file-download sleep_data wipe fail: ${t.message}")
                    }
                    // Overwrite buffer in-place when possible (caller still holds ref).
                    result.fill(0)
                    StructureObserve(
                        status = "present",
                        serviceId = serviceId,
                        id = id,
                        len = observed.len,
                        tagHistogram = observed.tagHistogram,
                        redactedKeys = observed.redactedKeys,
                        overnightSummaryKeys = observed.overnightSummaryKeys,
                        path = path,
                        reason = persistReason,
                    )
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "file-download sleep_data observe fail-closed: ${t.message}")
            StructureObserve(
                status = "absent",
                serviceId = serviceId,
                id = id,
                reason = "error",
            )
        }
    }

    /** @deprecated Use [downloadSleepFiles]. Kept for older call sites/tests. */
    fun probeSleepFiles(preferNewSync: Boolean = true): ProbeOutcome =
        downloadSleepFiles(preferNewSync = preferNewSync)

    private fun downloadOneNewSync(
        serviceId: Int,
        spec: SleepFileSpec,
        startUnix: Int,
        endUnix: Int,
    ): ByteArray? {
        val init = exchangeEncrypted(
            initFrame(
                serviceId,
                spec.fileName,
                spec.fileType,
                startUnix,
                endUnix,
                dictId = spec.dictId,
            ),
            serviceId,
            CMD_INIT,
            STEP_TIMEOUT_MS,
        ) ?: run {
            Log.i(TAG, "file-download init timeout name=${spec.fileName}")
            return null
        }
        val fileId = asByte(init, 0x03) ?: 0
        val fileSize = asInt(init, 0x04) ?: 0
        Log.i(
            TAG,
            "file-download init name=${spec.fileName} type=${spec.fileType.toInt() and 0xFF} " +
                "dictId=${spec.dictId} id=${fileId.toInt() and 0xFF} size=$fileSize",
        )
        if (fileSize <= 0) {
            sendComplete(serviceId, fileId)
            return ByteArray(0)
        }

        val info = exchangeEncrypted(
            infoFrame(serviceId, fileId),
            serviceId,
            CMD_INFO,
            STEP_TIMEOUT_MS,
        ) ?: run {
            Log.i(TAG, "file-download info timeout name=${spec.fileName}")
            return null
        }
        val timeoutSec = (asByte(info, 0x02)?.toInt()?.and(0xFF) ?: 20).coerceIn(5, 120)
        val maxBlockSize = (asInt(info, 0x04) ?: 1024).coerceAtLeast(64)
        val noEncrypt = (asByte(info, 0x05)?.toInt()?.and(0xFF) ?: 0) != 0
        Log.i(
            TAG,
            "file-download info name=${spec.fileName} " +
                "maxBlock=$maxBlockSize timeoutSec=$timeoutSec noEncrypt=$noEncrypt",
        )

        val buffer = ByteArray(fileSize)
        var offset = 0
        var nextProgress = PROGRESS_EVERY_BYTES
        val chunkTimeoutMs = (timeoutSec * 1000L).coerceAtLeast(BLOCK_TIMEOUT_MS)
        while (offset < fileSize) {
            val blockSize = minOf(fileSize - offset, maxBlockSize)
            val blockReq = blockRequestFrame(
                serviceId,
                fileId,
                offset,
                blockSize,
                dictId = spec.dictId,
                fileType = spec.fileType,
            )
            synchronizedQueueClearThenSend(blockReq, noEncrypt)
            var blockGot = 0
            while (blockGot < blockSize && offset + blockGot < fileSize) {
                val raw = awaitRawBlock(serviceId, chunkTimeoutMs)
                    ?: run {
                        Log.w(
                            TAG,
                            "file-download block timeout/null name=${spec.fileName} " +
                                "at=${offset + blockGot}/$fileSize",
                        )
                        return null
                    }
                val chunk = parseBlockChunk(raw, fileId) ?: continue
                if (chunk.offset != offset + blockGot) {
                    Log.w(
                        TAG,
                        "file-download offset mismatch want=${offset + blockGot} got=${chunk.offset}",
                    )
                    return null
                }
                if (offset + blockGot + chunk.data.size > fileSize) {
                    Log.w(TAG, "file-download overrun name=${spec.fileName}")
                    return null
                }
                System.arraycopy(chunk.data, 0, buffer, offset + blockGot, chunk.data.size)
                blockGot += chunk.data.size
                val got = offset + blockGot
                if (got >= nextProgress || got >= fileSize) {
                    Log.i(
                        TAG,
                        "file-download progress name=${spec.fileName} $got/$fileSize",
                    )
                    nextProgress = got + PROGRESS_EVERY_BYTES
                }
            }
            offset += blockGot
        }

        sendComplete(serviceId, fileId)
        return buffer
    }

    private fun synchronizedQueueClearThenSend(frame: HuaweiFraming.Frame, noEncrypt: Boolean) {
        if (noEncrypt) sendPlain(frame) else sendEncrypted(frame)
    }

    private fun sendComplete(serviceId: Int, fileId: Byte) {
        val frame = HuaweiFraming.Frame(
            serviceId = serviceId,
            commandId = CMD_COMPLETE,
            tlvs = listOf(
                HuaweiFraming.Tlv(0x01, byteArrayOf(fileId)),
                HuaweiFraming.Tlv(0x02, byteArrayOf(0x01)),
            ),
        )
        sendEncrypted(frame)
    }

    private fun initFrame(
        serviceId: Int,
        fileName: String,
        fileType: Byte,
        startUnix: Int,
        endUnix: Int,
        dictId: Int = 0,
    ): HuaweiFraming.Frame {
        val tlvs = ArrayList<HuaweiFraming.Tlv>(5)
        tlvs.add(HuaweiFraming.Tlv(0x01, fileName.toByteArray(Charsets.UTF_8)))
        tlvs.add(HuaweiFraming.Tlv(0x02, byteArrayOf(fileType)))
        tlvs.add(HuaweiFraming.Tlv(0x05, HuaweiPacketCrypto.intBe(startUnix)))
        tlvs.add(HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.intBe(endUnix)))
        // SEQUENCE_DATA dict-class invent: TLV 0x0c = dictId (community wire shape).
        if (dictId > 0 && fileType == TYPE_SEQUENCE_DATA) {
            tlvs.add(HuaweiFraming.Tlv(0x0c, HuaweiPacketCrypto.intBe(dictId)))
        }
        return HuaweiFraming.Frame(
            serviceId = serviceId,
            commandId = CMD_INIT,
            tlvs = tlvs,
        )
    }

    private fun infoFrame(serviceId: Int, fileId: Byte): HuaweiFraming.Frame =
        HuaweiFraming.Frame(
            serviceId = serviceId,
            commandId = CMD_INFO,
            tlvs = listOf(
                HuaweiFraming.Tlv(0x01, byteArrayOf(fileId)),
                HuaweiFraming.Tlv(0x02, byteArrayOf()),
                HuaweiFraming.Tlv(0x03, byteArrayOf()),
                HuaweiFraming.Tlv(0x04, byteArrayOf()),
                HuaweiFraming.Tlv(0x05, byteArrayOf()),
            ),
        )

    private fun blockRequestFrame(
        serviceId: Int,
        fileId: Byte,
        offset: Int,
        size: Int,
        dictId: Int = 0,
        fileType: Byte = 0,
    ): HuaweiFraming.Frame {
        val tlvs = ArrayList<HuaweiFraming.Tlv>(4)
        tlvs.add(HuaweiFraming.Tlv(0x01, byteArrayOf(fileId)))
        tlvs.add(HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.intBe(offset)))
        tlvs.add(HuaweiFraming.Tlv(0x03, HuaweiPacketCrypto.intBe(size)))
        // SEQUENCE_DATA block req may carry dictId on TLV 0x04.
        if (dictId > 0 &&
            (fileType == TYPE_SEQUENCE_DATA || fileId == TYPE_SEQUENCE_DATA)
        ) {
            tlvs.add(HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(dictId)))
        }
        return HuaweiFraming.Frame(
            serviceId = serviceId,
            commandId = CMD_REQUEST_BLOCK,
            tlvs = tlvs,
        )
    }

    private data class BlockChunk(val offset: Int, val data: ByteArray)

    private fun parseBlockChunk(raw: ByteArray, expectFileId: Byte): BlockChunk? {
        if (raw.size < BLOCK_HEADER_LEN) {
            Log.w(TAG, "file-download block too short len=${raw.size}")
            return null
        }
        val buf = ByteBuffer.wrap(raw).order(ByteOrder.BIG_ENDIAN)
        val fileId = buf.get()
        if (fileId != expectFileId) {
            Log.w(
                TAG,
                "file-download fileId mismatch want=${expectFileId.toInt() and 0xFF} " +
                    "got=${fileId.toInt() and 0xFF}",
            )
            return null
        }
        val offset = buf.int
        buf.get() // unknown
        val data = ByteArray(buf.remaining())
        buf.get(data)
        return BlockChunk(offset = offset, data = data)
    }

    private fun logSleepStateIntervals(
        intervals: List<StateInterval>,
        raw: ByteArray,
    ) {
        val zone = watchZoneLabel()
        Log.i(
            TAG,
            "file-download sleep_state rawLen=${raw.size} zone=$zone",
        )
        if (intervals.isEmpty()) {
            Log.i(TAG, "file-download sleep_state intervals=0")
            return
        }
        Log.i(TAG, "file-download sleep_state intervals=${intervals.size} (file order) zone=$zone")
        intervals.forEachIndexed { i, iv ->
            val durMin = (iv.endUnix - iv.beginUnix) / 60
            Log.i(
                TAG,
                "file-download sleep_state[$i] " +
                    "${iv.beginUnix}-${iv.endUnix} " +
                    "${formatUnix(iv.beginUnix)}→${formatUnix(iv.endUnix)} (${durMin}m)",
            )
        }
        val longest = intervals.maxByOrNull { it.endUnix - it.beginUnix }
        if (longest != null) {
            val durMin = (longest.endUnix - longest.beginUnix) / 60
            Log.i(
                TAG,
                "file-download sleep_state longest=" +
                    "${formatUnix(longest.beginUnix)}→${formatUnix(longest.endUnix)} (${durMin}m)",
            )
        }
        // Most recent calendar night fragment (by endUnix) — better than longest for "last night".
        val latest = intervals.maxByOrNull { it.endUnix }
        if (latest != null) {
            Log.i(
                TAG,
                "file-download sleep_state latestEnd=" +
                    "${formatUnix(latest.beginUnix)}→${formatUnix(latest.endUnix)}",
            )
        }
    }

    private fun asByte(frame: HuaweiFraming.Frame, tag: Int): Byte? =
        frame.tlvs.firstOrNull { it.tag == tag }?.value?.firstOrNull()

    private fun asInt(frame: HuaweiFraming.Frame, tag: Int): Int? {
        val v = frame.tlvs.firstOrNull { it.tag == tag }?.value ?: return null
        if (v.size < 4) return null
        return ByteBuffer.wrap(v).order(ByteOrder.BIG_ENDIAN).int
    }
}
