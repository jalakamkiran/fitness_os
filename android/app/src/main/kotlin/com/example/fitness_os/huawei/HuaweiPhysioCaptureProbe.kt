package com.example.fitness_os.huawei

import android.util.Log

/**
 * Post-Sync diagnostic orchestrator for overnight physio capture (dict → sleep_data →
 * optional path-2). Privacy-safe maps only — never feeds Flutter TruSleep SoT.
 *
 * Primary invent (HarmonyOS 5+ TruSleep stages/summaries): SEQUENCE_DATA `0x16` +
 * dict class `700013` on basename `sequence_data`.
 *
 * Legacy invents (Aug 2026 POC — wrong wire shape; kept for ABSENT regression):
 * UTF-8 `sequence_data/SLEEP_DETAILS` / `SLEEP_DETAILS` with type `0x00`/`0x0f`.
 */
class HuaweiPhysioCaptureProbe(
    private val fileDownload: () -> HuaweiFileDownload,
    /**
     * Controlled FeatureUpload listen window. Returns privacy-safe map when a
     * sequence/SLEEP_DETAILS-class push is observed; null on timeout.
     */
    private val listenFeatureUploadSequence: (timeoutMs: Long) -> Map<String, Any?>? = { null },
    /**
     * Optional path-2 diagnostic interval pull (tag+len + sleep-window overlap counts).
     */
    private val pullIntervalProxy: (
        (startUnix: Int, endUnix: Int, sleepIntervals: List<Pair<Long, Long>>) -> Map<String, Any?>
    )? = null,
) {
    companion object {
        private const val TAG = "FOS_HUAWEI"
        /** Invented filetype probe byte — GT5 may ignore / size-0; one attempt each. */
        const val DICT_FILETYPE_PROBE: Byte = 0x00
        const val FU_LISTEN_TIMEOUT_MS = 8_000L

        data class DictCandidate(
            val id: String,
            val route: String,
            val transport: String,
        )

        /** Legacy filename invents — not the SEQUENCE_DATA+dictId path. */
        val LEGACY_DICT_FD_CANDIDATES = listOf(
            DictCandidate(
                id = "cand-fd-seq-path",
                route = "sequence_data/SLEEP_DETAILS",
                transport = "FD-0x2c-pull",
            ),
            DictCandidate(
                id = "cand-fd-sleep-details",
                route = "SLEEP_DETAILS",
                transport = "FD-0x2c-pull",
            ),
        )

        @Deprecated("Use LEGACY_DICT_FD_CANDIDATES; primary path is SEQUENCE_DATA+dictId")
        val DICT_FD_CANDIDATES = LEGACY_DICT_FD_CANDIDATES
    }

    data class Options(
        val includeDict: Boolean = true,
        val includeSleepData: Boolean = true,
        val includePath2Intervals: Boolean = false,
        /** Re-run Aug-2026 wrong invents after the SEQUENCE_DATA primary. */
        val includeLegacyDictInvents: Boolean = true,
        val startUnix: Int = 0,
        val endUnix: Int = (System.currentTimeMillis() / 1000L).toInt(),
    )

    fun run(options: Options): Map<String, Any?> {
        val dictAttempts = ArrayList<Map<String, Any?>>()
        val overnightKeys = linkedSetOf<String>()
        var unmetOvernight = true

        if (options.includeDict) {
            val dl = fileDownload()

            // Primary: SEQUENCE_DATA + SLEEP_DETAILS dict class (HarmonyOS 5+ path).
            val primary = dl.downloadSleepDetailsSequenceObserve(
                startUnix = options.startUnix,
                endUnix = options.endUnix,
            )
            dictAttempts.add(
                buildMap {
                    put("candidateId", "cand-fd-seq-dict")
                    put("route", HuaweiFileDownload.FILE_SEQUENCE_DATA)
                    put("fileType", HuaweiFileDownload.TYPE_SEQUENCE_DATA.toInt() and 0xFF)
                    put("dictId", HuaweiFileDownload.DICT_SLEEP_DETAILS_CLASS)
                    put("transport", "FD-0x2c-sequence-dict")
                    putAll(primary.toMap())
                },
            )
            Log.i(
                TAG,
                "physio-probe dict candidate=cand-fd-seq-dict " +
                    "fileType=${HuaweiFileDownload.TYPE_SEQUENCE_DATA.toInt() and 0xFF} " +
                    "dictId=${HuaweiFileDownload.DICT_SLEEP_DETAILS_CLASS} " +
                    "status=${primary.status} len=${primary.len} " +
                    "overnightKeys=${primary.overnightSummaryKeys}",
            )
            overnightKeys.addAll(primary.overnightSummaryKeys)
            unmetOvernight = overnightKeys.isEmpty()

            // Legacy invents only if primary did not already close overnight summaries.
            if (options.includeLegacyDictInvents && unmetOvernight) {
                val fdTypePasses = listOf(
                    DICT_FILETYPE_PROBE to "",
                    HuaweiFileDownload.TYPE_SLEEP_DATA to "-type0f",
                )
                for (cand in LEGACY_DICT_FD_CANDIDATES) {
                    for ((fileType, idSuffix) in fdTypePasses) {
                        val candidateId = cand.id + idSuffix
                        val observed = dl.downloadDiagnosticNamedFileObserve(
                            fileName = cand.route,
                            fileType = fileType,
                            shortId = candidateId,
                            startUnix = options.startUnix,
                            endUnix = options.endUnix,
                        )
                        val row = buildMap<String, Any?> {
                            put("candidateId", candidateId)
                            put("route", cand.route)
                            put("fileType", fileType.toInt() and 0xFF)
                            put("transport", cand.transport)
                            putAll(observed.toMap())
                        }
                        dictAttempts.add(row)
                        Log.i(
                            TAG,
                            "physio-probe dict candidate=$candidateId " +
                                "fileType=${fileType.toInt() and 0xFF} " +
                                "status=${observed.status} len=${observed.len} " +
                                "overnightKeys=${observed.overnightSummaryKeys}",
                        )
                        overnightKeys.addAll(observed.overnightSummaryKeys)
                    }
                }
                unmetOvernight = overnightKeys.isEmpty()
            }

            val fu = listenFeatureUploadSequence(FU_LISTEN_TIMEOUT_MS)
            if (fu != null) {
                dictAttempts.add(
                    buildMap {
                        put("candidateId", "cand-fu-sequence-listen")
                        put("route", fu["route"] ?: "FU-0x28")
                        put("transport", "FU-0x28-receive")
                        putAll(fu)
                    },
                )
                @Suppress("UNCHECKED_CAST")
                val keys = fu["overnightSummaryKeys"] as? List<String>
                if (keys != null) overnightKeys.addAll(keys)
            } else {
                dictAttempts.add(
                    mapOf(
                        "candidateId" to "cand-fu-sequence-listen",
                        "route" to "FeatureUpload-listen",
                        "transport" to "FU-0x28-receive",
                        "status" to "absent",
                        "len" to 0,
                        "reason" to "no_sequence_push",
                        "redactedKeys" to emptyList<String>(),
                        "overnightSummaryKeys" to emptyList<String>(),
                    ),
                )
                Log.i(TAG, "physio-probe dict candidate=cand-fu-sequence-listen status=absent")
            }

            unmetOvernight = overnightKeys.isEmpty()
        }

        var sleepData: Map<String, Any?>? = null
        if (options.includeSleepData && unmetOvernight) {
            val observed = fileDownload().downloadSleepDataStructureObserve(
                startUnix = options.startUnix,
                endUnix = options.endUnix,
            )
            sleepData = observed.toMap()
            overnightKeys.addAll(observed.overnightSummaryKeys)
            unmetOvernight = overnightKeys.isEmpty()
            Log.i(
                TAG,
                "physio-probe sleep_data status=${observed.status} len=${observed.len} " +
                    "overnightKeys=${observed.overnightSummaryKeys} " +
                    observed.privacyInventoryLog(),
            )
        } else if (options.includeSleepData) {
            sleepData = mapOf(
                "status" to "skipped",
                "id" to "sleep_data",
                "reason" to "overnight_summaries_already_present",
            )
        }

        var path2: Map<String, Any?>? = null
        if (options.includePath2Intervals) {
            val sleepOutcome = fileDownload().downloadSleepFiles(
                preferNewSync = true,
                startUnix = options.startUnix,
                endUnix = options.endUnix,
            )
            val sleepIntervals = sleepOutcome.stateIntervals.map {
                it.beginUnix.toLong() to it.endUnix.toLong()
            }
            Log.i(
                TAG,
                "physio-probe sleep_state status=${sleepOutcome.status} " +
                    "intervals=${sleepIntervals.size} " +
                    "sleepMin=${HuaweiFitnessDataSync.intervalMinutes(sleepIntervals)}",
            )
            val pull = pullIntervalProxy
            path2 = if (pull != null) {
                pull(options.startUnix, options.endUnix, sleepIntervals)
            } else {
                mapOf(
                    "status" to "skipped",
                    "reason" to "path2_not_wired",
                    "sleepIntervalCount" to sleepIntervals.size,
                )
            }
            Log.i(
                TAG,
                "physio-probe path2 status=${path2["status"]} " +
                    "lastNightSleepMin=${path2["lastNightSleepMinutes"]} " +
                    "lastNightHrMin=${path2["lastNightHrMinutes"]} " +
                    "lastNightSpo2HintMin=${path2["lastNightSpo2HintMinutes"]} " +
                    "hrCoveragePct=${path2["lastNightHrCoveragePct"]}",
            )
        }

        return buildMap {
            put("status", "ok")
            put("dictAttempts", dictAttempts)
            put("overnightSummaryKeys", overnightKeys.toList())
            put("unmetOvernightSummary", overnightKeys.isEmpty())
            if (sleepData != null) put("sleepData", sleepData)
            if (path2 != null) put("path2Intervals", path2)
            // Explicit: this map must never be merged into product sleep SoT.
            put("feedsProductSleepSot", false)
        }
    }
}
