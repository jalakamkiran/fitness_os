package com.example.fitness_os.huawei

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Clean-room parser for FileDownload SEQUENCE_DATA (`0x16`) + SLEEP_DETAILS
 * dict class `700013`.
 *
 * Observed GT5-A07 layout (`capture:POC-2026-09-12-seq-dict`):
 * - File header (32 B BE): size, dictId, version, type, pad
 * - Records: start/end unix BE, flags, detailLen, pad to 32 B; then Huawei
 *   nested field TLVs (`03 04 <fieldId>` … `05 <len> <val>`); then
 *   `detailLen` bytes of `(durationSec u32 LE, stage u32 LE)` pairs
 *
 * Stage codes match Huawei Health Kit sleep_state: 1 Light, 2 REM, 3 Deep,
 * 4 Awake. First Awake segment often equals sleepLatency (bed → fall asleep).
 *
 * Privacy: callers must not log raw bodies; this type exposes scalars + stage
 * enums only.
 */
object HuaweiSleepDetailsSequenceParser {
    const val DICT_CLASS = HuaweiFileDownload.DICT_SLEEP_DETAILS_CLASS

    /** Health Kit–aligned stage codes observed on GT5 SEQUENCE_DATA. */
    const val STAGE_LIGHT = 1
    const val STAGE_REM = 2
    const val STAGE_DEEP = 3
    const val STAGE_AWAKE = 4

    private const val FILE_HEADER_LEN = 32
    private const val RECORD_HEADER_LEN = 32
    private const val FID_SLEEP_SCORE = 700_013_245
    private const val FID_BED_TIME = 700_013_298
    private const val FID_WAKEUP_TIME = 700_013_156
    private const val FID_FALL_ASLEEP = 700_013_686
    private const val FID_RISING_TIME = 700_013_973
    private const val FID_SLEEP_EFFICIENCY = 700_013_232
    private const val FID_SLEEP_LATENCY = 700_013_713
    private const val FID_DEEP_PART = 700_013_679
    private const val FID_AVG_HRV = 700_013_878
    private const val FID_AVG_HR = 700_013_580
    private const val FID_AVG_BREATH = 700_013_886
    private const val FID_AVG_SPO2 = 700_013_468
    private const val FID_MIN_HR = 700_013_436
    private const val FID_MAX_HR = 700_013_502

