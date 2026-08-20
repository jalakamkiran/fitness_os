package com.example.fitness_os.huawei

import android.util.Log
import java.nio.ByteBuffer
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/**
 * Clean-room FitnessData (`0x07`) activity Sync — sleep messages +
 * FitnessTotals day rollup + TruSleep FileDownload (`sleep_state` only).
 *
 * Continuous / daily HR is **not** pulled or soft-armed on Sync (Enable may
 * still arm auto-HR separately). Pre-promotion parsers: synthetic fixtures +
 * owned wire-spec shapes only.
 *
 * FileSleep / TruSleep FileDownload: non-blocking after messages (soft-fail);
 * intervals alone are mergeable success when messages are empty.
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
    /**
     * Optional override for tests. Default builds a soft-skip [HuaweiFileDownload].
     * Session injects a live-download collaborator.
     */
    private val sleepFileDownload: (() -> HuaweiFileDownload)? = null,
    /** @deprecated Prefer [sleepFileDownload]. */
    private val sleepFileDownloadProbe: (() -> HuaweiFileDownload.ProbeOutcome)? = null,
    /** Privacy-safe watch clock/zone scalars for Flutter → Sentry observe. */
    private val watchClockSnapshot: (() -> Map<String, Any?>)? = null,
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
        /** Catalog: SpO₂ lives in a second bitmap (`0x01`). Layout after HR is unowned — hint only. */
        /** Drop sub-15m fragments (paging noise / empty tails). */
        private const val MIN_SESSION_SEC = 15 * 60L
        /** Match Flutter [TruSleepSleepSot.mergeGapSec] — near-adjacent file fragments. */
        private const val FILE_INTERVAL_MERGE_GAP_SEC = 180

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

        fun intervalMinutes(intervals: List<Pair<Long, Long>>): Int =
            intervals.sumOf { ((it.second - it.first).coerceAtLeast(0L) / 60L).toInt() }

        fun lastNightIntervals(
            intervals: List<Pair<Long, Long>>,
            nowUnix: Long,
            lookbackSec: Long = 36L * 3600L,
        ): List<Pair<Long, Long>> =
            intervals.filter { it.second >= nowUnix - lookbackSec }

        fun countUnixInIntervals(
            timestamps: Collection<Long>,
            intervals: List<Pair<Long, Long>>,
        ): Int = timestamps.count { ts ->
            intervals.any { ts >= it.first && ts < it.second }
        }

        fun u32(value: ByteArray, offset: Int = 0): Long {
            if (value.size < offset + 4) return 0L
            return ByteBuffer.wrap(value, offset, 4).int.toLong() and 0xFFFF_FFFFL
        }

        /**
         * Privacy-safe TLV shape: `t=81:len=42x1;nested[t=85:len=20x2,t=05:len=4x3]`.
         * Recursively counts tag+len under nested containers (high bit set).
         */
        fun tlvTagLenHistogram(tlvs: List<HuaweiFraming.Tlv>): String {
            if (tlvs.isEmpty()) return "empty"
            val top = countTagLens(tlvs)
            val nestedCounts = linkedMapOf<String, Int>()
            fun walkNested(list: List<HuaweiFraming.Tlv>) {
                for (tlv in list) {
                    if (!tlv.isNested || tlv.value.isEmpty()) continue
                    val inner = runCatching { HuaweiFraming.decodeTlvs(tlv.value) }.getOrNull()
                        ?: continue
                    for ((key, n) in countTagLens(inner)) {
                        nestedCounts[key] = (nestedCounts[key] ?: 0) + n
                    }
                    walkNested(inner)
                }
            }
            walkNested(tlvs)
            return if (nestedCounts.isEmpty()) {
                formatTagLens(top)
            } else {
                "${formatTagLens(top)};nested[${formatTagLens(nestedCounts)}]"
            }
        }

        /**
         * Debug-only leaf scalars (len 1/2/4) as BE integers — for owner watch cross-check.
         * Does not claim field meaning.
         */
        fun leafScalarCandidates(
            tlvs: List<HuaweiFraming.Tlv>,
            maxEntries: Int = 48,
        ): String {
            val out = ArrayList<String>()
            fun walk(list: List<HuaweiFraming.Tlv>, path: String) {
                for (tlv in list) {
                    if (out.size >= maxEntries) return
                    val tagHex = "0x${tlv.tag.toString(16)}"
                    val here = if (path.isEmpty()) tagHex else "$path/$tagHex"
                    if (tlv.isNested && tlv.value.isNotEmpty()) {
                        val inner = runCatching { HuaweiFraming.decodeTlvs(tlv.value) }.getOrNull()
                        if (inner != null) {
                            walk(inner, here)
                            continue
                        }
                    }
                    when (tlv.value.size) {
                        1 -> out.add("$here:u8=${u8(tlv.value)}")
                        2 -> out.add("$here:u16=${u16(tlv.value)}")
                        4 -> out.add("$here:u32=${u32(tlv.value)}")
                        else -> Unit
                    }
                }
            }
            walk(tlvs, "")
            return out.joinToString(" ")
        }

        private fun countTagLens(tlvs: List<HuaweiFraming.Tlv>): Map<String, Int> {
            val counts = linkedMapOf<String, Int>()
            for (tlv in tlvs) {
                val key = "t=${tlv.tag.toString(16)}:len=${tlv.value.size}"
                counts[key] = (counts[key] ?: 0) + 1
            }
            return counts
        }

        private fun formatTagLens(counts: Map<String, Int>): String =
            counts.entries.joinToString(",") { (k, n) -> "${k}x$n" }

        private fun shouldLogDebugScalars(): Boolean {
            return try {
                val clazz = Class.forName("com.example.fitness_os.BuildConfig")
                clazz.getField("DEBUG").getBoolean(null)
            } catch (_: Throwable) {
                false
            }
        }

        /** Local calendar day `yyyy-MM-dd` (same semantics as Dart vitals `_localDayKey`). */
        fun localDayKey(unixSec: Long, tz: TimeZone = TimeZone.getDefault()): String {
            val cal = Calendar.getInstance(tz)
            cal.timeInMillis = unixSec * 1000L
            return String.format(
                Locale.US,
                "%04d-%02d-%02d",
                cal.get(Calendar.YEAR),
                cal.get(Calendar.MONTH) + 1,
                cal.get(Calendar.DAY_OF_MONTH),
            )
        }

        /**
         * Local midnight unix for [unixSec]'s calendar day, then subtract [daysBefore] days.
         * DST-safe via Calendar (not raw 86400 arithmetic).
         */
        fun localDayStartUnix(
            unixSec: Long,
            daysBefore: Int = 0,
            tz: TimeZone = TimeZone.getDefault(),
        ): Long {
            val cal = Calendar.getInstance(tz)
            cal.timeInMillis = unixSec * 1000L
            cal.set(Calendar.HOUR_OF_DAY, 0)
            cal.set(Calendar.MINUTE, 0)
            cal.set(Calendar.SECOND, 0)
            cal.set(Calendar.MILLISECOND, 0)
            if (daysBefore != 0) {
                cal.add(Calendar.DAY_OF_MONTH, -daysBefore)
            }
            return cal.timeInMillis / 1000L
        }
    }

    data class SleepSession(
        val beginUnix: Long,
        val endUnix: Long,
        val wireType: Int? = null,
        val stages: List<SleepStage> = emptyList(),
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "beginUnix" to beginUnix,
            "endUnix" to endUnix,
            "wireType" to wireType,
            "stages" to stages.map { it.toMap() },
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
     * FitnessTotals day row (`0x07:0x03`).
     *
     * Field map from `capture:owner-2026-08-07-post-day-reset` +
     * `capture:owner-2026-08-08-swim` (steps/calories + day-anchor locked;
     * wire `0x07` is **not** watch exercise minutes — retained for diagnostics only).
     */
    data class FitnessTotalsDay(
        val dayKey: String,
        val dayStartUnix: Long,
        val calories: Int,
        val steps: Int,
        /**
         * Raw wire `0x07` u32. **Not** Home workout-time: swim-day cross-check
         * (watch 58m vs wire 5064) rejected exercise-minute semantics.
         */
        val exerciseDurationSec: Int,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "dayKey" to dayKey,
            "dayStartUnix" to dayStartUnix,
            "calories" to calories,
            "steps" to steps,
            "exerciseDurationSec" to exerciseDurationSec,
        )
    }

    data class FitnessTotalsParse(
        val days: List<FitnessTotalsDay>,
        val unknownTags: Int,
    )

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
     * @return status + sleepSessions + dailyHrSamples (always empty) + fitnessTotals +
     * completedContainers + sleepEnrich + flags
     *
     * [skipAutoHrSoft] is ignored — Sync never soft-arms auto-HR (kept for channel compat).
     */
    fun sync(
        startUnix: Long,
        endUnix: Long,
        skipTruSleepSoft: Boolean = false,
        @Suppress("UNUSED_PARAMETER") skipAutoHrSoft: Boolean = false,
    ): Map<String, Any?> {
        val start = startUnix.coerceAtLeast(0)
        val end = endUnix.coerceAtLeast(start)
        Log.i(TAG, "activity-sync start window=[$start,$end]")

        val completed = mutableListOf<String>()
        val sleepSessions = ArrayList<Map<String, Any?>>()
        val hrSamples = ArrayList<Map<String, Any?>>()
        var enableSkipped = false
        var unknownTlvCount = 0

        // Soft-enable TruSleep only. Auto-HR is Enable-path only (not Sync).
        if (!skipTruSleepSoft) {
            when (requestEnable(CMD_TRUSLEEP_ENABLE)) {
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
            // Capture FitnessTotals when link still up — day KPIs independent of sleepCount.
            return attemptFitnessTotalsAndFinalize(
                startUnix = start,
                endUnix = end,
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
                return attemptFitnessTotalsAndFinalize(
                    startUnix = start,
                    endUnix = end,
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
        val tz = TimeZone.getDefault()
        val fmt = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm z", Locale.US)
        fmt.timeZone = tz
        for (s in aggregated) {
            val beginLabel = fmt.format(java.util.Date(s.beginUnix * 1000L))
            val endLabel = fmt.format(java.util.Date(s.endUnix * 1000L))
            Log.i(
                TAG,
                "activity-sync sleep begin=${s.beginUnix} end=${s.endUnix} " +
                    "durMin=${(s.endUnix - s.beginUnix) / 60} " +
                    "stages=${s.stages.size} wire0=${s.wireType} " +
                    "local=$beginLabel → $endLabel",
            )
        }
        logSleepStageDebugDump(aggregated, fmt)

        // Continuous / daily HR stripped from activity Sync — no stepCount HR pull.
        Log.i(TAG, "activity-sync skip daily_hr pull (continuous HR stripped)")

        return attemptFitnessTotalsAndFinalize(
            startUnix = start,
            endUnix = end,
            status = "ok", // recomputed below from mergeable
            message = if (enableSkipped) "enable_skipped" else null,
            sleep = sleepSessions,
            hr = hrSamples,
            completed = completed,
            enableSkipped = enableSkipped,
            unknownTlvCount = unknownTlvCount,
            fetchBatteryAfter = true,
            recomputeStatusFromMergeable = true,
        )
    }

    /**
     * Shared exit: exchange + parse FitnessTotals, then build the activity result map.
     * Always attempts the idle handoff when connected; completion bit is optional.
     *
     * Production logs: tag+len histogram + day/row counts only (no decoded kcal/steps).
     * Debug builds additionally log leaf scalar candidates for owner cross-check.
     */
    private fun attemptFitnessTotalsAndFinalize(
        startUnix: Long,
        endUnix: Long,
        status: String,
        message: String?,
        sleep: List<Map<String, Any?>>,
        hr: List<Map<String, Any?>>,
        completed: MutableList<String>,
        enableSkipped: Boolean,
        unknownTlvCount: Int = 0,
        fetchBatteryAfter: Boolean = false,
        recomputeStatusFromMergeable: Boolean = false,
    ): Map<String, Any?> {
        val totals = attemptFitnessTotals(startUnix, endUnix)
        if (totals.isNotEmpty()) {
            completed.add("fitness_totals")
        }
        if (fetchBatteryAfter) {
            fetchBattery?.invoke()
        }
        val sleepEnrich = attemptSleepFileDownload(sleep, startUnix, endUnix)
        if (unknownTlvCount > 0) {
            Log.i(TAG, "activity-sync unknownTlvCount=$unknownTlvCount")
        }
        val resolvedStatus = if (recomputeStatusFromMergeable) {
            val hasFileIntervals = sleepEnrich.any { row ->
                (row["stateIntervals"] as? List<*>)?.isNotEmpty() == true
            }
            val hasMergeable =
                sleep.isNotEmpty() ||
                    hr.isNotEmpty() ||
                    totals.isNotEmpty() ||
                    hasFileIntervals
            if (hasMergeable) "ok" else "empty"
        } else {
            status
        }
        val resolvedMessage = if (recomputeStatusFromMergeable) {
            if (enableSkipped) "enable_skipped" else null
        } else {
            message
        }
        Log.i(
            TAG,
            "activity-sync done status=$resolvedStatus sleep=${sleep.size} " +
                "hrSamples=${hr.size} fitnessTotalsDays=${totals.size} " +
                "sleepEnrich=${sleepEnrich.size} completed=$completed " +
                "enableSkipped=$enableSkipped",
        )
        return resultMap(
            status = resolvedStatus,
            message = resolvedMessage,
            sleep = sleep,
            hr = hr,
            fitnessTotals = totals,
            completed = completed,
            enableSkipped = enableSkipped,
            sleepEnrich = sleepEnrich,
        )
    }

    /**
     * Non-blocking TruSleep FileDownload. Never clears [sleep] on failure.
     * Downloads `sleep_state.bin` only (this cut); emits enrich even when
     * message-path sleep is empty if intervals are present.
     */
    private fun attemptSleepFileDownload(
        sleep: List<Map<String, Any?>>,
        windowStartUnix: Long,
        windowEndUnix: Long,
    ): List<Map<String, Any?>> {
        return try {
            // Prefer activity Sync window — message min(begin) must not starve files.
            val startUnix = windowStartUnix.toInt().coerceAtLeast(0)
            val endUnix = windowEndUnix.toInt().coerceAtLeast(startUnix)
            val outcome = sleepFileDownloadProbe?.invoke()
                ?: (sleepFileDownload?.invoke() ?: HuaweiFileDownload(
                    exchangeEncrypted = exchangeEncrypted,
                    isConnected = isConnected,
                    liveDownloadEnabled = false,
                )).downloadSleepFiles(
                    preferNewSync = true,
                    startUnix = startUnix,
                    endUnix = endUnix,
                )
            Log.i(
                TAG,
                "activity-sync file-download status=${outcome.status} " +
                    "svc=0x${outcome.serviceId.toString(16)} " +
                    "files=${outcome.files.size} intervals=${outcome.stateIntervals.size} " +
                    "reason=${outcome.reason}",
            )
            if (outcome.status != "present") {
                return emptyList()
            }
            val refs = outcome.files.map { it.toMap() }
            val intervals = outcome.stateIntervals
            if (intervals.isEmpty()) {
                // Present files but no SoT intervals — attach refs onto messages only.
                if (sleep.isEmpty()) return emptyList()
                return sleep.map { session ->
                    buildMap {
                        put("beginUnix", session["beginUnix"])
                        put("endUnix", session["endUnix"])
                        put("wireType", session["wireType"])
                        put("present", true)
                        put("refs", refs)
                    }
                }
            }
            // One enrich row per ≤3m gap-merged chain (avoid mega-span migrate).
            val chains = gapMergeFileIntervals(intervals)
            val intervalMaps = intervals.map { it.toMap() }
            chains.mapIndexed { index, chain ->
                buildMap {
                    put("beginUnix", chain.beginUnix)
                    put("endUnix", chain.endUnix)
                    put("present", true)
                    put("refs", refs)
                    // Attach full interval list once (first row) for Flutter SoT build.
                    if (index == 0) put("stateIntervals", intervalMaps)
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "activity-sync file-download fail-closed: ${t.message}")
            emptyList()
        }
    }

    /** Contiguous file-interval chains with gap ≤ [FILE_INTERVAL_MERGE_GAP_SEC]. */
    private fun gapMergeFileIntervals(
        intervals: List<HuaweiFileDownload.StateInterval>,
    ): List<HuaweiFileDownload.StateInterval> {
        if (intervals.isEmpty()) return emptyList()
        val sorted = intervals.sortedBy { it.beginUnix }
        val chains = ArrayList<HuaweiFileDownload.StateInterval>()
        var begin = sorted.first().beginUnix
        var end = sorted.first().endUnix
        for (i in 1 until sorted.size) {
            val next = sorted[i]
            if (next.beginUnix - end > FILE_INTERVAL_MERGE_GAP_SEC) {
                chains.add(HuaweiFileDownload.StateInterval(begin, end))
                begin = next.beginUnix
                end = next.endUnix
            } else {
                if (next.endUnix > end) end = next.endUnix
                if (next.beginUnix < begin) begin = next.beginUnix
            }
        }
        chains.add(HuaweiFileDownload.StateInterval(begin, end))
        return chains
    }

    /**
     * Exchange FitnessTotals when the link is usable. Returns parsed day rows, or empty
     * on disconnect / timeout / unusable frame (soft-omit completed bit).
     */
    private fun attemptFitnessTotals(
        startUnix: Long,
        endUnix: Long,
    ): List<Map<String, Any?>> {
        if (!isConnected()) {
            Log.i(TAG, "activity-sync fitnessTotals skipped (disconnected)")
            return emptyList()
        }
        Log.i(
            TAG,
            "activity-sync fitnessTotals request window=[$startUnix,$endUnix] " +
                "(re-fetch day rollup even if workouts/sleep already synced)",
        )
        val frame = exchangeEncrypted(
            buildWindowRequest(CMD_FITNESS_TOTALS, startUnix, endUnix),
            SVC,
            CMD_FITNESS_TOTALS,
            TIMEOUT_MS,
        )
        if (frame == null) {
            Log.w(TAG, "activity-sync fitnessTotals timeout/null")
            return emptyList()
        }
        val hist = tlvTagLenHistogram(frame.tlvs)
        Log.i(
            TAG,
            "activity-sync fitnessTotals frame ok " +
                "svc=0x${SVC.toString(16)} cmd=0x${CMD_FITNESS_TOTALS.toString(16)} " +
                "topTlvCount=${frame.tlvs.size} hist=[$hist]",
        )
        if (shouldLogDebugScalars()) {
            val scalars = leafScalarCandidates(frame.tlvs)
            if (scalars.isNotEmpty()) {
                Log.d(
                    TAG,
                    "activity-sync fitnessTotals debugScalars " +
                        "(owner cross-check vs watch day; provisional map) $scalars",
                )
            }
        }
        return try {
            val parsed = parseFitnessTotals(frame, endUnix = endUnix)
            Log.i(
                TAG,
                "activity-sync fitnessTotals parsedDays=${parsed.days.size} " +
                    "unknownTags=${parsed.unknownTags}",
            )
            parsed.days.map { it.toMap() }
        } catch (t: Throwable) {
            Log.w(TAG, "activity-sync fitnessTotals parse failed: ${t.message}")
            emptyList()
        }
    }

    /**
     * Parse FitnessTotals day slots under `0x81` → repeated `0x83`.
     *
     * Owned leaves (`capture:owner-2026-08-07-post-day-reset` +
     * `capture:owner-2026-08-08-swim`):
     * - `0x05` u32 steps, `0x06` u16 calories kcal
     * - `0x07` u32 retained as [FitnessTotalsDay.exerciseDurationSec] but **not**
     *   watch exercise minutes (Home uses workout-sum for workout time)
     *
     * Day-anchor (locked): inner `0x04` slot tag → days before local today at
     * [endUnix]; `0x04=1` is today (`daysBefore = tag - 1`). Tag `0` skipped
     * (padding in both owner captures).
     */
    fun parseFitnessTotals(
        frame: HuaweiFraming.Frame,
        endUnix: Long,
        tz: TimeZone = TimeZone.getDefault(),
    ): FitnessTotalsParse {
        val container = frame.tlvs.firstOrNull { it.tag == 0x81 }?.value
            ?: return FitnessTotalsParse(emptyList(), 0)
        val tlvs = HuaweiFraming.decodeTlvs(container)
        val slotValues = ArrayList<ByteArray>()
        var unknown = 0
        for (tlv in tlvs) {
            when (tlv.tag) {
                0x83 -> slotValues.add(tlv.value)
                0x02, 0x09 -> Unit // header / trailer
                else -> unknown++
            }
        }
        if (slotValues.isEmpty()) {
            return FitnessTotalsParse(emptyList(), unknown)
        }
        val days = ArrayList<FitnessTotalsDay>(slotValues.size)
        for (value in slotValues) {
            val leaves = parseFitnessTotalsSlotLeaves(value)
            val daysBefore = daysBeforeForSlotTag(leaves.slotTag) ?: continue
            val dayStart = localDayStartUnix(endUnix, daysBefore = daysBefore, tz = tz)
            val dayKey = localDayKey(dayStart, tz)
            days.add(
                FitnessTotalsDay(
                    dayKey = dayKey,
                    dayStartUnix = dayStart,
                    calories = leaves.calories,
                    steps = leaves.steps,
                    exerciseDurationSec = leaves.wire07,
                ),
            )
        }
        return FitnessTotalsParse(days, unknown)
    }

    /**
     * `0x04=1` → today; `0x04=N` (N≥1) → N−1 local days before [endUnix].
     * Tag `0` is padding — omit.
     */
    fun daysBeforeForSlotTag(slotTag: Int): Int? =
        if (slotTag <= 0) null else slotTag - 1

    private data class FitnessTotalsSlotLeaves(
        val slotTag: Int,
        val steps: Int,
        val calories: Int,
        val wire07: Int,
    )

    private fun parseFitnessTotalsSlotLeaves(value: ByteArray): FitnessTotalsSlotLeaves {
        val inner = HuaweiFraming.decodeTlvs(value)
        var slotTag = 0
        var steps = 0
        var calories = 0
        var wire07 = 0
        for (child in inner) {
            when (child.tag) {
                0x04 -> if (child.value.isNotEmpty()) {
                    slotTag = child.value[0].toInt() and 0xFF
                }
                0x05 -> if (child.value.size >= 4) steps = u32(child.value).toInt()
                0x06 -> if (child.value.size >= 2) calories = u16(child.value)
                0x07 -> if (child.value.size >= 4) {
                    wire07 = u32(child.value).toInt().coerceAtLeast(0)
                }
                0x08, 0x0B -> Unit // present; meaning unknown
                else -> Unit
            }
        }
        return FitnessTotalsSlotLeaves(
            slotTag = slotTag,
            steps = steps.coerceAtLeast(0),
            calories = calories.coerceAtLeast(0),
            wire07 = wire07,
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

    /**
     * Diagnostic-only daily interval HR/SpO₂ presence pull (`0x0A`/`0x0B`).
     * Product [sync] still skips daily_hr. Returns tag+len histogram — never series.
     *
     * When [sleepIntervals] is non-empty, also returns last-night overlap counts
     * (minutes only; no BPM / SpO₂ values).
     */
    fun probeDailyHrIntervalProxy(
        startUnix: Long,
        endUnix: Long,
        sleepIntervals: List<Pair<Long, Long>> = emptyList(),
    ): Map<String, Any?> {
        if (!isConnected()) {
            return mapOf("status" to "skipped", "reason" to "disconnected", "class" to "interval-proxy")
        }
        val stepCountFrame = exchangeEncrypted(
            buildWindowRequest(CMD_STEP_COUNT, startUnix, endUnix),
            SVC,
            CMD_STEP_COUNT,
            TIMEOUT_MS,
        )
        if (stepCountFrame == null) {
            Log.i(TAG, "physio-probe path2 stepCount timeout")
            return mapOf(
                "status" to "absent",
                "reason" to "step_count_timeout",
                "class" to "interval-proxy",
            )
        }
        val indices = parseCountIndices(stepCountFrame)
        val histograms = ArrayList<String>()
        var hrBitmapDays = 0
        var sampleCount = 0
        val hrUnix = HashSet<Long>()
        val spo2HintUnix = HashSet<Long>()
        for (index in indices) {
            val dataFrame = exchangeEncrypted(
                buildIndexRequest(CMD_STEP_DATA, index),
                SVC,
                CMD_STEP_DATA,
                TIMEOUT_MS,
            ) ?: continue
            histograms.add(tlvTagLenHistogram(dataFrame.tlvs))
            val parsed = parseStepDataHr(dataFrame)
            if (parsed.hrBitmapPresent) hrBitmapDays++
            sampleCount += parsed.samples.size
            hrUnix.addAll(parsed.hrUnix)
            spo2HintUnix.addAll(parsed.spo2HintUnix)
            // Do not retain BPM series in the result map.
        }
        val lastNight = lastNightIntervals(sleepIntervals, endUnix)
        val lastNightSleepMin = intervalMinutes(lastNight)
        val lastNightHrMin = countUnixInIntervals(hrUnix, lastNight)
        val lastNightSpo2HintMin = countUnixInIntervals(spo2HintUnix, lastNight)
        val coveragePct = if (lastNightSleepMin > 0) {
            (lastNightHrMin * 100) / lastNightSleepMin
        } else {
            0
        }
        Log.i(
            TAG,
            "physio-probe path2 indices=${indices.size} hrBitmapDays=$hrBitmapDays " +
                "sampleCount=$sampleCount lastNightSleepMin=$lastNightSleepMin " +
                "lastNightHrMin=$lastNightHrMin lastNightSpo2HintMin=$lastNightSpo2HintMin " +
                "hrCoveragePct=$coveragePct (values redacted)",
        )
        return buildMap {
            put("status", if (hrBitmapDays > 0 || histograms.isNotEmpty()) "present" else "absent")
            put("class", "interval-proxy")
            put("indexCount", indices.size)
            put("hrBitmapDays", hrBitmapDays)
            put("sampleCount", sampleCount)
            put("tagLenHistograms", histograms.take(8))
            put("reason", if (hrBitmapDays > 0) "hr_bitmap_present" else "no_hr_bitmap")
            put("sleepIntervalCount", sleepIntervals.size)
            put("lastNightIntervalCount", lastNight.size)
            put("lastNightSleepMinutes", lastNightSleepMin)
            put("lastNightHrMinutes", lastNightHrMin)
            put("lastNightSpo2HintMinutes", lastNightSpo2HintMin)
            put("lastNightHrCoveragePct", coveragePct)
            put(
                "spo2Hint",
                "extra_byte_after_hr_not_decoded",
            )
        }
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
        /** Debug-only raw `0x05` payload hex (never sent on channel). */
        val raw05Hex: String? = null,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "timestampUnix" to timestampUnix,
            "durationMin" to durationMin,
            "wireType" to wireType,
        )
    }

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
        var raw05Hex: String? = null
        for (child in inner) {
            when (child.tag) {
                0x04 -> if (child.value.isNotEmpty()) type = u8(child.value)
                0x05 -> if (child.value.size >= 4) {
                    raw05Hex = child.value.joinToString("") { b ->
                        "%02X".format(b.toInt() and 0xFF)
                    }
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
        // Owner debug: keep last raw 0x05 hex on the stage via side channel log only
        // when dumping recent sessions (see logSleepStageDebugDump).
        return SleepStage(timestamp, durationMin, type, raw05Hex)
    }

    /**
     * Owner debug dump: per-stage type/ts/dur (+ raw 0x05 hex) for sessions
     * ending in the last 48h, plus a global wireType histogram. Privacy: no PPG.
     */
    private fun logSleepStageDebugDump(
        sessions: List<SleepSession>,
        fmt: java.text.SimpleDateFormat,
    ) {
        val nowSec = System.currentTimeMillis() / 1000L
        val cutoff = nowSec - 48 * 3600L
        val typeHist = linkedMapOf<Int, Int>()
        var totalStages = 0
        for (session in sessions) {
            for (stage in session.stages) {
                totalStages++
                val t = stage.wireType ?: -1
                typeHist[t] = (typeHist[t] ?: 0) + 1
            }
        }
        val histStr = typeHist.entries
            .sortedBy { it.key }
            .joinToString(",") { "t=${it.key}:${it.value}" }
        Log.i(TAG, "activity-sync sleep-type-hist n=$totalStages [$histStr]")

        val recent = sessions.filter { it.endUnix >= cutoff }
        Log.i(
            TAG,
            "activity-sync sleep-stage-dump sessions=${recent.size} " +
                "(ending last 48h; force-pull debug)",
        )
        for (session in recent) {
            Log.i(
                TAG,
                "activity-sync sleep-stage-session begin=${session.beginUnix} " +
                    "end=${session.endUnix} stages=${session.stages.size}",
            )
            session.stages.forEachIndexed { i, stage ->
                val local = fmt.format(java.util.Date(stage.timestampUnix * 1000L))
                Log.i(
                    TAG,
                    "activity-sync sleep-stage i=$i type=${stage.wireType} " +
                        "ts=${stage.timestampUnix} durMin=${stage.durationMin} " +
                        "local=$local raw05=${stage.raw05Hex ?: "-"}",
                )
            }
        }
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
        val bucket = ArrayList<SleepStage>()
        bucket.add(ordered[0])
        for (i in 1 until ordered.size) {
            val s = ordered[i]
            val gap = s.timestampUnix - end
            if (gap > gapSplitSec) {
                if (end > begin) out.add(SleepSession(begin, end, type, bucket.toList()))
                begin = s.timestampUnix
                end = stageEndUnix(s)
                type = s.wireType
                bucket.clear()
                bucket.add(s)
            } else {
                end = maxOf(end, stageEndUnix(s))
                bucket.add(s)
            }
        }
        if (end > begin) out.add(SleepSession(begin, end, type, bucket.toList()))
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
        val hrUnix: List<Long> = emptyList(),
        val spo2HintUnix: List<Long> = emptyList(),
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
        val hrUnix = ArrayList<Long>()
        val spo2HintUnix = ArrayList<Long>()
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
                    if (p != null && p.isNotEmpty() && dayStart > 0L) {
                        val ts = dayStart + minute * 60L
                        val bitmap = u8(p)
                        if ((bitmap and BITMAP_HR) != 0) {
                            sawHrBitmap = true
                            val bpm = extractHrBpm(p)
                            if (bpm != null) {
                                hrUnix.add(ts)
                                samples.add(
                                    DailyHrSample(
                                        timestampUnix = ts,
                                        bpm = bpm,
                                    ),
                                )
                            }
                        }
                        if (bytesAfterHr(p) >= 1) {
                            spo2HintUnix.add(ts)
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
            hrUnix = hrUnix,
            spo2HintUnix = spo2HintUnix,
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

    /** Bytes remaining after bitmap-led HR (and lower 2B fields). Not a decoded SpO₂ value. */
    fun bytesAfterHr(payload: ByteArray): Int {
        if (payload.isEmpty()) return 0
        val bitmap = u8(payload)
        var offset = 1
        var bit = 0x01
        while (bit < BITMAP_HR) {
            if ((bitmap and bit) != 0) {
                offset += 2
            }
            bit = bit shl 1
        }
        if ((bitmap and BITMAP_HR) != 0) {
            offset += 1
        }
        return (payload.size - offset).coerceAtLeast(0)
    }

    private fun resultMap(
        status: String,
        message: String?,
        sleep: List<Map<String, Any?>>,
        hr: List<Map<String, Any?>>,
        fitnessTotals: List<Map<String, Any?>>,
        completed: List<String>,
        enableSkipped: Boolean,
        sleepEnrich: List<Map<String, Any?>> = emptyList(),
    ): Map<String, Any?> = buildMap {
        put("status", status)
        if (message != null) put("message", message)
        put("sleepSessions", sleep)
        put("dailyHrSamples", hr)
        put("fitnessTotals", fitnessTotals)
        put("completedContainers", completed)
        put("enableSkipped", enableSkipped)
        put("sleepEnrich", sleepEnrich)
        val clock = watchClockSnapshot?.invoke()
        if (clock != null && clock.isNotEmpty()) put("watchClock", clock)
    }
}
