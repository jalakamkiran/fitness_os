package com.example.fitness_os.huawei

import android.util.Log

/**
 * Post-Sync diagnostic orchestrator for overnight physio capture (dict → sleep_data →
 * optional path-2). Privacy-safe maps only — never feeds Flutter TruSleep SoT.
 *
 * Inventory candidates (U1): cand-fd-seq-path, cand-fd-sleep-details, cand-fu-sequence-listen.
 */
class HuaweiPhysioCaptureProbe(
    private val fileDownload: () -> HuaweiFileDownload,
    /**
     * Controlled FeatureUpload listen window. Returns privacy-safe map when a
     * sequence/SLEEP_DETAILS-class push is observed; null on timeout.
     */
    private val listenFeatureUploadSequence: (timeoutMs: Long) -> Map<String, Any?>? = { null },
    /**
     * Optional path-2 diagnostic interval pull (tag+len histogram only).
     */
    private val pullIntervalProxy: ((startUnix: Int, endUnix: Int) -> Map<String, Any?>)? = null,
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

        val DICT_FD_CANDIDATES = listOf(
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
    }

    data class Options(
        val includeDict: Boolean = true,
        val includeSleepData: Boolean = true,
        val includePath2Intervals: Boolean = false,
        val startUnix: Int = 0,
        val endUnix: Int = (System.currentTimeMillis() / 1000L).toInt(),
    )

    fun run(options: Options): Map<String, Any?> {
        val dictAttempts = ArrayList<Map<String, Any?>>()
        val overnightKeys = linkedSetOf<String>()
        var unmetOvernight = true

        if (options.includeDict) {
            val dl = fileDownload()
            for (cand in DICT_FD_CANDIDATES) {
                val observed = dl.downloadDiagnosticNamedFileObserve(
                    fileName = cand.route,
                    fileType = DICT_FILETYPE_PROBE,
                    shortId = cand.id,
                    startUnix = options.startUnix,
                    endUnix = options.endUnix,
                )
                val row = buildMap<String, Any?> {
                    put("candidateId", cand.id)
                    put("route", cand.route)
                    put("transport", cand.transport)
                    putAll(observed.toMap())
                }
                dictAttempts.add(row)
                Log.i(
                    TAG,
                    "physio-probe dict candidate=${cand.id} status=${observed.status} " +
                        "len=${observed.len} overnightKeys=${observed.overnightSummaryKeys}",
                )
                overnightKeys.addAll(observed.overnightSummaryKeys)
                // Typed overnight-summary present requires overnightSummaryKeys non-empty.
                // Huawhoop name equality alone (redactedKeys) is not enough.
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
                    "overnightKeys=${observed.overnightSummaryKeys}",
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
            val pull = pullIntervalProxy
            path2 = if (pull != null) {
                pull(options.startUnix, options.endUnix)
            } else {
                mapOf(
                    "status" to "skipped",
                    "reason" to "path2_not_wired",
                )
            }
            Log.i(TAG, "physio-probe path2 status=${path2["status"]}")
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