    data class StageSegment(
        val durationSec: Int,
        val stage: Int,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "durationSec" to durationSec,
            "stage" to stage,
            "label" to stageLabel(stage),
        )
    }

    data class SleepSession(
        val beginUnix: Int,
        val endUnix: Int,
        val sleepScore: Int? = null,
        val bedTimeUnix: Int? = null,
        val fallAsleepUnix: Int? = null,
        val wakeupUnix: Int? = null,
        val risingUnix: Int? = null,
        val sleepEfficiency: Int? = null,
        val sleepLatencySec: Int? = null,
        val deepPart: Int? = null,
        val avgHrv: Int? = null,
        val avgHeartRate: Int? = null,
        val avgBreathRate: Int? = null,
        val avgOxygenSaturation: Int? = null,
        val minHeartRate: Int? = null,
        val maxHeartRate: Int? = null,
        val stages: List<StageSegment> = emptyList(),
    ) {
        fun toMap(): Map<String, Any?> = buildMap {
            put("beginUnix", beginUnix)
            put("endUnix", endUnix)
            put("durationMin", ((endUnix - beginUnix).coerceAtLeast(0)) / 60)
            sleepScore?.let { put("sleepScore", it) }
            bedTimeUnix?.let { put("bedTimeUnix", it) }
            fallAsleepUnix?.let { put("fallAsleepUnix", it) }
            wakeupUnix?.let { put("wakeupUnix", it) }
            risingUnix?.let { put("risingUnix", it) }
            sleepEfficiency?.let { put("sleepEfficiency", it) }
            sleepLatencySec?.let { put("sleepLatencySec", it) }
            deepPart?.let { put("deepPart", it) }
            avgHrv?.let { put("avgHrv", it) }
            avgHeartRate?.let { put("avgHeartRate", it) }
            avgBreathRate?.let { put("avgBreathRate", it) }
            avgOxygenSaturation?.let { put("avgOxygenSaturation", it) }
            minHeartRate?.let { put("minHeartRate", it) }
            maxHeartRate?.let { put("maxHeartRate", it) }
            put("stages", stages.map { it.toMap() })
            put("stageMinutes", stageMinutes(stages))
            // Product wireType stages (message-path convention) for Flutter hypnogram.
            put("productStages", toProductStages(beginUnix, stages))
        }
    }

    /**
     * Map SEQUENCE stage codes → product/message `wireType`
     * (1=Light, 2=Deep, 3=REM, 4=Awake) used by [sleepStageKindFromWireType].
     */
    fun toProductWireType(sequenceStage: Int): Int = when (sequenceStage) {
        STAGE_LIGHT -> 1
        STAGE_DEEP -> 2
        STAGE_REM -> 3
        STAGE_AWAKE -> 4
        else -> sequenceStage
    }

    /** Timeline for Flutter [SleepStageSummary]: timestampUnix + durationMin + wireType. */
    fun toProductStages(
        beginUnix: Int,
        stages: List<StageSegment>,
    ): List<Map<String, Any?>> {
        var t = beginUnix
        val out = ArrayList<Map<String, Any?>>(stages.size)
        for (seg in stages) {
            val durMin = (seg.durationSec / 60).coerceAtLeast(1)
            out.add(
                mapOf(
                    "timestampUnix" to t,
                    "durationMin" to durMin,
                    "wireType" to toProductWireType(seg.stage),
                ),
            )
            t += seg.durationSec
        }
        return out
    }

    data class ParseResult(
        val dictId: Int,
        val sessions: List<SleepSession>,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "dictId" to dictId,
            "sessionCount" to sessions.size,
            "sessions" to sessions.map { it.toMap() },
        )
    }

    fun stageLabel(stage: Int): String = when (stage) {
        STAGE_LIGHT -> "light"
        STAGE_REM -> "rem"
        STAGE_DEEP -> "deep"
        STAGE_AWAKE -> "awake"
        else -> "unknown_$stage"
    }

    fun stageMinutes(stages: List<StageSegment>): Map<String, Int> {
        val mins = linkedMapOf(
            "light" to 0,
            "rem" to 0,
            "deep" to 0,
            "awake" to 0,
        )
        for (seg in stages) {
            val key = stageLabel(seg.stage)
            if (key in mins) {
                mins[key] = mins.getValue(key) + seg.durationSec / 60
            }
        }
        return mins
    }

    fun parse(bytes: ByteArray): ParseResult? {
        if (bytes.size < FILE_HEADER_LEN) return null
        val be = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
        val size = be.int
        val dictId = be.int
        if (dictId != DICT_CLASS) return null
        // version + type present but unused for this cut
        be.short
        be.short
        if (size != bytes.size && size > 0 && size < bytes.size) {
            // tolerate size mismatch; still walk records in buffer
        }
        var offset = FILE_HEADER_LEN
        val sessions = ArrayList<SleepSession>()
        while (offset + RECORD_HEADER_LEN <= bytes.size) {
            val rec = parseRecord(bytes, offset) ?: break
            sessions.add(rec.session)
            offset = rec.nextOffset
            if (offset <= rec.recordStart) break
        }
        if (sessions.isEmpty()) return null
        return ParseResult(dictId = dictId, sessions = sessions)
    }

    private data class RecordParse(
        val recordStart: Int,
        val nextOffset: Int,
        val session: SleepSession,
    )

    private fun parseRecord(bytes: ByteArray, offset: Int): RecordParse? {
        if (offset + RECORD_HEADER_LEN > bytes.size) return null
        val be = ByteBuffer.wrap(bytes, offset, RECORD_HEADER_LEN)
            .order(ByteOrder.BIG_ENDIAN)
        val begin = be.int
        val end = be.int
        if (end <= begin || begin < 1_600_000_000) return null
        be.short // flags0
        be.short // flags1
        val detailLen = be.int
        if (detailLen < 0 || detailLen > 20 * 1024) return null

        val summaryStart = offset + RECORD_HEADER_LEN
        val scoreMarker = byteArrayOf(
            0x03, 0x04,
            0x29, 0xb9.toByte(), 0x5a, 0xbd.toByte(),
            0x04, 0x01, 0x01, 0x05, 0x01,
        )
        val scoreAt = indexOf(bytes, scoreMarker, summaryStart, summaryStart + 900)
        if (scoreAt < 0) return null
        val scoreValOff = scoreAt + scoreMarker.size
        if (scoreValOff >= bytes.size) return null
        val sleepScore = bytes[scoreValOff].toInt() and 0xFF
        val detailsOff = scoreValOff + 1
        if (detailsOff + detailLen > bytes.size) return null

        val fields = scanFields(bytes, summaryStart, detailsOff)
        val stages = parseStages(bytes, detailsOff, detailLen)

        val session = SleepSession(
            beginUnix = begin,
            endUnix = end,
            sleepScore = sleepScore,
            bedTimeUnix = fields[FID_BED_TIME],
            fallAsleepUnix = fields[FID_FALL_ASLEEP],
            wakeupUnix = fields[FID_WAKEUP_TIME],
            risingUnix = fields[FID_RISING_TIME],
            sleepEfficiency = fields[FID_SLEEP_EFFICIENCY],
            sleepLatencySec = fields[FID_SLEEP_LATENCY]?.let { it * 60 },
            deepPart = fields[FID_DEEP_PART],
            avgHrv = fields[FID_AVG_HRV],
            avgHeartRate = fields[FID_AVG_HR],
            avgBreathRate = fields[FID_AVG_BREATH],
            avgOxygenSaturation = fields[FID_AVG_SPO2],
            minHeartRate = fields[FID_MIN_HR],
            maxHeartRate = fields[FID_MAX_HR],
            stages = stages,
        )
        return RecordParse(
            recordStart = offset,
            nextOffset = detailsOff + detailLen,
            session = session,
        )
    }

    private fun parseStages(bytes: ByteArray, off: Int, detailLen: Int): List<StageSegment> {
        if (detailLen < 8 || detailLen % 8 != 0) return emptyList()
        val le = ByteBuffer.wrap(bytes, off, detailLen).order(ByteOrder.LITTLE_ENDIAN)
        val out = ArrayList<StageSegment>(detailLen / 8)
        while (le.remaining() >= 8) {
            val durationSec = le.int
            val stage = le.int
            if (durationSec <= 0 || durationSec > 20 * 3600) break
            if (stage < 0 || stage > 10) break
            out.add(StageSegment(durationSec = durationSec, stage = stage))
        }
        return out
    }

    /** Scan `03 04 <fieldId BE>` + `04 01 <type>` + `05 <len> <val>` triples. */
    private fun scanFields(bytes: ByteArray, from: Int, to: Int): Map<Int, Int> {
        val out = HashMap<Int, Int>()
        var i = from
        while (i + 10 <= to) {
            if (bytes[i] != 0x03.toByte() || bytes[i + 1] != 0x04.toByte()) {
                i++
                continue
            }
            val fid = ByteBuffer.wrap(bytes, i + 2, 4).order(ByteOrder.BIG_ENDIAN).int
            var j = i + 6
            if (j + 3 >= to || bytes[j] != 0x04.toByte() || bytes[j + 1] != 0x01.toByte()) {
                i++
                continue
            }
            j += 3 // skip type byte
            if (j + 1 >= to || bytes[j] != 0x05.toByte()) {
                i++
                continue
            }
            val len = bytes[j + 1].toInt() and 0xFF
            j += 2
            if (j + len > to) break
            val value = when (len) {
                1 -> bytes[j].toInt() and 0xFF
                2 -> ByteBuffer.wrap(bytes, j, 2).order(ByteOrder.BIG_ENDIAN).short.toInt() and 0xFFFF
                4 -> ByteBuffer.wrap(bytes, j, 4).order(ByteOrder.BIG_ENDIAN).int
                else -> null
            }
            if (value != null) out[fid] = value
            i = j + len
        }
        return out
    }

    private fun indexOf(hay: ByteArray, needle: ByteArray, from: Int, toExclusive: Int): Int {
        val last = (toExclusive - needle.size).coerceAtMost(hay.size - needle.size)
        if (last < from) return -1
        var i = from
        while (i <= last) {
            var match = true
            for (j in needle.indices) {
                if (hay[i + j] != needle[j]) {
                    match = false
                    break
                }
            }
            if (match) return i
            i++
        }
        return -1
    }
}
