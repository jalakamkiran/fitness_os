package com.example.fitness_os.observability

import android.util.Log
import io.sentry.Hint
import io.sentry.Sentry
import io.sentry.SentryEvent
import io.sentry.SentryLevel
import io.sentry.protocol.Message
import org.json.JSONArray
import org.json.JSONObject

/**
 * Raw workout payload dumping for reverse-engineering (owner explicit consent).
 *
 * Captures full TLV hex for racket sports (badminton, tennis, etc.) to identify
 * unknown fields like swing count, rally data, cadence.
 *
 * Controlled by build config: `SENTRY_RAW_WORKOUT_DUMP` property.
 * Default: on for debug, off for release.
 *
 * **Privacy**: MAC addresses still redacted. Health data included by owner request
 * for debugging only.
 */
object RawWorkoutDump {
    private const val TAG = "FOS_RAW_DUMP"
    private const val MAX_ATTACHMENT_BYTES = 500 * 1024 // 500 KB

    /**
     * Check if raw dumps are enabled.
     * Read from BuildConfig (set via gradle property).
     */
    val isEnabled: Boolean
        get() {
            // Check if Sentry is enabled and dump flag is set
            // For now, we'll use a simple check - in production this would read BuildConfig
            return Sentry.isEnabled() && shouldDumpRawWorkouts()
        }

