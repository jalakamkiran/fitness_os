package com.example.fitness_os.huawei

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class HuaweiWorkoutSyncTest {

    private val sync = HuaweiWorkoutSync(
        exchangeEncrypted = { _, _, _, _ -> null },
    )

    @Test
    fun parseCount_readsWorkoutNumbersAndHints() {
        val entry1 = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.shortBe(1)),
                HuaweiFraming.Tlv(0x07, HuaweiPacketCrypto.shortBe(2)),
                HuaweiFraming.Tlv(0x08, HuaweiPacketCrypto.shortBe(3)),
                HuaweiFraming.Tlv(0x09, HuaweiPacketCrypto.shortBe(4)),
            ),
        )
        val entry2 = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.shortBe(5)),
                HuaweiFraming.Tlv(0x07, HuaweiPacketCrypto.shortBe(0)),
                HuaweiFraming.Tlv(0x08, HuaweiPacketCrypto.shortBe(0)),
            ),
        )
        val container = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(2)),
                HuaweiFraming.Tlv(0x85, entry1),
                HuaweiFraming.Tlv(0x85, entry2),
            ),
        )
        val frame = HuaweiFraming.Frame(
            HuaweiWorkoutSync.SVC,
            HuaweiWorkoutSync.CMD_COUNT,
            listOf(HuaweiFraming.Tlv(0x81, container)),
        )

        val numbers = sync.parseCount(frame)
        assertEquals(2, numbers.size)
        assertEquals(1, numbers[0].workoutNumber)
        assertEquals(2, numbers[0].dataCount)
        assertEquals(3, numbers[0].paceCount)
        assertEquals(4, numbers[0].segmentsCount)
        assertEquals(5, numbers[1].workoutNumber)
    }

    @Test
    fun parseTotals_readsListFields() {
        val container = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(0x1337)),
                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(0x01020304)),
                HuaweiFraming.Tlv(0x05, HuaweiPacketCrypto.intBe(0x05060708)),
                HuaweiFraming.Tlv(0x12, HuaweiPacketCrypto.intBe(3600)),
                HuaweiFraming.Tlv(0x14, byteArrayOf(0x02)),
                HuaweiFraming.Tlv(0x07, HuaweiPacketCrypto.intBe(5000)),
            ),
        )
        val frame = HuaweiFraming.Frame(
            HuaweiWorkoutSync.SVC,
            HuaweiWorkoutSync.CMD_TOTALS,
            listOf(HuaweiFraming.Tlv(0x81, container)),
        )

        val totals = sync.parseTotals(frame)
        assertNotNull(totals)
        assertEquals(0x1337, totals!!.number)
        assertEquals(0x01020304L, totals.startTime)
        assertEquals(0x05060708L, totals.endTime)
        assertEquals(3600L, totals.durationSec)
        assertEquals(2, totals.type)
        assertEquals(5000L, totals.distanceM)
    }

    @Test
    fun parseTotals_readsHrPeakAndSwimTags() {
        val container = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(42)),
                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(1_700_000_000)),
                HuaweiFraming.Tlv(0x12, HuaweiPacketCrypto.intBe(1800)),
                HuaweiFraming.Tlv(0x14, byteArrayOf(0x05)),
                HuaweiFraming.Tlv(0x0c, byteArrayOf(0x55, 0xAA.toByte())),
                HuaweiFraming.Tlv(0x15, byteArrayOf(0x01)),
                HuaweiFraming.Tlv(0x16, HuaweiPacketCrypto.intBe(1200)),
                HuaweiFraming.Tlv(0x17, HuaweiPacketCrypto.shortBe(28)),
                HuaweiFraming.Tlv(0x18, HuaweiPacketCrypto.shortBe(2500)),
                HuaweiFraming.Tlv(0x19, HuaweiPacketCrypto.shortBe(40)),
                HuaweiFraming.Tlv(0x1a, HuaweiPacketCrypto.shortBe(45)),
            ),
        )
        val frame = HuaweiFraming.Frame(
            HuaweiWorkoutSync.SVC,
            HuaweiWorkoutSync.CMD_TOTALS,
            listOf(HuaweiFraming.Tlv(0x81, container)),
        )

        val totals = sync.parseTotals(frame)!!
        assertEquals(0x55, totals.hrMin)
        assertEquals(0xAA, totals.hrMax)
        assertNull(totals.hrPeak)
        assertEquals(1, totals.swimType)
        assertEquals(1200, totals.strokes)
        assertEquals(28, totals.strokeRate)
        assertEquals(2500, totals.poolLength)
        assertEquals(40, totals.laps)
        assertEquals(45, totals.avgSwolf)
        assertEquals(0, totals.enrichmentTags.size)

        val enriched = totals.withCountHints(
            HuaweiWorkoutSync.WorkoutNumber(
                workoutNumber = 42,
                dataCount = 10,
                paceCount = 0,
                segmentsCount = 8,
            ),
        )
        val map = enriched.toMap()
        assertEquals(10, map["dataCount"])
        assertEquals(0, map["paceCount"])
        assertEquals(8, map["segmentsCount"])
        assertEquals(0x55, map["hrMin"])
        assertEquals(40, map["laps"])
    }

    @Test
    fun parseTotals_recordsUnknownEnrichmentTagLengths() {
        val container = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(7)),
                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(100)),
                HuaweiFraming.Tlv(0x12, HuaweiPacketCrypto.intBe(60)),
                HuaweiFraming.Tlv(0x14, byteArrayOf(0x8C.toByte())),
                HuaweiFraming.Tlv(0x0c, byteArrayOf(0x01, 0x02, 0x03)),
                HuaweiFraming.Tlv(0x15, byteArrayOf(0x01, 0x02)),
            ),
        )
        val frame = HuaweiFraming.Frame(
            HuaweiWorkoutSync.SVC,
            HuaweiWorkoutSync.CMD_TOTALS,
            listOf(HuaweiFraming.Tlv(0x81, container)),
        )

        val totals = sync.parseTotals(frame)!!
        assertNull(totals.hrMin)
        assertNull(totals.swimType)
        assertEquals(2, totals.enrichmentTags.size)
        assertEquals(0x0c, totals.enrichmentTags[0].id)
        assertEquals(3, totals.enrichmentTags[0].len)
        assertEquals(0x15, totals.enrichmentTags[1].id)
        assertEquals(2, totals.enrichmentTags[1].len)
    }

    @Test
    fun parseSwimSegments_expandsNested0x83Laps_swolfChecked() {
        // Capture-shaped #11 lap: style free, 25m, 11s, SWOLF 135, 124 strokes
        // (11 + 124 = 135). Wire index 1 → stored 0. half=0 preferred over half=1.
        fun lap(wireIndex: Int, half: Int, distance: Int, duration: Int, style: Int, swolf: Int, strokes: Int) =
            HuaweiFraming.Tlv(
                0x83,
                HuaweiFraming.encodeTlvs(
                    listOf(
                        HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.shortBe(distance)),
                        HuaweiFraming.Tlv(0x05, byteArrayOf(half.toByte())),
                        HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.shortBe(496)),
                        HuaweiFraming.Tlv(0x09, HuaweiPacketCrypto.shortBe(wireIndex)),
                        HuaweiFraming.Tlv(0x0a, byteArrayOf(style.toByte())),
                        HuaweiFraming.Tlv(0x0b, byteArrayOf(duration.toByte())),
                        HuaweiFraming.Tlv(0x0c, HuaweiPacketCrypto.shortBe(swolf)),
                        HuaweiFraming.Tlv(0x0d, HuaweiPacketCrypto.shortBe(strokes)),
                    ),
                ),
            )

        val inner = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(11)), // workout #
                lap(1, 0, 25, 11, 2, 135, 124),
                lap(1, 1, 25, 11, 2, 135, 124),
                lap(2, 0, 25, 12, 2, 48, 36),
                HuaweiFraming.Tlv(0x08, HuaweiPacketCrypto.shortBe(0)),
            ),
        )
        val frame = HuaweiFraming.Frame(
            HuaweiWorkoutSync.SVC,
            HuaweiWorkoutSync.CMD_SWIM,
            listOf(HuaweiFraming.Tlv(0x81, inner)),
        )

        val all = sync.parseSwimSegments(frame)
        assertEquals(3, all.size)
        assertEquals(0, all[0].index)
        assertEquals(0, all[0].half)
        assertEquals(25L, all[0].distanceM)
        assertEquals(11L, all[0].durationSec)
        assertEquals(2, all[0].style)
        assertEquals(124, all[0].strokes)
        assertEquals(135, all[0].avgSwolf)
        assertEquals(44, all[0].paceSecPer100m) // 11s * 100 / 25m

        // Merge preference: half=0 wins when enriching duplicate indices.
        val byIndex = linkedMapOf<Int, HuaweiWorkoutSync.SwimSegment>()
        for (seg in all) {
            val existing = byIndex[seg.index]
            if (existing == null || (seg.half ?: 0) < (existing.half ?: 0)) {
                byIndex[seg.index] = seg
            }
        }
        assertEquals(2, byIndex.size)
        assertEquals(0, byIndex[0]!!.half)
        assertEquals(36, byIndex[1]!!.strokes)
    }

    @Test
    fun parseWorkoutDataPage_readsHeaderSummaryWithoutSamples() {
        val inner = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(10)),
                HuaweiFraming.Tlv(0x03, HuaweiPacketCrypto.shortBe(1)),
                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(1_700_000_100)),
                HuaweiFraming.Tlv(0x05, HuaweiPacketCrypto.shortBe(60)),
                HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.shortBe(12)),
                HuaweiFraming.Tlv(0x07, HuaweiPacketCrypto.shortBe(240)),
                HuaweiFraming.Tlv(0x08, HuaweiPacketCrypto.shortBe(0x0040)),
            ),
        )
        val frame = HuaweiFraming.Frame(
            HuaweiWorkoutSync.SVC,
            HuaweiWorkoutSync.CMD_DATA,
            listOf(HuaweiFraming.Tlv(0x81, inner)),
        )

        val page = sync.parseWorkoutDataPage(frame, 0)!!
        assertEquals(1, page.index)
        assertEquals(1_700_000_100L, page.timestamp)
        assertEquals(60, page.intervalSec)
        assertEquals(12, page.sampleCount)
        assertEquals(240, page.dataLength)
        assertEquals(0x0040, page.bitmap)
        assertEquals(0, page.tags.size)
    }

    @Test
    fun sync_enrichmentTimeout_keepsTotalsAndPartialBatch() {
        var swimCalls = 0
        val enrichingSync = HuaweiWorkoutSync(
            exchangeEncrypted = { request, service, cmd, _ ->
                when {
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_COUNT -> {
                        val entry = HuaweiFraming.encodeTlvs(
                            listOf(
                                HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.shortBe(9)),
                                HuaweiFraming.Tlv(0x07, HuaweiPacketCrypto.shortBe(0)),
                                HuaweiFraming.Tlv(0x08, HuaweiPacketCrypto.shortBe(0)),
                                HuaweiFraming.Tlv(0x09, HuaweiPacketCrypto.shortBe(2)),
                            ),
                        )
                        val container = HuaweiFraming.encodeTlvs(
                            listOf(
                                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(1)),
                                HuaweiFraming.Tlv(0x85, entry),
                            ),
                        )
                        HuaweiFraming.Frame(
                            HuaweiWorkoutSync.SVC,
                            HuaweiWorkoutSync.CMD_COUNT,
                            listOf(HuaweiFraming.Tlv(0x81, container)),
                        )
                    }
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_TOTALS -> {
                        val container = HuaweiFraming.encodeTlvs(
                            listOf(
                                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(9)),
                                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(100)),
                                HuaweiFraming.Tlv(0x12, HuaweiPacketCrypto.intBe(300)),
                                HuaweiFraming.Tlv(0x14, byteArrayOf(0x05)),
                            ),
                        )
                        HuaweiFraming.Frame(
                            HuaweiWorkoutSync.SVC,
                            HuaweiWorkoutSync.CMD_TOTALS,
                            listOf(HuaweiFraming.Tlv(0x81, container)),
                        )
                    }
                    service == HuaweiWorkoutSync.SVC &&
                        cmd == HuaweiWorkoutSync.CMD_SWIM -> {
                        swimCalls++
                        null
                    }
                    else -> null
                }
            },
        )

        val result = enrichingSync.sync(0, 999_999_999)
        assertEquals("partial_batch", result["status"])
        @Suppress("UNCHECKED_CAST")
        val workouts = result["workouts"] as List<Map<String, Any?>>
        assertEquals(1, workouts.size)
        assertEquals(9, workouts[0]["number"])
        assertEquals(300L, workouts[0]["durationSec"])
        assertEquals("partial", workouts[0]["enrichmentStatus"])
        assertEquals(2, workouts[0]["segmentsCount"])
        assertEquals(1, swimCalls)
    }
}
