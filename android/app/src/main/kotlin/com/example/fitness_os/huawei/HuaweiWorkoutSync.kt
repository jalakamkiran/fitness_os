package com.example.fitness_os.huawei

import android.util.Log
import java.nio.ByteBuffer

/**
 * Clean-room Gate B workout sync — Count → Totals only.
 *
 * Behavioral shapes from public LPv2 / GB oracle (service 0x17). No AGPL paste.
 * Data / Pace / Swim / GPS are intentionally deferred.
 */
class HuaweiWorkoutSync(
    private val exchangeEncrypted: (
        request: HuaweiFraming.Frame,
        expectService: Int,
        expectCmd: Int,
        timeoutMs: Long,
    ) -> HuaweiFraming.Frame?,
) {
    companion object {
        private const val TAG = "FOS_HUAWEI"
        const val SVC = 0x17
        const val CMD_COUNT = 0x07
        const val CMD_TOTALS = 0x08
        private const val TIMEOUT_MS = 20_000L
        /** Same empty-history floor GB uses when no cursor exists. */
        const val FALLBACK_START_UNIX = 1_654_819_200L

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

    data class WorkoutTotals(
        val number: Int,
        val startTime: Long,
        val endTime: Long,
        val durationSec: Long,
        val type: Int,
        val calories: Long?,
        val distanceM: Long?,
        val steps: Long?,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "number" to number,
            "startTime" to startTime,
            "endTime" to endTime,
            "durationSec" to durationSec,
            "type" to type,
            "calories" to calories,
            "distanceM" to distanceM,
            "steps" to steps,
        )
    }

    /**
     * @return status: ok | empty | stuck | error; workouts: list of totals maps
     */
    fun sync(startUnix: Long, endUnix: Long): Map<String, Any?> {
        val start = startUnix.coerceAtLeast(0)
        val end = endUnix.coerceAtLeast(start)
        Log.i(TAG, "workout-sync start window=[$start,$end]")

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
            val totals = parseTotals(totalsFrame)
            if (totals == null) {
                Log.w(TAG, "workout-sync totals parse failed number=${ref.workoutNumber}")
                continue
            }
            Log.i(
                TAG,
                "workout-sync totals number=${totals.number} type=${totals.type} " +
                    "start=${totals.startTime} duration=${totals.durationSec}s",
            )
            workouts.add(totals.toMap())
        }

        return mapOf(
            "status" to "ok",
            "workouts" to workouts,
        )
    }

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
        )
    }
}
