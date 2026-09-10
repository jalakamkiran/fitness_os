package com.example.fitness_os.huawei

import android.util.Log
import java.nio.ByteBuffer

/**
 * Clean-room Gate B workout sync — Count → Totals → hint-gated enrichment.
 *
 * Behavioral shapes from public LPv2 / GB oracle (service 0x17). No AGPL paste.
 * Fetch order: Swim segments (0x0e) → WorkoutData (0x0a) → Pace (0x0c) when time allows.
 */
class HuaweiWorkoutSync(
    private val exchangeEncrypted: (
        request: HuaweiFraming.Frame,
        expectService: Int,
        expectCmd: Int,
        timeoutMs: Long,
    ) -> HuaweiFraming.Frame?,
    /**
     * Optional native sample-file sink (peer to TruSleep persist). Relative path under
     * GateAPrefs workout HR samples dir. Invoked only when opaque point bodies exist.
     */
    private val persistWorkoutSamples: ((id: String, bytes: ByteArray) -> String?)? = null,
    /**
     * Optional native leftover-file sink (peer to samples). Relative path under
     * GateAPrefs workout leftovers dir. Used when leftover bodies would blow the
     * MethodChannel binder budget — small leftovers still cross the channel once.
     */
    private val persistWorkoutLeftovers: ((id: String, bytes: ByteArray) -> String?)? = null,
) {
    companion object {
        private const val TAG = "FOS_HUAWEI"
        const val SVC = 0x17
        const val CMD_COUNT = 0x07
        const val CMD_TOTALS = 0x08
        const val CMD_DATA = 0x0a
        const val CMD_PACE = 0x0c
        const val CMD_SWIM = 0x0e
        private const val TIMEOUT_MS = 20_000L
        /** Same empty-history floor GB uses when no cursor exists. */
        const val FALLBACK_START_UNIX = 1_654_819_200L
        /** Relative side-file dir — must match [GateAPrefs.workoutHrSamplesDir]. */
        const val WORKOUT_HR_SAMPLES_DIR = "workouts/hr_samples"
        /** Relative side-file dir — must match [GateAPrefs.workoutLeftoversDir]. */
        const val WORKOUT_LEFTOVERS_DIR = "workouts/leftovers"
        /**
         * Soft cumulative binder budget for leftover bodies in one Sync result.
         * Below Android TransactionTooLarge (~1MB) with headroom for other map fields.
         */
        const val LEFTOVER_CHANNEL_BUDGET_BYTES = 384 * 1024
        /** Single leftover above this always spills when a sink is available. */
        const val LEFTOVER_INLINE_MAX_BYTES = 64 * 1024

        fun u16(value: ByteArray, offset: Int = 0): Int {
            if (value.size < offset + 2) return 0
            return ((value[offset].toInt() and 0xFF) shl 8) or
                (value[offset + 1].toInt() and 0xFF)
        }

        fun u32(value: ByteArray, offset: Int = 0): Long {
            if (value.size < offset + 4) return 0L
            return ByteBuffer.wrap(value, offset, 4).int.toLong() and 0xFFFF_FFFFL
        }

        fun u8(value: ByteArray, offset: Int = 0): Int {
            if (value.size <= offset) return 0
            return value[offset].toInt() and 0xFF
        }
    }

    data class WorkoutNumber(
        val workoutNumber: Int,
        val dataCount: Int,
        val paceCount: Int,
        val segmentsCount: Int,
    )

    data class EnrichmentTagRef(
        val id: Int,
        val len: Int,
    ) {
        fun toMap(): Map<String, Int> = mapOf("id" to id, "len" to len)
    }

    /**
     * Parsed swim lap from nested 0x83 inside 0x17:0x0e — unknown TLVs as id+len only.
     *
     * Field map aligned with GB behavioral oracle (WorkoutSwimSegments.Block):
     * distance 0x04, unitType 0x05 (0=metric), pace 0x06, segment 0x09,
     * style 0x0a, strokes 0x0b, swolf 0x0c, time 0x0d.
     */
    data class SwimSegment(
        val index: Int,
        val distanceM: Long? = null,
        val durationSec: Long? = null,
        val swimType: Int? = null,
        val style: Int? = null,
        val strokes: Int? = null,
        val avgSwolf: Int? = null,
        val paceSecPer100m: Int? = null,
        /** Wire 0x05 unit type (0=metric, 1=imperial). Not exported. */
        val unitType: Int? = null,
        val tags: List<EnrichmentTagRef> = emptyList(),
    ) {
        fun toMap(): Map<String, Any?> {
            val out = linkedMapOf<String, Any?>("index" to index)
            if (distanceM != null) out["distanceM"] = distanceM
            if (durationSec != null) out["durationSec"] = durationSec
            if (swimType != null) out["swimType"] = swimType
            if (style != null) out["style"] = style
            if (strokes != null) out["strokes"] = strokes
            if (avgSwolf != null) out["avgSwolf"] = avgSwolf
            if (paceSecPer100m != null) out["paceSecPer100m"] = paceSecPer100m
            if (tags.isNotEmpty()) out["tags"] = tags.map { it.toMap() }
            return out
        }
    }

    /**
     * WorkoutData page summary (0x17:0x0a).
     * Channel map stays header metadata + id+len tags; opaque sample bodies ride
     * [leftoverTlvs] for native file persist only (equivalent points until bitmap promote).
     */
    data class WorkoutDataPageSummary(
        val index: Int,
        val timestamp: Long? = null,
        val intervalSec: Int? = null,
        val sampleCount: Int? = null,
        val dataLength: Int? = null,
        val bitmap: Int? = null,
        val tags: List<EnrichmentTagRef> = emptyList(),
        val leftoverTlvs: List<HuaweiFraming.Tlv> = emptyList(),
    ) {
        val hasPointBodies: Boolean get() = leftoverTlvs.isNotEmpty()

        fun toMap(): Map<String, Any?> {
            val out = linkedMapOf<String, Any?>("index" to index)
            if (timestamp != null) out["timestamp"] = timestamp
            if (intervalSec != null) out["intervalSec"] = intervalSec
            if (sampleCount != null) out["sampleCount"] = sampleCount
            if (dataLength != null) out["dataLength"] = dataLength
            if (bitmap != null) out["bitmap"] = bitmap
            if (tags.isNotEmpty()) out["tags"] = tags.map { it.toMap() }
            return out
        }
    }

    data class PaceBlockSummary(
        val index: Int,
        val distanceM: Long? = null,
        val paceSec: Int? = null,
        val tags: List<EnrichmentTagRef> = emptyList(),
    ) {
        fun toMap(): Map<String, Any?> {
            val out = linkedMapOf<String, Any?>("index" to index)
            if (distanceM != null) out["distanceM"] = distanceM
            if (paceSec != null) out["paceSec"] = paceSec
            if (tags.isNotEmpty()) out["tags"] = tags.map { it.toMap() }
            return out
        }
    }

    data class WorkoutTotals(
        val number: Int,
        val startTime: Long,
        val endTime: Long,
        val durationSec: Long,
        val type: Int,
        val calories: Long?,
        val distanceM: Long?,
        val steps: Long?,
        val dataCount: Int = 0,
        val paceCount: Int = 0,
        val segmentsCount: Int = 0,
        val hrMin: Int? = null,
        val hrMax: Int? = null,
        val hrPeak: Int? = null,
        val swimType: Int? = null,
        val strokes: Int? = null,
        val strokeRate: Int? = null,
        val avgSwolf: Int? = null,
        val poolLength: Int? = null,
        val laps: Int? = null,
        /** Training load — catalog tag 0x0d; omit when absent or width mismatch. */
        val load: Int? = null,
        /** Aerobic training stress — catalog tag 0x0e. */
        val aerobicEffect: Int? = null,
        /** Anaerobic training stress — catalog tag 0x20. */
        val anaerobicEffect: Int? = null,
        /** Session recovery time — catalog tag 0x11. */
        val recoveryTime: Int? = null,
        /** Training points — catalog tag 0x63. */
        val trainingPoints: Int? = null,
        val enrichmentTags: List<EnrichmentTagRef> = emptyList(),
        /**
         * Unmatched / width-mismatched Totals TLVs kept as tag+len+body.
         * Recovery-HR (0x66) rides here as an opaque blob. Logs use id+len only.
         */
        val leftoverTlvs: List<HuaweiFraming.Tlv> = emptyList(),
    ) {
        fun toMap(
            leftoverSink: ((id: String, bytes: ByteArray) -> String?)? = null,
            forceSpill: Boolean = false,
        ): Map<String, Any?> {
            val out = linkedMapOf<String, Any?>(
                "number" to number,
                "startTime" to startTime,
                "endTime" to endTime,
                "durationSec" to durationSec,
                "type" to type,
                "calories" to calories,
                "distanceM" to distanceM,
                "steps" to steps,
                "dataCount" to dataCount,
                "paceCount" to paceCount,
                "segmentsCount" to segmentsCount,
            )
            if (hrMin != null) out["hrMin"] = hrMin
            if (hrMax != null) out["hrMax"] = hrMax
            if (hrPeak != null) out["hrPeak"] = hrPeak
            if (swimType != null) out["swimType"] = swimType
            if (strokes != null) out["strokes"] = strokes
            if (strokeRate != null) out["strokeRate"] = strokeRate
            if (avgSwolf != null) out["avgSwolf"] = avgSwolf
            if (poolLength != null) out["poolLength"] = poolLength
            if (laps != null) out["laps"] = laps
            if (load != null) out["load"] = load
            if (aerobicEffect != null) out["aerobicEffect"] = aerobicEffect
            if (anaerobicEffect != null) out["anaerobicEffect"] = anaerobicEffect
            if (recoveryTime != null) out["recoveryTime"] = recoveryTime
            if (trainingPoints != null) out["trainingPoints"] = trainingPoints
            if (enrichmentTags.isNotEmpty()) {
                out["enrichmentTags"] = enrichmentTags.map { it.toMap() }
            }
            if (leftoverTlvs.isNotEmpty()) {
                val leftoverBytes = HuaweiFraming.encodeTlvs(leftoverTlvs)
                out["leftoverLen"] = leftoverBytes.size
                val shouldSpill = forceSpill ||
                    leftoverBytes.size > LEFTOVER_INLINE_MAX_BYTES
                if (shouldSpill && leftoverSink != null) {
                    val id = "${number}_$startTime"
                    val path = leftoverSink(id, leftoverBytes)
                    if (path != null) {
                        out["leftoverPath"] = path
                        out["leftoverPresent"] = true
                        Log.i(
                            TAG,
                            "workout-sync leftover spilled number=$number " +
                                "len=${leftoverBytes.size} path=$path",
                        )
                    } else {
                        // Sink failed — fall back to inline so Dart can still persist.
                        out["leftover"] = leftoverBytes
                        out["leftoverPresent"] = true
                        Log.w(
                            TAG,
                            "workout-sync leftover spill failed number=$number " +
                                "len=${leftoverBytes.size} — inlining",
                        )
                    }
                } else {
                    out["leftover"] = leftoverBytes
                    out["leftoverPresent"] = true
                }
            }
            return out
        }

        fun withCountHints(ref: WorkoutNumber): WorkoutTotals = copy(
            dataCount = ref.dataCount,
            paceCount = ref.paceCount,
            segmentsCount = ref.segmentsCount,
        )
    }

    /**
     * @param enrichStartUnix floor for hint-gated Data/Pace/Swim. During leftover-keep
     * one-shot, Count uses [startUnix] (2022 floor) while enrich stays incremental.
     * Strength (`type=140` with `dataCount>0`) is always enrich-eligible.
     * @return status: ok | empty | stuck | error | partial_batch; workouts: totals maps
     */
    fun sync(
        startUnix: Long,
        endUnix: Long,
        enrichStartUnix: Long = startUnix,
    ): Map<String, Any?> {
        val start = startUnix.coerceAtLeast(0)
        val end = endUnix.coerceAtLeast(start)
        val enrichFloor = enrichStartUnix.coerceAtLeast(0)
        Log.i(TAG, "workout-sync start window=[$start,$end] enrichStart=$enrichFloor")

        val countFrame = exchangeEncrypted(
            buildCountRequest(start, end),
            SVC,
            CMD_COUNT,
            TIMEOUT_MS,
        )
        if (countFrame == null) {
            Log.w(TAG, "workout-sync count timeout")
            return mapOf(
                "status" to "stuck",
                "message" to "Workout count timed out — disconnect and retry",
                "workouts" to emptyList<Map<String, Any?>>(),
            )
        }

        val numbers = parseCount(countFrame).sortedBy { it.workoutNumber }
        Log.i(TAG, "workout-sync count=${numbers.size}")
        if (numbers.isEmpty()) {
            return mapOf(
                "status" to "empty",
                "workouts" to emptyList<Map<String, Any?>>(),
            )
        }

        val workouts = ArrayList<Map<String, Any?>>(numbers.size)
        var enrichmentPartial = false
        var leftoverChannelBytes = 0
        for (ref in numbers) {
            val totalsFrame = exchangeEncrypted(
                buildTotalsRequest(ref.workoutNumber),
                SVC,
                CMD_TOTALS,
                TIMEOUT_MS,
            )
            if (totalsFrame == null) {
                Log.w(TAG, "workout-sync totals timeout number=${ref.workoutNumber}")
                return mapOf(
                    "status" to "stuck",
                    "message" to "Workout totals timed out at #${ref.workoutNumber}",
                    "workouts" to workouts,
                )
            }
            val totals = parseTotals(totalsFrame)?.withCountHints(ref)
            if (totals == null) {
                Log.w(TAG, "workout-sync totals parse failed number=${ref.workoutNumber}")
                continue
            }
            Log.i(
                TAG,
                "workout-sync totals number=${totals.number} type=${totals.type} " +
                    "start=${totals.startTime} duration=${totals.durationSec}s " +
                    "data=${totals.dataCount} pace=${totals.paceCount} seg=${totals.segmentsCount}",
            )
            val leftoverLenHint = if (totals.leftoverTlvs.isNotEmpty()) {
                HuaweiFraming.encodeTlvs(totals.leftoverTlvs).size
            } else {
                0
            }
            val forceSpill = leftoverLenHint > 0 && (
                leftoverLenHint > LEFTOVER_INLINE_MAX_BYTES ||
                    leftoverChannelBytes + leftoverLenHint > LEFTOVER_CHANNEL_BUDGET_BYTES
                )
            val workoutMap = LinkedHashMap(
                totals.toMap(
                    leftoverSink = persistWorkoutLeftovers,
                    forceSpill = forceSpill,
                ),
            )
            if (workoutMap.containsKey("leftover")) {
                leftoverChannelBytes += (workoutMap["leftoverLen"] as? Int) ?: 0
            }
            val hasHints =
                totals.segmentsCount > 0 || totals.dataCount > 0 || totals.paceCount > 0
            val strengthWithData = totals.type == 140 && totals.dataCount > 0
            val inEnrichWindow = totals.startTime >= enrichFloor
            // One-shot: Count+Totals for history; hint-gated enrich only for
            // strength-with-data or already-recent rows — not years of swim/run Data.
            if (hasHints && (strengthWithData || inEnrichWindow)) {
                if (enrichWorkout(workoutMap, totals)) {
                    enrichmentPartial = true
                }
            } else {
                // Totals-only historical must not be enrichmentStatus=partial
                // (Flutter clock 3 would otherwise reopen the 2022 Count floor).
                workoutMap["enrichmentStatus"] = "none"
                workoutMap["sampleFetch"] = "none"
            }
            workouts.add(workoutMap)
        }

        return mapOf(
            "status" to if (enrichmentPartial) "partial_batch" else "ok",
            "workouts" to workouts,
        )
    }

    /**
     * Fetch segments → data pages → pace (last). Returns true if any enrichment timed out.
     * Never throws; Totals fields in [out] are preserved.
     */
    private fun enrichWorkout(out: MutableMap<String, Any?>, totals: WorkoutTotals): Boolean {
        var partial = false
        var enrichmentTimedOut = false

        if (totals.segmentsCount > 0) {
            // GB oracle: request page index in TLV 0x08; each page returns 0x83 blocks
            // that are appended (metric unitType=0 preferred). Do not half-dedupe.
            val collected = ArrayList<SwimSegment>()
            for (index in 0 until totals.segmentsCount) {
                val frame = exchangeEncrypted(
                    buildSwimSegmentRequest(totals.number, index),
                    SVC,
                    CMD_SWIM,
                    TIMEOUT_MS,
                )
                if (frame == null) {
                    Log.w(
                        TAG,
                        "workout-sync swim timeout number=${totals.number} index=$index",
                    )
                    partial = true
                    enrichmentTimedOut = true
                    break
                }
                collected.addAll(parseSwimSegments(frame))
            }
            val metric = collected.filter { it.unitType == null || it.unitType == 0 }
            val chosen = if (metric.isNotEmpty()) metric else collected
            if (chosen.isNotEmpty()) {
                out["segments"] = chosen.mapIndexed { i, seg ->
                    seg.copy(index = i).toMap()
                }
            }
            Log.i(
                TAG,
                "workout-sync swim number=${totals.number} " +
                    "fetched=${chosen.size} pages=${totals.segmentsCount} " +
                    "raw=${collected.size}",
            )
        }

        if (totals.dataCount > 0) {
            val pages = ArrayList<WorkoutDataPageSummary>()
            var sampleTotal = 0
            var dataTimedOut = false
            for (index in 0 until totals.dataCount) {
                val frame = exchangeEncrypted(
                    buildWorkoutDataRequest(totals.number, index),
                    SVC,
                    CMD_DATA,
                    TIMEOUT_MS,
                )
                if (frame == null) {
                    Log.w(
                        TAG,
                        "workout-sync data timeout number=${totals.number} index=$index",
                    )
                    partial = true
                    enrichmentTimedOut = true
                    dataTimedOut = true
                    break
                }
                parseWorkoutDataPage(frame, index)?.let { page ->
                    pages.add(page)
                    sampleTotal += page.sampleCount ?: 0
                }
            }
            if (pages.isNotEmpty()) {
                // Channel: header metadata only — never the opaque point series.
                out["dataPages"] = pages.map { it.toMap() }
                if (sampleTotal > 0) out["sampleCount"] = sampleTotal
            }
            val pointPages = pages.filter { it.hasPointBodies }
            val sampleFetch = when {
                dataTimedOut -> "timeout"
                pointPages.isNotEmpty() -> "ok"
                pages.isNotEmpty() -> "partial"
                else -> "partial"
            }
            out["sampleFetch"] = sampleFetch
            if (pointPages.isNotEmpty()) {
                val fileBytes = encodeWorkoutSampleFile(pointPages)
                val sampleId = "${totals.number}_${totals.startTime}"
                val path = persistWorkoutSamples?.invoke(sampleId, fileBytes)
                if (path != null) {
                    out["samplePath"] = path
                }
                Log.i(
                    TAG,
                    "workout-sync data number=${totals.number} " +
                        "pages=${pages.size}/${totals.dataCount} samples=$sampleTotal " +
                        "pointsPages=${pointPages.size} persisted=${path != null}",
                )
            } else {
                Log.i(
                    TAG,
                    "workout-sync data number=${totals.number} " +
                        "pages=${pages.size}/${totals.dataCount} samples=$sampleTotal " +
                        "pointsPages=0 sampleFetch=$sampleFetch",
                )
            }
        } else {
            out["sampleFetch"] = "none"
        }

        if (totals.paceCount > 0 && !enrichmentTimedOut) {
            val paceBlocks = ArrayList<Map<String, Any?>>()
            for (index in 0 until totals.paceCount) {
                val frame = exchangeEncrypted(
                    buildPaceRequest(totals.number, index),
                    SVC,
                    CMD_PACE,
                    TIMEOUT_MS,
                )
                if (frame == null) {
                    Log.w(
                        TAG,
                        "workout-sync pace timeout number=${totals.number} index=$index",
                    )
                    partial = true
                    break
                }
                parsePaceBlock(frame, index)?.let { paceBlocks.add(it.toMap()) }
            }
            if (paceBlocks.isNotEmpty()) {
                out["paceBlocks"] = paceBlocks
            }
            Log.i(
                TAG,
                "workout-sync pace number=${totals.number} " +
                    "blocks=${paceBlocks.size}/${totals.paceCount}",
            )
        } else if (totals.paceCount > 0 && enrichmentTimedOut) {
            Log.d(
                TAG,
                "workout-sync pace skipped number=${totals.number} " +
                    "after enrichment timeout",
            )
        }

        out["enrichmentStatus"] = when {
            partial -> "partial"
            totals.segmentsCount > 0 || totals.dataCount > 0 || totals.paceCount > 0 -> "ok"
            else -> "none"
        }
        return partial
    }

    fun fetchWorkoutData(workoutNumber: Int, dataIndex: Int): Map<String, Any?> {
        if (dataIndex < 0) return emptyMap()
        val frame = exchangeEncrypted(
            buildWorkoutDataRequest(workoutNumber, dataIndex),
            SVC,
            CMD_DATA,
            TIMEOUT_MS,
        ) ?: return emptyMap()
        return parseWorkoutDataPage(frame, dataIndex)?.toMap() ?: emptyMap()
    }

    /** Pace command 0x17:0x0c (not Totals TLV tag 0x0c). */
    fun fetchPaceBlock(workoutNumber: Int, paceIndex: Int): Map<String, Any?> {
        if (paceIndex < 0) return emptyMap()
        val frame = exchangeEncrypted(
            buildPaceRequest(workoutNumber, paceIndex),
            SVC,
            CMD_PACE,
            TIMEOUT_MS,
        ) ?: return emptyMap()
        return parsePaceBlock(frame, paceIndex)?.toMap() ?: emptyMap()
    }

    /** Swim segments command 0x17:0x0e — returns all nested laps from one page. */
    fun fetchSwimSegment(workoutNumber: Int, segmentIndex: Int): Map<String, Any?> {
        if (segmentIndex < 0) return emptyMap()
        val frame = exchangeEncrypted(
            buildSwimSegmentRequest(workoutNumber, segmentIndex),
            SVC,
            CMD_SWIM,
            TIMEOUT_MS,
        ) ?: return emptyMap()
        val segments = parseSwimSegments(frame)
        if (segments.isEmpty()) return emptyMap()
        return mapOf("segments" to segments.map { it.toMap() })
    }

    /** WorkoutData 0x0a — page index is TLV 0x03 (GB WorkoutData.Request). */
    private fun buildWorkoutDataRequest(workoutNumber: Int, dataIndex: Int): HuaweiFraming.Frame {
        val nested = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(workoutNumber)),
                HuaweiFraming.Tlv(0x03, HuaweiPacketCrypto.shortBe(dataIndex)),
            ),
        )
        return HuaweiFraming.Frame(
            SVC,
            CMD_DATA,
            listOf(HuaweiFraming.Tlv(0x81, nested)),
        )
    }

    /**
     * Pace 0x0c / Swim 0x0e — page index is TLV **0x08** (GB WorkoutPace /
     * WorkoutSwimSegments.Request). Using 0x03 here makes the watch ignore the
     * page and repeat the first batch (observed: always 6 unique laps).
     */
    private fun buildPaceOrSwimPageRequest(
        workoutNumber: Int,
        pageIndex: Int,
        commandId: Int,
    ): HuaweiFraming.Frame {
        val nested = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(workoutNumber)),
                HuaweiFraming.Tlv(0x08, HuaweiPacketCrypto.shortBe(pageIndex)),
            ),
        )
        return HuaweiFraming.Frame(
            SVC,
            commandId,
            listOf(HuaweiFraming.Tlv(0x81, nested)),
        )
    }

    private fun buildPaceRequest(workoutNumber: Int, paceIndex: Int): HuaweiFraming.Frame =
        buildPaceOrSwimPageRequest(workoutNumber, paceIndex, CMD_PACE)

    private fun buildSwimSegmentRequest(workoutNumber: Int, segmentIndex: Int): HuaweiFraming.Frame =
        buildPaceOrSwimPageRequest(workoutNumber, segmentIndex, CMD_SWIM)

    private fun buildCountRequest(startUnix: Long, endUnix: Long): HuaweiFraming.Frame {
        val nested = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x03, HuaweiPacketCrypto.intBe(startUnix.toInt())),
                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(endUnix.toInt())),
            ),
        )
        return HuaweiFraming.Frame(
            SVC,
            CMD_COUNT,
            listOf(HuaweiFraming.Tlv(0x81, nested)),
        )
    }

    private fun buildTotalsRequest(workoutNumber: Int): HuaweiFraming.Frame {
        val nested = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(workoutNumber)),
            ),
        )
        return HuaweiFraming.Frame(
            SVC,
            CMD_TOTALS,
            listOf(HuaweiFraming.Tlv(0x81, nested)),
        )
    }

    fun parseCount(frame: HuaweiFraming.Frame): List<WorkoutNumber> {
        val container = frame.tlvs.firstOrNull { it.tag == 0x81 }?.value
            ?: return emptyList()
        val tlvs = HuaweiFraming.decodeTlvs(container)
        val out = ArrayList<WorkoutNumber>()
        for (tlv in tlvs) {
            if (tlv.tag != 0x85) continue
            val inner = HuaweiFraming.decodeTlvs(tlv.value)
            var number = 0
            var dataCount = 0
            var paceCount = 0
            var segmentsCount = 0
            for (child in inner) {
                when (child.tag) {
                    0x06 -> number = u16(child.value)
                    0x07 -> dataCount = u16(child.value)
                    0x08 -> paceCount = u16(child.value)
                    0x09 -> segmentsCount = u16(child.value)
                }
            }
            if (number > 0) {
                out.add(
                    WorkoutNumber(
                        workoutNumber = number,
                        dataCount = dataCount,
                        paceCount = paceCount,
                        segmentsCount = segmentsCount,
                    ),
                )
            }
        }
        return out
    }

    fun parseTotals(frame: HuaweiFraming.Frame): WorkoutTotals? {
        val container = frame.tlvs.firstOrNull { it.tag == 0x81 }?.value
            ?: return null
        val tlvs = HuaweiFraming.decodeTlvs(container)
        var number = 0
        var startTime = 0L
        var endTime = 0L
        var durationSec = 0L
        var type = 0
        var calories: Long? = null
        var distanceM: Long? = null
        var steps: Long? = null
        var hrMin: Int? = null
        var hrMax: Int? = null
        var hrPeak: Int? = null
        var swimType: Int? = null
        var strokes: Int? = null
        var strokeRate: Int? = null
        var avgSwolf: Int? = null
        var poolLength: Int? = null
        var laps: Int? = null
        var load: Int? = null
        var aerobicEffect: Int? = null
        var anaerobicEffect: Int? = null
        var recoveryTime: Int? = null
        var trainingPoints: Int? = null
        val unknownTags = ArrayList<EnrichmentTagRef>()
        val leftoverTlvs = ArrayList<HuaweiFraming.Tlv>()
        for (tlv in tlvs) {
            when (tlv.tag) {
                0x02 -> number = u16(tlv.value)
                0x04 -> startTime = u32(tlv.value)
                0x05 -> endTime = u32(tlv.value)
                0x06 -> calories = u32(tlv.value)
                0x07 -> distanceM = u32(tlv.value)
                0x08 -> steps = u32(tlv.value)
                0x09 -> if (durationSec == 0L) durationSec = u32(tlv.value)
                0x12 -> durationSec = u32(tlv.value)
                0x14 -> type = u8(tlv.value)
                0x0c -> parseHrPeakTlv(tlv)?.let { (min, max, peak) ->
                    hrMin = min
                    hrMax = max
                    hrPeak = peak
                } ?: run {
                    Log.d(TAG, "workout-sync tag 0x0c len=${tlv.value.size} unparsed")
                    unknownTags.add(EnrichmentTagRef(0x0c, tlv.value.size))
                }
                // Locked community scalars: strip from leftover only on width match.
                0x0d -> parseScalarU32(tlv)?.let { load = it.toInt() }
                    ?: keepLeftover(leftoverTlvs, tlv)
                0x0e -> parseScalarU32(tlv)?.let { aerobicEffect = it.toInt() }
                    ?: keepLeftover(leftoverTlvs, tlv)
                0x11 -> parseScalarU16(tlv)?.let { recoveryTime = it }
                    ?: keepLeftover(leftoverTlvs, tlv)
                0x20 -> parseScalarU8(tlv)?.let { anaerobicEffect = it }
                    ?: keepLeftover(leftoverTlvs, tlv)
                0x63 -> parseScalarU16(tlv)?.let { trainingPoints = it }
                    ?: keepLeftover(leftoverTlvs, tlv)
                // Recovery-HR stays opaque leftover — never integer-decode.
                0x66 -> keepLeftover(leftoverTlvs, tlv)
                0x15 -> parseScalarU8(tlv)?.let { swimType = it }
                    ?: recordUnknown(unknownTags, tlv)
                0x16 -> parseScalarU32OrU16(tlv)?.let { strokes = it }
                    ?: recordUnknown(unknownTags, tlv)
                0x17 -> parseScalarU16OrU8(tlv)?.let { strokeRate = it }
                    ?: recordUnknown(unknownTags, tlv)
                0x18 -> parseScalarU16(tlv)?.let { poolLength = it }
                    ?: recordUnknown(unknownTags, tlv)
                0x19 -> parseScalarU16OrU8(tlv)?.let { laps = it }
                    ?: recordUnknown(unknownTags, tlv)
                0x1a -> parseScalarU16(tlv)?.let { avgSwolf = it }
                    ?: recordUnknown(unknownTags, tlv)
                else -> keepLeftover(leftoverTlvs, tlv)
            }
        }
        if (number == 0 || startTime == 0L) return null
        if (durationSec == 0L && endTime > startTime) {
            durationSec = endTime - startTime
        }
        return WorkoutTotals(
            number = number,
            startTime = startTime,
            endTime = endTime,
            durationSec = durationSec,
            type = type,
            calories = calories,
            distanceM = distanceM,
            steps = steps,
            hrMin = hrMin,
            hrMax = hrMax,
            hrPeak = hrPeak,
            swimType = swimType,
            strokes = strokes,
            strokeRate = strokeRate,
            avgSwolf = avgSwolf,
            poolLength = poolLength,
            laps = laps,
            load = load,
            aerobicEffect = aerobicEffect,
            anaerobicEffect = anaerobicEffect,
            recoveryTime = recoveryTime,
            trainingPoints = trainingPoints,
            enrichmentTags = unknownTags,
            leftoverTlvs = leftoverTlvs,
        )
    }

    private fun recordUnknown(out: MutableList<EnrichmentTagRef>, tlv: HuaweiFraming.Tlv) {
        Log.d(TAG, "workout-sync tag 0x${tlv.tag.toString(16)} len=${tlv.value.size} unparsed")
        out.add(EnrichmentTagRef(tlv.tag, tlv.value.size))
    }

    /** Totals-only: keep unmatched / width-mismatched TLV bodies. Log id+len only. */
    private fun keepLeftover(out: MutableList<HuaweiFraming.Tlv>, tlv: HuaweiFraming.Tlv) {
        Log.d(TAG, "workout-sync leftover tag 0x${tlv.tag.toString(16)} len=${tlv.value.size}")
        out.add(tlv)
    }

    /** Totals TLV 0x0c — oracle suggests 2-byte min/max peaks; accept u8 pair or u16. */
    private fun parseHrPeakTlv(tlv: HuaweiFraming.Tlv): Triple<Int?, Int?, Int?>? {
        return when (tlv.value.size) {
            1 -> Triple(null, null, u8(tlv.value))
            2 -> Triple(u8(tlv.value, 0), u8(tlv.value, 1), null)
            4 -> Triple(u16(tlv.value, 0), u16(tlv.value, 2), null)
            else -> null
        }
    }

    private fun parseScalarU8(tlv: HuaweiFraming.Tlv): Int? =
        if (tlv.value.size == 1) u8(tlv.value) else null

    private fun parseScalarU16(tlv: HuaweiFraming.Tlv): Int? =
        if (tlv.value.size == 2) u16(tlv.value) else null

    private fun parseScalarU32(tlv: HuaweiFraming.Tlv): Long? =
        if (tlv.value.size == 4) u32(tlv.value) else null

    private fun parseScalarU16OrU8(tlv: HuaweiFraming.Tlv): Int? = when (tlv.value.size) {
        1 -> u8(tlv.value)
        2 -> u16(tlv.value)
        else -> null
    }

    private fun parseScalarU32OrU16(tlv: HuaweiFraming.Tlv): Int? = when (tlv.value.size) {
        2 -> u16(tlv.value)
        4 -> u32(tlv.value).toInt()
        else -> null
    }

    /**
     * Parse all nested swim laps from a 0x17:0x0e page.
     *
     * Envelope: `0x81` → `0x02` workout #, `0x08` page #, repeated `0x83` blocks.
     * Block map (GB oracle): `0x04` distance m, `0x05` unit type, `0x06` pace,
     * `0x07` pointIndex, `0x09` segment #, `0x0a` style, `0x0b` strokes,
     * `0x0c` SWOLF, `0x0d` time s.
     */
    fun parseSwimSegments(frame: HuaweiFraming.Frame): List<SwimSegment> {
        val container = frame.tlvs.firstOrNull { it.tag == 0x81 }?.value ?: return emptyList()
        return parseSwimSegmentPageTlvs(HuaweiFraming.decodeTlvs(container))
    }

    /** First lap only — kept for callers that expect a single segment. */
    fun parseSwimSegment(frame: HuaweiFraming.Frame, segmentIndex: Int): SwimSegment? {
        val all = parseSwimSegments(frame)
        return all.firstOrNull { it.index == segmentIndex } ?: all.firstOrNull()
    }

    internal fun parseSwimSegmentPageTlvs(tlvs: List<HuaweiFraming.Tlv>): List<SwimSegment> {
        val out = ArrayList<SwimSegment>()
        var sequential = 0
        for (tlv in tlvs) {
            when (tlv.tag) {
                0x83 -> parseNestedSwimLap(tlv.value, sequential)?.let {
                    out.add(it)
                    sequential++
                }
                0x02, 0x03, 0x08 -> Unit // workout # / legacy index / page index
                else -> Log.d(
                    TAG,
                    "workout-sync swim page tag 0x${tlv.tag.toString(16)} " +
                        "len=${tlv.value.size} unparsed",
                )
            }
        }
        return out
    }

    private fun parseNestedSwimLap(value: ByteArray, fallbackIndex: Int): SwimSegment? {
        val inner = HuaweiFraming.decodeTlvs(value)
        var wireSegment: Int? = null
        var unitType: Int? = null
        var distanceM: Long? = null
        var durationSec: Long? = null
        var style: Int? = null
        var strokes: Int? = null
        var avgSwolf: Int? = null
        var wirePace: Int? = null
        val unknownTags = ArrayList<EnrichmentTagRef>()
        for (tlv in inner) {
            when (tlv.tag) {
                0x04 -> parseScalarFlexible(tlv)?.let { distanceM = it.toLong() }
                    ?: recordUnknown(unknownTags, tlv)
                0x05 -> unitType = parseScalarU8(tlv) ?: parseScalarU16OrU8(tlv)
                0x06 -> parseScalarFlexible(tlv)?.let { wirePace = it }
                    ?: recordUnknown(unknownTags, tlv)
                0x07 -> Unit // pointIndex — not needed for lap table
                0x09 -> wireSegment = parseScalarFlexible(tlv)
                0x0a -> parseScalarU8(tlv)?.let { style = it }
                    ?: recordUnknown(unknownTags, tlv)
                0x0b -> parseScalarFlexible(tlv)?.let { strokes = it }
                    ?: recordUnknown(unknownTags, tlv)
                0x0c -> parseScalarFlexible(tlv)?.let { avgSwolf = it }
                    ?: recordUnknown(unknownTags, tlv)
                0x0d -> parseScalarFlexible(tlv)?.let { durationSec = it.toLong() }
                    ?: recordUnknown(unknownTags, tlv)
                else -> recordUnknown(unknownTags, tlv)
            }
        }
        // Need at least one swim metric — empty 0x83 is noise.
        if (distanceM == null && durationSec == null && strokes == null && avgSwolf == null) {
            return null
        }
        val index = when {
            wireSegment == null -> fallbackIndex
            wireSegment >= 1 -> wireSegment - 1
            else -> wireSegment
        }
        val computedPace = if (distanceM != null && distanceM > 0 && durationSec != null) {
            ((durationSec * 100) / distanceM).toInt()
        } else {
            null
        }
        return SwimSegment(
            index = index,
            distanceM = distanceM,
            durationSec = durationSec,
            style = style,
            strokes = strokes,
            avgSwolf = avgSwolf,
            paceSecPer100m = wirePace ?: computedPace,
            unitType = unitType,
            tags = unknownTags,
        )
    }

    private fun parseScalarFlexible(tlv: HuaweiFraming.Tlv): Int? = when (tlv.value.size) {
        1 -> u8(tlv.value)
        2 -> u16(tlv.value)
        4 -> u32(tlv.value).toInt()
        else -> null
    }

    fun parseWorkoutDataPage(frame: HuaweiFraming.Frame, dataIndex: Int): WorkoutDataPageSummary? {
        val container = frame.tlvs.firstOrNull { it.tag == 0x81 }?.value ?: return null
        return parseWorkoutDataPageTlvs(HuaweiFraming.decodeTlvs(container), dataIndex)
    }

    internal fun parseWorkoutDataPageTlvs(
        tlvs: List<HuaweiFraming.Tlv>,
        dataIndex: Int,
    ): WorkoutDataPageSummary {
        var index = dataIndex
        var timestamp: Long? = null
        var intervalSec: Int? = null
        var sampleCount: Int? = null
        var dataLength: Int? = null
        var bitmap: Int? = null
        val unknownTags = ArrayList<EnrichmentTagRef>()
        val leftoverTlvs = ArrayList<HuaweiFraming.Tlv>()
        for (tlv in tlvs) {
            when (tlv.tag) {
                0x02 -> { /* workoutNumber — ignore for summary */ }
                0x03 -> index = u16(tlv.value)
                0x04 -> timestamp = u32(tlv.value)
                0x05 -> intervalSec = parseScalarU32OrU16(tlv)
                0x06 -> sampleCount = parseScalarU32OrU16(tlv)
                0x07 -> dataLength = parseScalarU32OrU16(tlv)
                0x08 -> bitmap = parseScalarU32OrU16(tlv)
                else -> {
                    // Opaque sample / unmatched bodies — equivalent points until bitmap promote.
                    keepLeftover(leftoverTlvs, tlv)
                    unknownTags.add(EnrichmentTagRef(tlv.tag, tlv.value.size))
                }
            }
        }
        return WorkoutDataPageSummary(
            index = index,
            timestamp = timestamp,
            intervalSec = intervalSec,
            sampleCount = sampleCount,
            dataLength = dataLength,
            bitmap = bitmap,
            tags = unknownTags,
            leftoverTlvs = leftoverTlvs,
        )
    }

    /**
     * Native sample file: per-page 0x81 containers with header metadata + leftover bodies.
     * Logs/channel never carry the series; dump treats leftover bytes as equivalent points.
     */
    internal fun encodeWorkoutSampleFile(pages: List<WorkoutDataPageSummary>): ByteArray {
        val pageTlvs = ArrayList<HuaweiFraming.Tlv>(pages.size)
        for (page in pages) {
            val inner = ArrayList<HuaweiFraming.Tlv>()
            inner.add(HuaweiFraming.Tlv(0x03, HuaweiPacketCrypto.shortBe(page.index)))
            page.timestamp?.let {
                inner.add(HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(it.toInt())))
            }
            page.intervalSec?.let {
                inner.add(HuaweiFraming.Tlv(0x05, HuaweiPacketCrypto.shortBe(it)))
            }
            page.sampleCount?.let {
                inner.add(HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.shortBe(it)))
            }
            page.dataLength?.let {
                inner.add(HuaweiFraming.Tlv(0x07, HuaweiPacketCrypto.shortBe(it)))
            }
            page.bitmap?.let {
                inner.add(HuaweiFraming.Tlv(0x08, HuaweiPacketCrypto.shortBe(it)))
            }
            inner.addAll(page.leftoverTlvs)
            pageTlvs.add(HuaweiFraming.Tlv(0x81, HuaweiFraming.encodeTlvs(inner)))
        }
        return HuaweiFraming.encodeTlvs(pageTlvs)
    }

    fun parsePaceBlock(frame: HuaweiFraming.Frame, paceIndex: Int): PaceBlockSummary? {
        val container = frame.tlvs.firstOrNull { it.tag == 0x81 }?.value ?: return null
        return parsePaceBlockTlvs(HuaweiFraming.decodeTlvs(container), paceIndex)
    }

    internal fun parsePaceBlockTlvs(tlvs: List<HuaweiFraming.Tlv>, paceIndex: Int): PaceBlockSummary {
        var index = paceIndex
        var distanceM: Long? = null
        var paceSec: Int? = null
        val unknownTags = ArrayList<EnrichmentTagRef>()
        for (tlv in tlvs) {
            when (tlv.tag) {
                0x02 -> { /* workoutNumber */ }
                0x03 -> index = u16(tlv.value)
                0x07 -> distanceM = u32(tlv.value)
                0x0b -> paceSec = parseScalarU32OrU16(tlv)
                else -> recordUnknown(unknownTags, tlv)
            }
        }
        return PaceBlockSummary(
            index = index,
            distanceM = distanceM,
            paceSec = paceSec,
            tags = unknownTags,
        )
    }
}
