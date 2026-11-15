package com.example.fitness_os.observability

import io.sentry.Breadcrumb
import io.sentry.Hint
import io.sentry.Sentry
import io.sentry.SentryLevel
import io.sentry.protocol.Message

/**
 * Privacy-safe Sentry breadcrumbs for Huawei LPv2 sync operations.
 *
 * Never logs health data values (HR series, GPS coords, raw sample bodies).
 * Only codes, counts, TLV tag IDs, lengths, and error context for debugging.
 */
object HuaweiSyncBreadcrumbs {
    private val isEnabled: Boolean
        get() = Sentry.isEnabled()

    /**
     * Record Bluetooth connection attempt.
     */
    fun connectionAttempt(address: String) {
        if (!isEnabled) return
        addBreadcrumb(
            message = "Huawei BT connection attempt",
            category = "huawei.connection",
            level = SentryLevel.INFO,
            data = mapOf("address" to redactMac(address))
        )
    }

    /**
     * Record successful Bluetooth connection.
     */
    fun connectionSuccess(address: String) {
        if (!isEnabled) return
        addBreadcrumb(
            message = "Huawei BT connected",
            category = "huawei.connection",
            level = SentryLevel.INFO,
            data = mapOf("address" to redactMac(address))
        )
    }

    /**
     * Record connection failure.
     */
    fun connectionFailure(address: String, reason: String) {
        if (!isEnabled) return
        addBreadcrumb(
            message = "Huawei BT connection failed: $reason",
            category = "huawei.connection",
            level = SentryLevel.WARNING,
            data = mapOf(
                "address" to redactMac(address),
                "reason" to reason
            )
        )
    }

    /**
     * Record authentication/pairing step.
     */
    fun authStep(step: String, success: Boolean) {
        if (!isEnabled) return
        addBreadcrumb(
            message = "Huawei auth: $step",
            category = "huawei.auth",
            level = if (success) SentryLevel.INFO else SentryLevel.WARNING,
            data = mapOf(
                "step" to step,
                "success" to success
            )
        )
    }

    /**
     * Record workout sync phase (Count/Totals/Data/Pace/Swim).
     */
    fun workoutSyncPhase(
        phase: String,
        workoutNumber: Int? = null,
        pageIndex: Int? = null,
    ) {
        if (!isEnabled) return
        val data = mutableMapOf<String, Any>("phase" to phase)
        if (workoutNumber != null) data["workoutNumber"] = workoutNumber
        if (pageIndex != null) data["pageIndex"] = pageIndex
        
        addBreadcrumb(
            message = "Workout sync: $phase",
            category = "huawei.workout.sync",
            level = SentryLevel.DEBUG,
            data = data
        )
    }

    /**
     * Record workout sync command timeout.
     */
    fun workoutTimeout(
        command: String,
        workoutNumber: Int? = null,
        pageIndex: Int? = null,
    ) {
        if (!isEnabled) return
        val data = mutableMapOf<String, Any>("command" to command)
        if (workoutNumber != null) data["workoutNumber"] = workoutNumber
        if (pageIndex != null) data["pageIndex"] = pageIndex
        
        addBreadcrumb(
            message = "Workout sync timeout: $command",
            category = "huawei.workout.sync",
            level = SentryLevel.WARNING,
            data = data
        )
    }

    /**
     * Record TLV parse failure (tag and length only, never body).
     */
    fun tlvParseFailure(
        tag: Int,
        length: Int,
        context: String,
        expectedLength: Int? = null,
    ) {
        if (!isEnabled) return
        val data = mutableMapOf(
            "tag" to "0x${tag.toString(16)}",
            "length" to length,
            "context" to context
        )
        if (expectedLength != null) {
            data["expectedLength"] = expectedLength
        }
        
        addBreadcrumb(
            message = "TLV parse failure: $context",
            category = "huawei.parse",
            level = SentryLevel.WARNING,
            data = data
        )
    }

    /**
     * Record parsed workout totals metadata (counts only, no health values).
     */
    fun workoutTotalsParsed(
        workoutNumber: Int,
        type: Int,
        durationSec: Long,
        dataCount: Int,
        paceCount: Int,
        segmentsCount: Int,
    ) {
        if (!isEnabled) return
        addBreadcrumb(
            message = "Workout totals parsed: #$workoutNumber type=$type",
            category = "huawei.workout.parse",
            level = SentryLevel.DEBUG,
            data = mapOf(
                "workoutNumber" to workoutNumber,
                "type" to type,
                "durationSec" to durationSec,
                "dataCount" to dataCount,
                "paceCount" to paceCount,
                "segmentsCount" to segmentsCount
            )
        )
    }

