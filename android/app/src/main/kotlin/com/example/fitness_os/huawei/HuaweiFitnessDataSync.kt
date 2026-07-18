package com.example.fitness_os.huawei

import android.util.Log
import java.nio.ByteBuffer

/**
 * Clean-room FitnessData (`0x07`) activity Sync — sleep messages + daily HR.
 *
 * Pre-promotion parsers: synthetic fixtures + owned wire-spec shapes only.
 * Do not treat as normative until `huawei-br-gt5-fitness-data.md` cites capture/ABSENT.
 *
 * FileSleep / TruSleep FileDownload deferred (U4).
 */
class HuaweiFitnessDataSync(
    private val exchangeEncrypted: (
        request: HuaweiFraming.Frame,
        expectService: Int,
        expectCmd: Int,
        timeoutMs: Long,
    ) -> HuaweiFraming.Frame?,
    private val fetchBattery: (() -> Unit)? = null,
    private val isConnected: () -> Boolean = { true },
) {
    companion object {
        private const val TAG = "FOS_HUAWEI"
        const val SVC = 0x07
        const val CMD_FITNESS_TOTALS = 0x03
        const val CMD_STEP_COUNT = 0x0A
        const val CMD_STEP_DATA = 0x0B
        const val CMD_SLEEP_COUNT = 0x0C
        const val CMD_SLEEP_DATA = 0x0D
        const val CMD_TRUSLEEP_ENABLE = 0x16
        const val CMD_AUTO_HR_ENABLE = 0x17
        const val CMD_AUTO_SPO2_ENABLE = 0x24
        private const val TIMEOUT_MS = 20_000L
        private const val ENABLE_TIMEOUT_MS = 8_000L
        /** Bitmap bit for interval HR in step/activity samples (wire-spec). */
        const val BITMAP_HR = 0x40
        /** Drop sub-15m fragments (paging noise / empty tails). */
        private const val MIN_SESSION_SEC = 15 * 60L

        private data class FeatureEnable(val id: String, val cmd: Int)

        private val AUTO_TRACK_ENABLES = listOf(
            FeatureEnable("trusleep", CMD_TRUSLEEP_ENABLE),
            FeatureEnable("auto_hr", CMD_AUTO_HR_ENABLE),
            FeatureEnable("auto_spo2", CMD_AUTO_SPO2_ENABLE),
        )

        fun u8(value: ByteArray, offset: Int = 0): Int {
            if (value.size <= offset) return 0
            return value[offset].toInt() and 0xFF
        }

        fun u16(value: ByteArray, offset: Int = 0): Int {
            if (value.size < offset + 2) return 0
            return ((value[offset].toInt() and 0xFF) shl 8) or
                (value[offset + 1].toInt() and 0xFF)
        }

        fun u32(value: ByteArray, offset: Int = 0): Long {
            if (value.size < offset + 4) return 0L
            return ByteBuffer.wrap(value, offset, 4).int.toLong() and 0xFFFF_FFFFL
        }
    }

    data class SleepSession(
        val beginUnix: Long,
        val endUnix: Long,
        val wireType: Int? = null,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "beginUnix" to beginUnix,
            "endUnix" to endUnix,
            "wireType" to wireType,
        )
    }

    data class DailyHrSample(
        val timestampUnix: Long,
        val bpm: Int,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "timestampUnix" to timestampUnix,
            "bpm" to bpm,
        )
    }

    /**
     * Explicit auto-tracking enable batch (TruSleep / auto-HR / auto-SpO2).
     * Returns overall + features only — never sleep/HR series.
     *
     * @param supportedCmds when non-null, cmds absent from the set are `skipped` without send
     */
    fun enableAutoTracking(supportedCmds: Set<Int>? = null): Map<String, Any?> {
        val features = ArrayList<Map<String, Any?>>()
        var stop = false
        for (feature in AUTO_TRACK_ENABLES) {
            if (stop) {
                features.add(featureResult(feature.id, feature.cmd, "failed", null))
                continue
            }
            if (supportedCmds != null && feature.cmd !in supportedCmds) {
                Log.i(TAG, "enable-auto 0x${feature.cmd.toString(16)} skipped (unsupported)")
                features.add(featureResult(feature.id, feature.cmd, "skipped", null))
                continue
            }
            if (!isConnected()) {
                Log.i(TAG, "enable-auto disconnect before 0x${feature.cmd.toString(16)}")
                features.add(featureResult(feature.id, feature.cmd, "failed", null))
                stop = true
                continue
            }
            val frame = exchangeEncrypted(
                HuaweiFraming.Frame(
                    SVC,
                    feature.cmd,
                    listOf(HuaweiFraming.Tlv(0x01, byteArrayOf(0x01))),
                ),
                SVC,
                feature.cmd,
                ENABLE_TIMEOUT_MS,
            )
            val (outcome, resultCode) = mapHonestEnableOutcome(frame)
            Log.i(
                TAG,
                "enable-auto 0x${feature.cmd.toString(16)} outcome=$outcome" +
                    (resultCode?.let { " resultCode=$it" } ?: ""),
            )
            features.add(featureResult(feature.id, feature.cmd, outcome, resultCode))
            if (frame == null && !isConnected()) {
                // In-flight timed out because transport died — remainder failed.
                stop = true
            }
        }
        val armed = features.count { it["outcome"] == "armed" }
        val overall = when {
            armed == features.size -> "all_armed"
            armed == 0 -> "none_armed"
            else -> "partial"
        }
        return mapOf(
            "status" to "ok",
            "overall" to overall,
            "features" to features,
        )
    }

    /**
     * @return status + sleepSessions + dailyHrSamples + completedContainers + flags
     */
    fun sync(
        startUnix: Long,
        endUnix: Long,
        skipTruSleepSoft: Boolean = false,
        skipAutoHrSoft: Boolean = false,
    ): Map<String, Any?> {
        val start = startUnix.coerceAtLeast(0)
        val end = endUnix.coerceAtLeast(start)
        Log.i(TAG, "activity-sync start window=[$start,$end]")

        val completed = mutableListOf<String>()
        val sleepSessions = ArrayList<Map<String, Any?>>()
        val hrSamples = ArrayList<Map<String, Any?>>()
        var enableSkipped = false
        var unknownTlvCount = 0

        // Soft enables — distinct from durable empty. Skip when explicit Enable already armed.
        if (!skipTruSleepSoft) {
            when (requestEnable(CMD_TRUSLEEP_ENABLE)) {
                EnableResult.Skipped -> enableSkipped = true
                EnableResult.Failed -> enableSkipped = true
                EnableResult.Ok -> Unit
            }
        }
        if (!skipAutoHrSoft) {
            when (requestEnable(CMD_AUTO_HR_ENABLE)) {
                EnableResult.Skipped -> enableSkipped = true
                EnableResult.Failed -> enableSkipped = true
                EnableResult.Ok -> Unit
            }
        }

        // sleepCount → sleepData
        val sleepCountFrame = exchangeEncrypted(
            buildWindowRequest(CMD_SLEEP_COUNT, start, end),
            SVC,
            CMD_SLEEP_COUNT,
            TIMEOUT_MS,
        )
        if (sleepCountFrame == null) {
            Log.w(TAG, "activity-sync sleepCount timeout")
            return resultMap(
                status = "stuck",
                message = "Sleep count timed out — disconnect and retry",
                sleep = sleepSessions,
                hr = hrSamples,
                completed = completed,
                enableSkipped = enableSkipped,
            )
        }
        val sleepRefs = parseCountIndices(sleepCountFrame)
        Log.i(TAG, "activity-sync sleepCount=${sleepRefs.size}")

        // 0x0C count pages stage batches across 0x0D indices — collect ALL stages,
        // then aggregate once (per-index sessions incorrectly split one nap).
        val allSleepStages = ArrayList<SleepStage>()
        for (index in sleepRefs) {
            val dataFrame = exchangeEncrypted(
                buildIndexRequest(CMD_SLEEP_DATA, index),
                SVC,
                CMD_SLEEP_DATA,
                TIMEOUT_MS,
            )
            if (dataFrame == null) {
                Log.w(TAG, "activity-sync sleepData timeout index=$index")
                val partial = aggregateSleepSessions(allSleepStages)
                    .filter { it.endUnix - it.beginUnix >= MIN_SESSION_SEC }
                for (s in partial) sleepSessions.add(s.toMap())
                if (sleepSessions.isNotEmpty()) completed.add("sleep")
                return resultMap(
                    status = "partial_batch",
                    message = "Sleep data timed out after partial progress",
                    sleep = sleepSessions,
                    hr = hrSamples,
                    completed = completed,
                    enableSkipped = enableSkipped,
                )
            }
            val parsed = parseSleepStages(dataFrame)
            unknownTlvCount += parsed.unknownTags
            allSleepStages.addAll(parsed.stages)
        }
        val aggregated = aggregateSleepSessions(allSleepStages)
            .filter { it.endUnix - it.beginUnix >= MIN_SESSION_SEC }
        for (s in aggregated) sleepSessions.add(s.toMap())
        // Empty sleep container still "completed" so Flutter can keep prior.
        completed.add("sleep")
        Log.i(
            TAG,
            "activity-sync sleepSessions=${sleepSessions.size} " +
                "stages=${allSleepStages.size} pages=${sleepRefs.size}",
        )
        val tz = java.util.TimeZone.getDefault()
        val fmt = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm z", java.util.Locale.US)
        fmt.timeZone = tz
        for (s in aggregated) {
            val beginLabel = fmt.format(java.util.Date(s.beginUnix * 1000L))
            val endLabel = fmt.format(java.util.Date(s.endUnix * 1000L))
            Log.i(
                TAG,
                "activity-sync sleep begin=${s.beginUnix} end=${s.endUnix} " +
                    "durMin=${(s.endUnix - s.beginUnix) / 60} " +
                    "local=$beginLabel → $endLabel",
            )
        }

        // stepCount → stepData (HR extract only; drop steps/SpO2)
        val stepCountFrame = exchangeEncrypted(
            buildWindowRequest(CMD_STEP_COUNT, start, end),
            SVC,
            CMD_STEP_COUNT,
            TIMEOUT_MS,
        )
        if (stepCountFrame == null) {
            Log.w(TAG, "activity-sync stepCount timeout")
            return resultMap(
                status = "partial_batch",
                message = "Step count timed out after sleep",
                sleep = sleepSessions,
                hr = hrSamples,
                completed = completed,
                enableSkipped = enableSkipped,
            )
        }
        val stepRefs = parseCountIndices(stepCountFrame)
        Log.i(TAG, "activity-sync stepCount=${stepRefs.size}")

        var hrContainerCompleted = false
        for (index in stepRefs) {
            val dataFrame = exchangeEncrypted(
                buildIndexRequest(CMD_STEP_DATA, index),
                SVC,
                CMD_STEP_DATA,
                TIMEOUT_MS,
            )
            if (dataFrame == null) {
                Log.w(TAG, "activity-sync stepData timeout index=$index")
                if (hrContainerCompleted) completed.add("daily_hr")
                return resultMap(
                    status = "partial_batch",
                    message = "Step data timed out after partial progress",
                    sleep = sleepSessions,
                    hr = hrSamples,
                    completed = completed,
                    enableSkipped = enableSkipped,
                )
            }
            val parsed = parseStepDataHr(dataFrame)
            unknownTlvCount += parsed.unknownTags
            for (s in parsed.samples) {
                hrSamples.add(s.toMap())
            }
            // Only mark completed when we extracted usable BPM (bitmap alone can be noise).
            if (parsed.samples.isNotEmpty()) {
                hrContainerCompleted = true
            }
        }
        if (hrContainerCompleted) {
            completed.add("daily_hr")
        }
        Log.i(
            TAG,
            "activity-sync hrSamples=${hrSamples.size} hrCompleted=$hrContainerCompleted",
        )
        // Absent HR bitmap ⇒ HR not completed — not partial_batch.

        // Opaque idle handoff — no Flutter persistence.
        exchangeEncrypted(
            buildWindowRequest(CMD_FITNESS_TOTALS, start, end),
            SVC,
            CMD_FITNESS_TOTALS,
            TIMEOUT_MS,
        )
        // FileSleep hook deferred (U4).
        fetchBattery?.invoke()

        if (unknownTlvCount > 0) {
            Log.i(TAG, "activity-sync unknownTlvCount=$unknownTlvCount")
        }

        val hasMergeable = sleepSessions.isNotEmpty() || hrSamples.isNotEmpty()
        val status = when {
            hasMergeable -> "ok"
            else -> "empty"
        }
        Log.i(
            TAG,
            "activity-sync done status=$status sleep=${sleepSessions.size} " +
                "hrSamples=${hrSamples.size} completed=$completed enableSkipped=$enableSkipped",
        )
        return resultMap(
            status = status,
            message = if (enableSkipped) "enable_skipped" else null,
            sleep = sleepSessions,
            hr = hrSamples,
            completed = completed,
            enableSkipped = enableSkipped,
        )
    }

    private enum class EnableResult { Ok, Skipped, Failed }

    private fun requestEnable(cmd: Int): EnableResult {
        val frame = exchangeEncrypted(
            HuaweiFraming.Frame(
                SVC,
                cmd,
                listOf(HuaweiFraming.Tlv(0x01, byteArrayOf(0x01))),
            ),
            SVC,
            cmd,
            ENABLE_TIMEOUT_MS,
        )
        if (frame == null) {
            Log.i(TAG, "activity-sync enable 0x${cmd.toString(16)} skipped (no response)")
            return EnableResult.Skipped
        }
        return EnableResult.Ok
    }

    /**
     * Strict RESULT_OK (`t=7f` / 100000) → armed. Any other non-null frame → failed.
     * Null → timed_out. Never treat "any response" as armed.
     */
    private fun mapHonestEnableOutcome(frame: HuaweiFraming.Frame?): Pair<String, Int?> {
        if (frame == null) return "timed_out" to null
        val resultTlv = frame.tlvs.firstOrNull { it.tag == 0x7F }
        if (resultTlv != null && resultTlv.value.size >= 4) {
            val code = ByteBuffer.wrap(resultTlv.value).int
            return if (code == HuaweiPacketCrypto.RESULT_OK) {
                "armed" to code
            } else {
                "failed" to code
            }
        }
        return "failed" to null
    }

    private fun featureResult(
        id: String,
        cmd: Int,
        outcome: String,
        resultCode: Int?,
    ): Map<String, Any?> = buildMap {
        put("id", id)
        put("cmd", cmd)
        put("outcome", outcome)
        if (resultCode != null) put("resultCode", resultCode)
    }

    private fun buildWindowRequest(cmd: Int, startUnix: Long, endUnix: Long): HuaweiFraming.Frame {
        val nested = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x03, HuaweiPacketCrypto.intBe(startUnix.toInt())),
                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(endUnix.toInt())),
            ),
        )
        return HuaweiFraming.Frame(SVC, cmd, listOf(HuaweiFraming.Tlv(0x81, nested)))
    }

    private fun buildIndexRequest(cmd: Int, index: Int): HuaweiFraming.Frame {
        val nested = HuaweiFraming.encodeTlvs(
            listOf(HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(index))),
        )
        return HuaweiFraming.Frame(SVC, cmd, listOf(HuaweiFraming.Tlv(0x81, nested)))
    }

    /** Count responses: list of u16 indices under 0x81 → 0x85 entries tag 0x02. */
    fun parseCountIndices(frame: HuaweiFraming.Frame): List<Int> {
        val container = frame.tlvs.firstOrNull { it.tag == 0x81 }?.value
            ?: return emptyList()
        val tlvs = HuaweiFraming.decodeTlvs(container)
        val out = ArrayList<Int>()
        for (tlv in tlvs) {
            if (tlv.tag != 0x85) continue
            val inner = HuaweiFraming.decodeTlvs(tlv.value)
            val index = inner.firstOrNull { it.tag == 0x02 }?.value?.let { u16(it) } ?: 0
            if (index > 0) out.add(index)
        }
        // Some firmwares return a bare count in 0x02 — synthesize 1..n indices.
        if (out.isEmpty()) {
            val count = tlvs.firstOrNull { it.tag == 0x02 }?.value?.let { u16(it) } ?: 0
            for (i in 1..count) out.add(i)
        }
        return out
    }

    data class SleepStage(
        val timestampUnix: Long,
        val durationMin: Int,
        val wireType: Int?,
    )

    data class SleepStageParse(val stages: List<SleepStage>, val unknownTags: Int)

    data class SleepParse(val sessions: List<SleepSession>, val unknownTags: Int)

    /**
     * Observed GT5-A07 sleep data (`capture:POC-2026-07-18-activity-sync-sleep`):
     * 0x81 → 0x02 index u16, repeated 0x83 stages:
     *   0x04 type u8, 0x06 meta u8, 0x05 = timestamp_be_u32 + duration_be_u16 (minutes)
     * Indices from sleepCount are **stage pages** for the window — merge across pages.
     */
    fun parseSleepStages(frame: HuaweiFraming.Frame): SleepStageParse {
        val container = frame.tlvs.firstOrNull { it.tag == 0x81 }?.value
            ?: return SleepStageParse(emptyList(), 0)
        val tlvs = HuaweiFraming.decodeTlvs(container)
        val stages = ArrayList<SleepStage>()
        var unknown = 0
        for (tlv in tlvs) {
            when (tlv.tag) {
                0x83 -> {
                    val stage = parseSleepStage(tlv.value)
                    if (stage != null) {
                        stages.add(stage)
                    } else {
                        unknown++
                    }
                }
                0x02, 0x01 -> Unit // page index / meta
                else -> unknown++
            }
        }
        return SleepStageParse(stages, unknown)
    }

    fun parseSleepData(frame: HuaweiFraming.Frame): SleepParse {
        val parsed = parseSleepStages(frame)
        return SleepParse(aggregateSleepSessions(parsed.stages), parsed.unknownTags)
    }

    fun parseSleepStage(value: ByteArray): SleepStage? {
        val inner = HuaweiFraming.decodeTlvs(value)
        var type: Int? = null
        var timestamp = 0L
        var durationMin = 0
        for (child in inner) {
            when (child.tag) {
                0x04 -> if (child.value.isNotEmpty()) type = u8(child.value)
                0x05 -> if (child.value.size >= 4) {
                    timestamp = u32(child.value)
                    if (child.value.size >= 6) {
                        durationMin = u16(child.value, 4).coerceAtLeast(0)
                    }
                }
                0x06 -> Unit // observed meta; ignore
                else -> Unit
            }
        }
        if (timestamp <= 0L) return null
        return SleepStage(timestamp, durationMin, type)
    }

    /** Gap > 45 minutes starts a new session within one sleepData container. */
    fun aggregateSleepSessions(
        stages: List<SleepStage>,
        gapSplitSec: Long = 45 * 60L,
    ): List<SleepSession> {
        if (stages.isEmpty()) return emptyList()
        val ordered = stages.sortedBy { it.timestampUnix }
        val out = ArrayList<SleepSession>()
        var begin = ordered[0].timestampUnix
        var end = stageEndUnix(ordered[0])
        var type = ordered[0].wireType
        for (i in 1 until ordered.size) {
            val s = ordered[i]
            val gap = s.timestampUnix - end
            if (gap > gapSplitSec) {
                if (end > begin) out.add(SleepSession(begin, end, type))
                begin = s.timestampUnix
                end = stageEndUnix(s)
                type = s.wireType
            } else {
                end = maxOf(end, stageEndUnix(s))
            }
        }
        if (end > begin) out.add(SleepSession(begin, end, type))
        return out
    }

    private fun stageEndUnix(stage: SleepStage): Long {
        val durSec = stage.durationMin.coerceAtLeast(1) * 60L
        return stage.timestampUnix + durSec
    }

    data class StepHrParse(
        val samples: List<DailyHrSample>,
        val hrBitmapPresent: Boolean,
        val unknownTags: Int,
    )

    /**
     * Observed GT5-A07 step data (`capture:POC-2026-07-18-activity-sync-sleep`):
     * 0x81 → 0x02 index, 0x03 dayStart u32, repeated 0x84 minutes:
     *   0x05 minuteOffset u8, 0x06 payload (first byte = field bitmap)
     * HR when bitmap & 0x40; SpO2/steps dropped after extract (R13).
     */
    fun parseStepDataHr(frame: HuaweiFraming.Frame): StepHrParse {
        val container = frame.tlvs.firstOrNull { it.tag == 0x81 }?.value
            ?: return StepHrParse(emptyList(), false, 0)
        // Result-only frames (tag 0x7f) are not HR containers.
        if (frame.tlvs.any { it.tag == 0x7F } &&
            frame.tlvs.none { it.tag == 0x81 && it.value.size > 4 }
        ) {
            return StepHrParse(emptyList(), false, 0)
        }
        val tlvs = HuaweiFraming.decodeTlvs(container)
        var dayStart = 0L
        var unknown = 0
        var sawHrBitmap = false
        val samples = ArrayList<DailyHrSample>()
        for (tlv in tlvs) {
            when (tlv.tag) {
                0x02 -> Unit // day index
                0x03 -> if (tlv.value.size >= 4) dayStart = u32(tlv.value)
                0x08 -> Unit // end marker
                0x84 -> {
                    val inner = HuaweiFraming.decodeTlvs(tlv.value)
                    var minute = 0
                    var payload: ByteArray? = null
                    for (child in inner) {
                        when (child.tag) {
                            0x05 -> if (child.value.isNotEmpty()) minute = u8(child.value)
                            0x06 -> payload = child.value
                            else -> unknown++
                        }
                    }
                    val p = payload
                    if (p != null && p.isNotEmpty()) {
                        val bitmap = u8(p)
                        if ((bitmap and BITMAP_HR) != 0) {
                            sawHrBitmap = true
                            val bpm = extractHrBpm(p)
                            if (bpm != null && dayStart > 0L) {
                                samples.add(
                                    DailyHrSample(
                                        timestampUnix = dayStart + minute * 60L,
                                        bpm = bpm,
                                    ),
                                )
                            }
                        }
                    }
                }
                else -> unknown++
            }
        }
        return StepHrParse(
            samples = samples,
            hrBitmapPresent = sawHrBitmap,
            unknownTags = unknown,
        )
    }

    /**
     * Bitmap-led payload: skip known lower bits' widths, then read HR u8 when 0x40 set.
     * Widths are directional from observed envelopes (steps/cal/dist 2B each before HR).
     */
    fun extractHrBpm(payload: ByteArray): Int? {
        if (payload.isEmpty()) return null
        val bitmap = u8(payload)
        if ((bitmap and BITMAP_HR) == 0) return null
        var offset = 1
        // bits below 0x40 commonly: 0x01 steps, 0x02 cal, 0x04 dist, 0x08/0x10 other — 2B each when set
        var bit = 0x01
        while (bit < BITMAP_HR) {
            if ((bitmap and bit) != 0) {
                offset += 2
            }
            bit = bit shl 1
        }
        if (offset >= payload.size) return null
        val bpm = u8(payload, offset)
        return if (bpm in 30..220) bpm else null
    }

    private fun resultMap(
        status: String,
        message: String?,
        sleep: List<Map<String, Any?>>,
        hr: List<Map<String, Any?>>,
        completed: List<String>,
        enableSkipped: Boolean,
    ): Map<String, Any?> = buildMap {
        put("status", status)
        if (message != null) put("message", message)
        put("sleepSessions", sleep)
        put("dailyHrSamples", hr)
        put("completedContainers", completed)
        put("enableSkipped", enableSkipped)
    }
}