    /**
     * Dump raw workout totals for racket sports.
     */
    fun dumpRacketWorkoutTotals(
        workoutNumber: Int,
        typeCode: Int,
        startTime: Long,
        endTime: Long,
        durationSec: Long,
        rawTotalsHex: String,
        unknownTlvs: List<Map<String, Any>>? = null,
        leftoverTlvs: List<Map<String, Any>>? = null,
        additionalContext: Map<String, Any>? = null,
    ) {
        if (!isEnabled) return

        try {
            val metadata = buildMap<String, Any> {
                put("workoutNumber", workoutNumber)
                put("typeCode", typeCode)
                put("typeName", typeCodeName(typeCode))
                put("startTime", startTime)
                put("endTime", endTime)
                put("durationSec", durationSec)
                put("service", "0x17")
                put("command", "0x08")
                put("commandName", "WorkoutTotals")
                additionalContext?.let { putAll(it) }
            }

            val dump = buildMap<String, Any> {
                put("version", "1.0")
                put("dumpType", "racket_workout_totals")
                put("metadata", metadata)
                put("rawTotalsHex", rawTotalsHex)
                put("rawTotalsLength", rawTotalsHex.length / 2)
                unknownTlvs?.takeIf { it.isNotEmpty() }?.let { put("unknownTlvs", it) }
                leftoverTlvs?.takeIf { it.isNotEmpty() }?.let { put("leftoverTlvs", it) }
            }

            sendDump(
                message = "badminton.raw_dump.totals",
                dump = dump,
                level = SentryLevel.INFO,
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to dump raw workout totals", e)
        }
    }

    /**
     * Dump raw workout data pages (enrichment).
     */
    fun dumpRacketWorkoutData(
        workoutNumber: Int,
        typeCode: Int,
        dataPages: List<Map<String, Any>>,
        rawSampleStreamHex: String? = null,
        additionalContext: Map<String, Any>? = null,
    ) {
        if (!isEnabled) return

        try {
            val metadata = buildMap<String, Any> {
                put("workoutNumber", workoutNumber)
                put("typeCode", typeCode)
                put("typeName", typeCodeName(typeCode))
                put("service", "0x17")
                put("command", "0x0a")
                put("commandName", "WorkoutData")
                put("pageCount", dataPages.size)
                additionalContext?.let { putAll(it) }
            }

            val dump = buildMap<String, Any> {
                put("version", "1.0")
                put("dumpType", "racket_workout_data")
                put("metadata", metadata)
                put("dataPages", dataPages)
                rawSampleStreamHex?.let {
                    put("rawSampleStreamHex", it)
                    put("rawSampleStreamLength", it.length / 2)
                }
            }

            sendDump(
                message = "badminton.raw_dump.data",
                dump = dump,
                level = SentryLevel.INFO,
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to dump raw workout data", e)
        }
    }

    /**
     * Dump raw pace blocks (if present).
     */
    fun dumpRacketWorkoutPace(
        workoutNumber: Int,
        typeCode: Int,
        paceBlocks: List<Map<String, Any>>,
        additionalContext: Map<String, Any>? = null,
    ) {
        if (!isEnabled) return

        try {
            val metadata = buildMap<String, Any> {
                put("workoutNumber", workoutNumber)
                put("typeCode", typeCode)
                put("typeName", typeCodeName(typeCode))
                put("service", "0x17")
                put("command", "0x0c")
                put("commandName", "Pace")
                put("blockCount", paceBlocks.size)
                additionalContext?.let { putAll(it) }
            }

            val dump = buildMap<String, Any> {
                put("version", "1.0")
                put("dumpType", "racket_workout_pace")
                put("metadata", metadata)
                put("paceBlocks", paceBlocks)
            }

            sendDump(
                message = "badminton.raw_dump.pace",
                dump = dump,
                level = SentryLevel.INFO,
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to dump raw workout pace", e)
        }
    }

    private fun sendDump(
        message: String,
        dump: Map<String, Any>,
        level: SentryLevel,
    ) {
        val redactedDump = redactMacs(dump)
        val jsonString = toJson(redactedDump)
        val jsonBytes = jsonString.toByteArray(Charsets.UTF_8)

        if (jsonBytes.size <= MAX_ATTACHMENT_BYTES) {
            // Small enough to send directly in extras
            val event = SentryEvent().apply {
                this.message = Message().apply { this.message = message }
                this.level = level
                setExtra("dump", redactedDump)
            }
            Sentry.captureEvent(event)
        } else {
            // Chunk large payloads
            val chunks = chunkBytes(jsonBytes, MAX_ATTACHMENT_BYTES)
            chunks.forEachIndexed { index, chunk ->
                val chunkMessage = "$message.chunk_${index + 1}_of_${chunks.size}"
                val attachment = io.sentry.Attachment(
                    chunk,
                    "workout_dump_chunk_${index + 1}.json",
                    "application/json",
                )

                val event = SentryEvent().apply {
                    this.message = Message().apply { this.message = chunkMessage }
                    this.level = level
                    setExtra("chunkIndex", index + 1)
                    setExtra("totalChunks", chunks.size)
                    setExtra("chunkSize", chunk.size)
                }

                Sentry.captureEvent(event, Hint.withAttachment(attachment))
            }
        }
    }

    private fun redactMacs(data: Any): Any {
        return when (data) {
            is String -> redactMacAddresses(data)
            is Map<*, *> -> data.mapValues { (_, v) -> redactMacs(v ?: "") }
            is List<*> -> data.map { redactMacs(it ?: "") }
            else -> data
        }
    }

    private fun redactMacAddresses(text: String): String {
        // Redact MAC addresses (AA:BB:CC:DD:EE:FF -> AA:••:••:••:••:FF)
        val macRegex = Regex("""([0-9A-Fa-f]{2}):([0-9A-Fa-f]{2}):([0-9A-Fa-f]{2}):([0-9A-Fa-f]{2}):([0-9A-Fa-f]{2}):([0-9A-Fa-f]{2})""")
        return macRegex.replace(text) { matchResult ->
            "${matchResult.groupValues[1]}:••:••:••:••:${matchResult.groupValues[6]}"
        }
    }

    private fun chunkBytes(bytes: ByteArray, chunkSize: Int): List<ByteArray> {
        val chunks = mutableListOf<ByteArray>()
        var offset = 0
        while (offset < bytes.size) {
            val end = minOf(offset + chunkSize, bytes.size)
            chunks.add(bytes.copyOfRange(offset, end))
            offset = end
        }
        return chunks
    }

    private fun toJson(data: Any): String {
        return when (data) {
            is Map<*, *> -> {
                val json = JSONObject()
                data.forEach { (k, v) ->
                    json.put(k.toString(), toJsonValue(v))
                }
                json.toString()
            }
            is List<*> -> {
                val json = JSONArray()
                data.forEach { json.put(toJsonValue(it)) }
                json.toString()
            }
            else -> data.toString()
        }
    }

    private fun toJsonValue(value: Any?): Any? {
        return when (value) {
            null -> JSONObject.NULL
            is Map<*, *> -> {
                val json = JSONObject()
                value.forEach { (k, v) -> json.put(k.toString(), toJsonValue(v)) }
                json
            }
            is List<*> -> {
                val json = JSONArray()
                value.forEach { json.put(toJsonValue(it)) }
                json
            }
            else -> value
        }
    }

    private fun typeCodeName(code: Int): String {
        return when (code) {
            129 -> "Badminton"
            130 -> "Table tennis"
            131 -> "Tennis"
            133 -> "Squash"
            else -> "Racket sport $code"
        }
    }

    private fun shouldDumpRawWorkouts(): Boolean {
        // Check build config or system property
        // For now, default to true in debug builds
        return try {
            // In a real build, this would check BuildConfig.SENTRY_RAW_WORKOUT_DUMP
            // For now, we'll make it opt-in via a simple check
            val debugMode = android.os.Build.TYPE == "userdebug" || android.os.Build.TYPE == "eng"
            debugMode
        } catch (e: Exception) {
            false
        }
    }
}