    /**
     * Record unusual payload size (potential protocol version change).
     */
    fun unusualPayloadSize(
        context: String,
        actualSize: Int,
        expectedSize: Int,
    ) {
        if (!isEnabled) return
        addBreadcrumb(
            message = "Unusual payload size: $context",
            category = "huawei.payload",
            level = SentryLevel.WARNING,
            data = mapOf(
                "context" to context,
                "actualSize" to actualSize,
                "expectedSize" to expectedSize,
                "ratio" to String.format("%.2f", actualSize.toFloat() / expectedSize)
            )
        )
    }

    /**
     * Record unknown workout type encountered.
     */
    fun unknownWorkoutType(typeCode: Int) {
        if (!isEnabled) return
        addBreadcrumb(
            message = "Unknown workout type: $typeCode",
            category = "huawei.workout.type",
            level = SentryLevel.WARNING,
            data = mapOf("typeCode" to typeCode)
        )
    }

    /**
     * Record badminton (or other racket sport) workout parsed.
     */
    fun racketSportWorkout(
        workoutNumber: Int,
        typeCode: Int,
        durationSec: Long,
        hasHrData: Boolean,
        hasLoad: Boolean,
    ) {
        if (!isEnabled) return
        addBreadcrumb(
            message = "Racket sport workout: #$workoutNumber type=$typeCode",
            category = "huawei.workout.racket",
            level = SentryLevel.INFO,
            data = mapOf(
                "workoutNumber" to workoutNumber,
                "typeCode" to typeCode,
                "durationSec" to durationSec,
                "hasHrData" to hasHrData,
                "hasLoad" to hasLoad
            )
        )
    }

    /**
     * Capture exception with Huawei context.
     */
    fun captureException(
        throwable: Throwable,
        context: String,
        additionalData: Map<String, Any> = emptyMap(),
    ) {
        if (!isEnabled) return
        Sentry.withScope { scope ->
            scope.setContexts("huawei_context", context)
            additionalData.forEach { (key, value) ->
                scope.setExtra(key, value.toString())
            }
            Sentry.captureException(throwable)
        }
    }

    /**
     * Record fitness data sync start.
     */
    fun fitnessDataSyncStart(startUnix: Long, endUnix: Long) {
        if (!isEnabled) return
        addBreadcrumb(
            message = "Fitness data sync started",
            category = "huawei.fitness.sync",
            level = SentryLevel.INFO,
            data = mapOf(
                "startUnix" to startUnix,
                "endUnix" to endUnix,
                "windowDays" to ((endUnix - startUnix) / 86400)
            )
        )
    }

    /**
     * Record fitness data sync completion.
     */
    fun fitnessDataSyncComplete(itemCount: Int, status: String) {
        if (!isEnabled) return
        addBreadcrumb(
            message = "Fitness data sync complete: $status",
            category = "huawei.fitness.sync",
            level = if (status == "ok") SentryLevel.INFO else SentryLevel.WARNING,
            data = mapOf(
                "itemCount" to itemCount,
                "status" to status
            )
        )
    }

    /**
     * Record workout enrichment summary (after Data/Pace/Swim fetch).
     */
    fun workoutEnrichmentComplete(
        workoutNumber: Int,
        pagesRequested: Int,
        pagesFetched: Int,
        sampleFetchStatus: String,
        pointPages: Int,
        sampleCount: Int,
        samplesPersisted: Boolean,
    ) {
        if (!isEnabled) return
        addBreadcrumb(
            message = "Workout enrichment: #$workoutNumber pages=$pagesFetched/$pagesRequested samples=$sampleFetchStatus",
            category = "huawei.workout.enrichment",
            level = SentryLevel.DEBUG,
            data = mapOf(
                "workoutNumber" to workoutNumber,
                "pagesRequested" to pagesRequested,
                "pagesFetched" to pagesFetched,
                "sampleFetchStatus" to sampleFetchStatus,
                "pointPages" to pointPages,
                "sampleCount" to sampleCount,
                "samplesPersisted" to samplesPersisted
            )
        )
    }

    // Helper functions

    private fun addBreadcrumb(
        message: String,
        category: String,
        level: SentryLevel,
        data: Map<String, Any>,
    ) {
        val breadcrumb = Breadcrumb().apply {
            this.message = message
            this.category = category
            this.level = level
            data.forEach { (key, value) ->
                setData(key, value)
            }
        }
        Sentry.addBreadcrumb(breadcrumb)
    }

    /**
     * Redact MAC address for privacy (show first and last octet only).
     */
    private fun redactMac(address: String): String {
        val parts = address.split(":", "-")
        if (parts.size != 6) return "••:••:••:••:••:••"
        return "${parts[0]}:••:••:••:••:${parts[5]}"
    }
}
