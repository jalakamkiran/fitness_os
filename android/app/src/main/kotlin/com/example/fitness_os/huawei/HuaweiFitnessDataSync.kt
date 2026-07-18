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
        private const val TIMEOUT_MS = 20_000L
        /** Bitmap bit for interval HR in step/activity samples (wire-spec). */
        const val BITMAP_HR = 0x40

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
     * @return status + sleepSessions + dailyHrSamples + completedContainers + flags
     */
    fun sync(startUnix: Long, endUnix: Long): Map<String, Any?> {
        val start = startUnix.coerceAtLeast(0)
        val end = endUnix.coerceAtLeast(start)
        Log.i(TAG, "activity-sync start window=[$start,$end]")

        val completed = mutableListOf<String>()
        val sleepSessions = ArrayList<Map<String, Any?>>()
        val hrSamples = ArrayList<Map<String, Any?>>()
        var enableSkipped = false
        var unknownTlvCount = 0

        // Soft enables — distinct from durable empty.
        when (requestEnable(CMD_TRUSLEEP_ENABLE)) {
            EnableResult.Skipped -> enableSkipped = true
            EnableResult.Failed -> enableSkipped = true
            EnableResult.Ok -> Unit
        }
        when (requestEnable(CMD_AUTO_HR_ENABLE)) {
            EnableResult.Skipped -> enableSkipped = true
            EnableResult.Failed -> enableSkipped = true
            EnableResult.Ok -> Unit
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

        for (index in sleepRefs) {
            val dataFrame = exchangeEncrypted(
                buildIndexRequest(CMD_SLEEP_DATA, index),
                SVC,
                CMD_SLEEP_DATA,
                TIMEOUT_MS,
            )
            if (dataFrame == null) {
                Log.w(TAG, "activity-sync sleepData timeout index=$index")
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
            val parsed = parseSleepData(dataFrame)
            unknownTlvCount += parsed.unknownTags
            for (s in parsed.sessions) {
                sleepSessions.add(s.toMap())
            }
        }
        // Empty sleep container still "completed" so Flutter can keep prior.
        completed.add("sleep")

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
            if (parsed.hrBitmapPresent) {
                hrContainerCompleted = true
                for (s in parsed.samples) {
                    hrSamples.add(s.toMap())
                }
            }
        }
        if (hrContainerCompleted) {
            completed.add("daily_hr")
        }
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
            8_000L,
        )
        if (frame == null) {
            Log.i(TAG, "activity-sync enable 0x${cmd.toString(16)} skipped (no response)")
            return EnableResult.Skipped
        }
        return EnableResult.Ok
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

    data class SleepParse(val sessions: List<SleepSession>, val unknownTags: Int)

    /**
     * Synthetic / pre-promotion sleep data shape:
     * 0x81 → repeated 0x83 { 0x01 begin u32, 0x02 end u32, optional 0x03 type u8 }
     */
    fun parseSleepData(frame: HuaweiFraming.Frame): SleepParse {
        val container = frame.tlvs.firstOrNull { it.tag == 0x81 }?.value
            ?: return SleepParse(emptyList(), 0)
        val tlvs = HuaweiFraming.decodeTlvs(container)
        val sessions = ArrayList<SleepSession>()
        var unknown = 0
        for (tlv in tlvs) {
            when (tlv.tag) {
                0x83 -> {
                    val inner = HuaweiFraming.decodeTlvs(tlv.value)
                    var begin = 0L
                    var end = 0L
                    var type: Int? = null
                    for (child in inner) {
                        when (child.tag) {
                            0x01 -> begin = u32(child.value)
                            0x02 -> end = u32(child.value)
                            0x03 -> type = u8(child.value)
                            else -> unknown++
                        }
                    }
                    if (begin > 0L && end > begin) {
                        sessions.add(SleepSession(begin, end, type))
                    }
                }
                0x02, 0x01 -> Unit // count / meta
                else -> unknown++
            }
        }
        return SleepParse(sessions, unknown)
    }

    data class StepHrParse(
        val samples: List<DailyHrSample>,
        val hrBitmapPresent: Boolean,
        val unknownTags: Int,
    )

    /**
     * Synthetic / pre-promotion step data HR shape:
     * 0x81 → 0x02 bitmap u8, repeated 0x84 { 0x01 ts u32, 0x02 bpm u8 } when bitmap & 0x40
     */
    fun parseStepDataHr(frame: HuaweiFraming.Frame): StepHrParse {
        val container = frame.tlvs.firstOrNull { it.tag == 0x81 }?.value
            ?: return StepHrParse(emptyList(), false, 0)
        val tlvs = HuaweiFraming.decodeTlvs(container)
        var bitmap = 0
        var unknown = 0
        val samples = ArrayList<DailyHrSample>()
        for (tlv in tlvs) {
            when (tlv.tag) {
                0x02 -> bitmap = u8(tlv.value)
                0x84 -> {
                    val inner = HuaweiFraming.decodeTlvs(tlv.value)
                    var ts = 0L
                    var bpm = 0
                    for (child in inner) {
                        when (child.tag) {
                            0x01 -> ts = u32(child.value)
                            0x02 -> bpm = u8(child.value)
                            else -> unknown++
                        }
                    }
                    if (ts > 0L && bpm > 0) {
                        samples.add(DailyHrSample(ts, bpm))
                    }
                }
                else -> unknown++
            }
        }
        val hrPresent = (bitmap and BITMAP_HR) != 0
        // If samples arrived without bitmap, still treat as present.
        val completed = hrPresent || samples.isNotEmpty()
        return StepHrParse(
            samples = if (completed) samples else emptyList(),
            hrBitmapPresent = completed,
            unknownTags = unknown,
        )
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
