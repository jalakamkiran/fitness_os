package com.example.fitness_os.huawei

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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
    fun parseTotals_keepsUnmatchedTlvBodyInLeftover() {
        val unmatchedBody = byteArrayOf(0xDE.toByte(), 0xAD.toByte(), 0xBE.toByte())
        val container = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(0x42)),
                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(1_700_000_000)),
                HuaweiFraming.Tlv(0x12, HuaweiPacketCrypto.intBe(900)),
                HuaweiFraming.Tlv(0x14, byteArrayOf(140.toByte())),
                HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.intBe(120)),
                HuaweiFraming.Tlv(0x7f, unmatchedBody),
            ),
        )
        val frame = HuaweiFraming.Frame(
            HuaweiWorkoutSync.SVC,
            HuaweiWorkoutSync.CMD_TOTALS,
            listOf(HuaweiFraming.Tlv(0x81, container)),
        )

        val totals = sync.parseTotals(frame)
        assertNotNull(totals)
        assertEquals(0x42, totals!!.number)
        assertEquals(140, totals.type)
        assertEquals(120L, totals.calories)
        assertNull(totals.load)
        assertNull(totals.recoveryTime)

        val leftover = totals.leftoverTlvs
        assertEquals(1, leftover.size)
        assertEquals(0x7f, leftover[0].tag)
        assertEquals(3, leftover[0].value.size)
        assertArrayEquals(unmatchedBody, leftover[0].value)

        val map = totals.toMap()
        assertTrue(map.containsKey("leftover"))
        @Suppress("UNCHECKED_CAST")
        val leftoverBytes = map["leftover"] as ByteArray
        assertEquals(leftoverBytes.size, map["leftoverLen"])
        val decoded = HuaweiFraming.decodeTlvs(leftoverBytes)
        assertEquals(1, decoded.size)
        assertEquals(0x7f, decoded[0].tag)
        assertArrayEquals(unmatchedBody, decoded[0].value)
        // Bodies must not ride enrichmentTags.
        assertEquals(0, totals.enrichmentTags.size)
        assertFalse(map.containsKey("enrichmentTags"))
    }

    @Test
    fun parseTotals_persistsLockedScalarsWhenWidthMatches() {
        val container = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(11)),
                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(1_700_000_100)),
                HuaweiFraming.Tlv(0x12, HuaweiPacketCrypto.intBe(600)),
                HuaweiFraming.Tlv(0x14, byteArrayOf(140.toByte())),
                HuaweiFraming.Tlv(0x0d, HuaweiPacketCrypto.intBe(42)), // load u32
                HuaweiFraming.Tlv(0x0e, HuaweiPacketCrypto.intBe(35)), // aerobicEffect u32
                HuaweiFraming.Tlv(0x11, HuaweiPacketCrypto.shortBe(90)), // recoveryTime u16
                HuaweiFraming.Tlv(0x20, byteArrayOf(18)), // anaerobicEffect u8
                HuaweiFraming.Tlv(0x63, HuaweiPacketCrypto.shortBe(12)), // trainingPoints u16
            ),
        )
        val frame = HuaweiFraming.Frame(
            HuaweiWorkoutSync.SVC,
            HuaweiWorkoutSync.CMD_TOTALS,
            listOf(HuaweiFraming.Tlv(0x81, container)),
        )

        val totals = sync.parseTotals(frame)!!
        assertEquals(42, totals.load)
        assertEquals(35, totals.aerobicEffect)
        assertEquals(90, totals.recoveryTime)
        assertEquals(18, totals.anaerobicEffect)
        assertEquals(12, totals.trainingPoints)
        assertTrue(totals.leftoverTlvs.isEmpty())

        val map = totals.toMap()
        assertEquals(42, map["load"])
        assertEquals(35, map["aerobicEffect"])
        assertEquals(90, map["recoveryTime"])
        assertEquals(18, map["anaerobicEffect"])
        assertEquals(12, map["trainingPoints"])
        assertFalse(map.containsKey("leftover"))
        assertFalse(map.containsKey("leftoverLen"))
    }

    @Test
    fun parseTotals_lockedTagUnexpectedLength_keepsBodyInLeftover() {
        val badLoad = byteArrayOf(0x01, 0x02, 0x03) // not u32
        val container = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(8)),
                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(200)),
                HuaweiFraming.Tlv(0x12, HuaweiPacketCrypto.intBe(60)),
                HuaweiFraming.Tlv(0x14, byteArrayOf(140.toByte())),
                HuaweiFraming.Tlv(0x0d, badLoad),
                HuaweiFraming.Tlv(0x66, byteArrayOf(0x70, 0x71, 0x72, 0x73)), // recovery-HR opaque
            ),
        )
        val frame = HuaweiFraming.Frame(
            HuaweiWorkoutSync.SVC,
            HuaweiWorkoutSync.CMD_TOTALS,
            listOf(HuaweiFraming.Tlv(0x81, container)),
        )

        val totals = sync.parseTotals(frame)!!
        assertNull(totals.load)
        assertEquals(2, totals.leftoverTlvs.size)
        assertEquals(0x0d, totals.leftoverTlvs[0].tag)
        assertArrayEquals(badLoad, totals.leftoverTlvs[0].value)
        assertEquals(0x66, totals.leftoverTlvs[1].tag)
        assertEquals(4, totals.leftoverTlvs[1].value.size)
        // Must not invent integer recovery-HR.
        assertFalse(totals.toMap().containsKey("recoveryHeartRates"))
    }

    @Test
    fun parseTotals_lockedScalarsOmittedWhenAbsent() {
        val container = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(3)),
                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(50)),
                HuaweiFraming.Tlv(0x12, HuaweiPacketCrypto.intBe(30)),
                HuaweiFraming.Tlv(0x14, byteArrayOf(2)),
            ),
        )
        val frame = HuaweiFraming.Frame(
            HuaweiWorkoutSync.SVC,
            HuaweiWorkoutSync.CMD_TOTALS,
            listOf(HuaweiFraming.Tlv(0x81, container)),
        )

        val totals = sync.parseTotals(frame)!!
        assertNull(totals.load)
        assertNull(totals.aerobicEffect)
        assertNull(totals.anaerobicEffect)
        assertNull(totals.recoveryTime)
        assertNull(totals.trainingPoints)
        val map = totals.toMap()
        assertFalse(map.containsKey("load"))
        assertFalse(map.containsKey("aerobicEffect"))
        assertFalse(map.containsKey("anaerobicEffect"))
        assertFalse(map.containsKey("recoveryTime"))
        assertFalse(map.containsKey("trainingPoints"))
        assertFalse(map.containsKey("leftover"))
    }

    @Test
    fun parseTotals_missingNumberOrStart_returnsNullEvenWithLeftover() {
        val container = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x12, HuaweiPacketCrypto.intBe(60)),
                HuaweiFraming.Tlv(0x14, byteArrayOf(140.toByte())),
                HuaweiFraming.Tlv(0x7f, byteArrayOf(0x01, 0x02)),
            ),
        )
        val frame = HuaweiFraming.Frame(
            HuaweiWorkoutSync.SVC,
            HuaweiWorkoutSync.CMD_TOTALS,
            listOf(HuaweiFraming.Tlv(0x81, container)),
        )

        assertNull(sync.parseTotals(frame))
    }

    @Test
    fun sync_totalsMapIncludesLeftoverLen() {
        val unmatchedBody = byteArrayOf(0xAA.toByte(), 0xBB.toByte())
        val enrichingSync = HuaweiWorkoutSync(
            exchangeEncrypted = { _, service, cmd, _ ->
                when {
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_COUNT -> {
                        val entry = HuaweiFraming.encodeTlvs(
                            listOf(
                                HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.shortBe(21)),
                                HuaweiFraming.Tlv(0x07, HuaweiPacketCrypto.shortBe(0)),
                                HuaweiFraming.Tlv(0x08, HuaweiPacketCrypto.shortBe(0)),
                                HuaweiFraming.Tlv(0x09, HuaweiPacketCrypto.shortBe(0)),
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
                                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(21)),
                                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(300)),
                                HuaweiFraming.Tlv(0x12, HuaweiPacketCrypto.intBe(120)),
                                HuaweiFraming.Tlv(0x14, byteArrayOf(140.toByte())),
                                HuaweiFraming.Tlv(0x0d, HuaweiPacketCrypto.intBe(7)),
                                HuaweiFraming.Tlv(0x7f, unmatchedBody),
                            ),
                        )
                        HuaweiFraming.Frame(
                            HuaweiWorkoutSync.SVC,
                            HuaweiWorkoutSync.CMD_TOTALS,
                            listOf(HuaweiFraming.Tlv(0x81, container)),
                        )
                    }
                    else -> null
                }
            },
        )

        val result = enrichingSync.sync(0, 999_999_999)
        assertEquals("ok", result["status"])
        @Suppress("UNCHECKED_CAST")
        val workouts = result["workouts"] as List<Map<String, Any?>>
        assertEquals(1, workouts.size)
        assertEquals(7, workouts[0]["load"])
        assertTrue(workouts[0].containsKey("leftoverLen"))
        assertTrue(workouts[0]["leftoverLen"] is Int)
        @Suppress("UNCHECKED_CAST")
        val leftoverBytes = workouts[0]["leftover"] as ByteArray
        assertEquals(leftoverBytes.size, workouts[0]["leftoverLen"])
        // Channel carries raw bytes once — not a hex string body.
        assertFalse(workouts[0]["leftover"] is String)
        val decoded = HuaweiFraming.decodeTlvs(leftoverBytes)
        assertEquals(1, decoded.size)
        assertEquals(0x7f, decoded[0].tag)
        assertArrayEquals(unmatchedBody, decoded[0].value)
    }

    @Test
    fun parseSwimSegments_expandsNested0x83Laps_gbFieldMap() {
        // GB oracle: 0x0b=strokes, 0x0d=time, 0x05=unitType (0 metric / 1 imperial).
        // SWOLF check: time + strokes (124 + 11 = 135).
        fun lap(
            wireIndex: Int,
            unitType: Int,
            distance: Int,
            strokes: Int,
            style: Int,
            swolf: Int,
            duration: Int,
            pace: Int,
        ) =
            HuaweiFraming.Tlv(
                0x83,
                HuaweiFraming.encodeTlvs(
                    listOf(
                        HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.shortBe(distance)),
                        HuaweiFraming.Tlv(0x05, byteArrayOf(unitType.toByte())),
                        HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.intBe(pace)),
                        HuaweiFraming.Tlv(0x09, HuaweiPacketCrypto.shortBe(wireIndex)),
                        HuaweiFraming.Tlv(0x0a, byteArrayOf(style.toByte())),
                        HuaweiFraming.Tlv(0x0b, HuaweiPacketCrypto.shortBe(strokes)),
                        HuaweiFraming.Tlv(0x0c, HuaweiPacketCrypto.shortBe(swolf)),
                        HuaweiFraming.Tlv(0x0d, HuaweiPacketCrypto.intBe(duration)),
                    ),
                ),
            )

        val inner = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(11)), // workout #
                HuaweiFraming.Tlv(0x08, HuaweiPacketCrypto.shortBe(0)), // page
                lap(1, 0, 25, 11, 2, 135, 124, 496),
                lap(1, 1, 25, 11, 2, 135, 124, 496), // imperial twin
                lap(2, 0, 25, 12, 2, 48, 36, 144),
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
        assertEquals(0, all[0].unitType)
        assertEquals(25L, all[0].distanceM)
        assertEquals(124L, all[0].durationSec)
        assertEquals(2, all[0].style)
        assertEquals(11, all[0].strokes)
        assertEquals(135, all[0].avgSwolf)
        assertEquals(496, all[0].paceSecPer100m) // wire pace preferred

        // Enrichment keeps metric (unitType=0) only, then sequential indexes.
        val metric = all.filter { it.unitType == null || it.unitType == 0 }
        assertEquals(2, metric.size)
        assertEquals(11, metric[0].strokes)
        assertEquals(12, metric[1].strokes)
    }

    @Test
    fun sync_swimRequestUsesPageTag0x08_andAppendsMetricLapsAcrossPages() {
        val swimPageTags = ArrayList<Int>()
        val enrichingSync = HuaweiWorkoutSync(
            exchangeEncrypted = { request, service, cmd, _ ->
                when {
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_COUNT -> {
                        val entry = HuaweiFraming.encodeTlvs(
                            listOf(
                                HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.shortBe(12)),
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
                                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(12)),
                                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(100)),
                                HuaweiFraming.Tlv(0x07, HuaweiPacketCrypto.intBe(50)),
                                HuaweiFraming.Tlv(0x12, HuaweiPacketCrypto.intBe(300)),
                                HuaweiFraming.Tlv(0x14, byteArrayOf(0x06)),
                                HuaweiFraming.Tlv(0x19, HuaweiPacketCrypto.shortBe(4)),
                            ),
                        )
                        HuaweiFraming.Frame(
                            HuaweiWorkoutSync.SVC,
                            HuaweiWorkoutSync.CMD_TOTALS,
                            listOf(HuaweiFraming.Tlv(0x81, container)),
                        )
                    }
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_SWIM -> {
                        val nested = request.tlvs.first { it.tag == 0x81 }.value
                        val kids = HuaweiFraming.decodeTlvs(nested)
                        val pageTag = kids.firstOrNull { it.tag == 0x08 }?.let {
                            HuaweiWorkoutSync.u16(it.value)
                        } ?: -1
                        swimPageTags.add(pageTag)
                        // Wrong legacy tag must not be used for swim pages.
                        assertEquals(null, kids.firstOrNull { it.tag == 0x03 })

                        fun lap(seg: Int, strokes: Int, duration: Int) = HuaweiFraming.Tlv(
                            0x83,
                            HuaweiFraming.encodeTlvs(
                                listOf(
                                    HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.shortBe(25)),
                                    HuaweiFraming.Tlv(0x05, byteArrayOf(0)),
                                    HuaweiFraming.Tlv(0x09, HuaweiPacketCrypto.shortBe(seg)),
                                    HuaweiFraming.Tlv(0x0a, byteArrayOf(2)),
                                    HuaweiFraming.Tlv(0x0b, HuaweiPacketCrypto.shortBe(strokes)),
                                    HuaweiFraming.Tlv(0x0c, HuaweiPacketCrypto.shortBe(duration + strokes)),
                                    HuaweiFraming.Tlv(0x0d, HuaweiPacketCrypto.intBe(duration)),
                                ),
                            ),
                        )
                        val base = pageTag * 2
                        val container = HuaweiFraming.encodeTlvs(
                            listOf(
                                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(12)),
                                HuaweiFraming.Tlv(0x08, HuaweiPacketCrypto.shortBe(pageTag)),
                                lap(base + 1, 10 + base, 20),
                                lap(base + 2, 11 + base, 21),
                            ),
                        )
                        HuaweiFraming.Frame(
                            HuaweiWorkoutSync.SVC,
                            HuaweiWorkoutSync.CMD_SWIM,
                            listOf(HuaweiFraming.Tlv(0x81, container)),
                        )
                    }
                    else -> null
                }
            },
        )

        val result = enrichingSync.sync(0, 999_999_999)
        assertEquals("ok", result["status"])
        assertEquals(listOf(0, 1), swimPageTags)
        @Suppress("UNCHECKED_CAST")
        val workouts = result["workouts"] as List<Map<String, Any?>>
        @Suppress("UNCHECKED_CAST")
        val segments = workouts[0]["segments"] as List<Map<String, Any?>>
        assertEquals(4, segments.size)
        assertEquals(10, segments[0]["strokes"])
        assertEquals(20L, segments[0]["durationSec"])
        assertEquals(13, segments[3]["strokes"])
    }

    @Test
    fun parseWorkoutDataPage_headerOnly_hasNoPointBodies() {
        // Header-only is not "samples persisted" — no unmatched sample TLV bodies.
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
        assertTrue(page.leftoverTlvs.isEmpty())
        assertEquals(0, page.tags.size)
        assertFalse(page.hasPointBodies)
    }

    @Test
    fun parseWorkoutDataPage_keepsUnmatchedSampleBodiesAsEquivalentPoints() {
        val opaqueSampleBody = byteArrayOf(0x7A, 0x7B, 0x7C, 0x7D, 0x7E)
        val inner = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(10)),
                HuaweiFraming.Tlv(0x03, HuaweiPacketCrypto.shortBe(0)),
                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(1_700_000_200)),
                HuaweiFraming.Tlv(0x05, HuaweiPacketCrypto.shortBe(1)),
                HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.shortBe(5)),
                HuaweiFraming.Tlv(0x07, HuaweiPacketCrypto.shortBe(5)),
                HuaweiFraming.Tlv(0x08, HuaweiPacketCrypto.shortBe(0x0001)),
                // Synthetic unmatched sample payload — clean-room; not a GT5 bitmap decode.
                HuaweiFraming.Tlv(0x7a, opaqueSampleBody),
            ),
        )
        val frame = HuaweiFraming.Frame(
            HuaweiWorkoutSync.SVC,
            HuaweiWorkoutSync.CMD_DATA,
            listOf(HuaweiFraming.Tlv(0x81, inner)),
        )

        val page = sync.parseWorkoutDataPage(frame, 0)!!
        assertEquals(5, page.sampleCount)
        assertTrue(page.hasPointBodies)
        assertEquals(1, page.leftoverTlvs.size)
        assertEquals(0x7a, page.leftoverTlvs[0].tag)
        assertArrayEquals(opaqueSampleBody, page.leftoverTlvs[0].value)
        // Channel map stays metadata-sized: id+len only, no body bytes.
        val map = page.toMap()
        assertFalse(map.containsKey("leftover"))
        assertFalse(map.containsKey("points"))
        @Suppress("UNCHECKED_CAST")
        val tags = map["tags"] as List<Map<String, Int>>
        assertEquals(1, tags.size)
        assertEquals(0x7a, tags[0]["id"])
        assertEquals(5, tags[0]["len"])
    }

    @Test
    fun sync_dataCountZero_skipsDataAndSampleFetchNone() {
        var dataCalls = 0
        val enrichingSync = HuaweiWorkoutSync(
            exchangeEncrypted = { _, service, cmd, _ ->
                when {
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_COUNT -> {
                        countFrame(number = 40, dataCount = 0, paceCount = 0, segmentsCount = 0)
                    }
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_TOTALS -> {
                        totalsFrame(number = 40, start = 500, duration = 90, type = 140)
                    }
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_DATA -> {
                        dataCalls++
                        null
                    }
                    else -> null
                }
            },
        )

        val result = enrichingSync.sync(0, 999_999_999)
        assertEquals("ok", result["status"])
        @Suppress("UNCHECKED_CAST")
        val workouts = result["workouts"] as List<Map<String, Any?>>
        assertEquals(1, workouts.size)
        assertEquals(0, workouts[0]["dataCount"])
        assertEquals("none", workouts[0]["sampleFetch"])
        assertEquals("none", workouts[0]["enrichmentStatus"])
        assertEquals(0, dataCalls)
        assertFalse(workouts[0].containsKey("samplePath"))
    }

    @Test
    fun sync_dataPagesWithPointBodies_persistsFileAndMetadataOnly() {
        val opaqueSampleBody = byteArrayOf(0x11, 0x22, 0x33, 0x44)
        val sink = LinkedHashMap<String, ByteArray>()
        var dataCalls = 0
        val enrichingSync = HuaweiWorkoutSync(
            exchangeEncrypted = { _, service, cmd, _ ->
                when {
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_COUNT -> {
                        countFrame(number = 41, dataCount = 1, paceCount = 0, segmentsCount = 0)
                    }
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_TOTALS -> {
                        totalsFrame(number = 41, start = 1_700_000_300, duration = 120, type = 140)
                    }
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_DATA -> {
                        dataCalls++
                        dataPageFrame(
                            workoutNumber = 41,
                            pageIndex = 0,
                            timestamp = 1_700_000_300,
                            intervalSec = 1,
                            sampleCount = 4,
                            dataLength = 4,
                            bitmap = 0x0001,
                            leftover = listOf(HuaweiFraming.Tlv(0x7a, opaqueSampleBody)),
                        )
                    }
                    else -> null
                }
            },
            persistWorkoutSamples = { id, bytes ->
                sink[id] = bytes.copyOf()
                "workouts/hr_samples/$id.bin"
            },
        )

        val result = enrichingSync.sync(0, 999_999_999)
        assertEquals("ok", result["status"])
        @Suppress("UNCHECKED_CAST")
        val workouts = result["workouts"] as List<Map<String, Any?>>
        assertEquals(1, workouts.size)
        assertEquals(1, dataCalls)
        assertEquals("ok", workouts[0]["sampleFetch"])
        assertEquals(4, workouts[0]["sampleCount"])
        assertEquals(1, workouts[0]["dataCount"])
        assertEquals("workouts/hr_samples/41_1700000300.bin", workouts[0]["samplePath"])
        assertEquals(1, sink.size)
        assertTrue(sink.values.first().isNotEmpty())
        // Channel must stay metadata-sized — no multi-point series list.
        assertFalse(workouts[0].containsKey("hrPoints"))
        assertFalse(workouts[0].containsKey("points"))
        @Suppress("UNCHECKED_CAST")
        val dataPages = workouts[0]["dataPages"] as? List<Map<String, Any?>>
        assertNotNull(dataPages)
        assertFalse(dataPages!![0].containsKey("leftover"))
        assertFalse(dataPages[0].containsKey("points"))
    }

    @Test
    fun sync_headerOnlyDataPages_sampleFetchNotOkWithPoints() {
        val sink = LinkedHashMap<String, ByteArray>()
        val enrichingSync = HuaweiWorkoutSync(
            exchangeEncrypted = { _, service, cmd, _ ->
                when {
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_COUNT -> {
                        countFrame(number = 42, dataCount = 1, paceCount = 0, segmentsCount = 0)
                    }
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_TOTALS -> {
                        totalsFrame(number = 42, start = 800, duration = 60, type = 140)
                    }
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_DATA -> {
                        dataPageFrame(
                            workoutNumber = 42,
                            pageIndex = 0,
                            timestamp = 800,
                            intervalSec = 60,
                            sampleCount = 12,
                            dataLength = 240,
                            bitmap = 0x0040,
                            leftover = emptyList(),
                        )
                    }
                    else -> null
                }
            },
            persistWorkoutSamples = { id, bytes ->
                sink[id] = bytes.copyOf()
                "workouts/hr_samples/$id.bin"
            },
        )

        val result = enrichingSync.sync(0, 999_999_999)
        @Suppress("UNCHECKED_CAST")
        val workouts = result["workouts"] as List<Map<String, Any?>>
        assertEquals(1, workouts.size)
        // Pages arrived and header claims samples, but bitmap/payload has no point bodies.
        assertEquals(12, workouts[0]["sampleCount"])
        assertEquals("partial", workouts[0]["sampleFetch"])
        assertFalse(workouts[0].containsKey("samplePath"))
        assertTrue(sink.isEmpty())
    }

    @Test
    fun sync_dataTimeout_keepsTotalsPartialBatchAndSampleFetchTimeout() {
        var dataCalls = 0
        val enrichingSync = HuaweiWorkoutSync(
            exchangeEncrypted = { _, service, cmd, _ ->
                when {
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_COUNT -> {
                        countFrame(number = 43, dataCount = 2, paceCount = 0, segmentsCount = 0)
                    }
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_TOTALS -> {
                        totalsFrame(number = 43, start = 900, duration = 180, type = 140)
                    }
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_DATA -> {
                        dataCalls++
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
        assertEquals(43, workouts[0]["number"])
        assertEquals(180L, workouts[0]["durationSec"])
        assertEquals(2, workouts[0]["dataCount"])
        assertEquals("partial", workouts[0]["enrichmentStatus"])
        assertEquals("timeout", workouts[0]["sampleFetch"])
        assertFalse(workouts[0].containsKey("samplePath"))
        assertEquals(1, dataCalls)
    }

    @Test
    fun sync_enrichmentTimeout_keepsTotalsAndPartialBatch() {
        var swimCalls = 0
        val enrichingSync = HuaweiWorkoutSync(
            exchangeEncrypted = { _, service, cmd, _ ->
                when {
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_COUNT -> {
                        countFrame(number = 9, dataCount = 0, paceCount = 0, segmentsCount = 2)
                    }
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_TOTALS -> {
                        totalsFrame(number = 9, start = 100, duration = 300, type = 5)
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
        // Count said no Data pages — do not claim sample load was absent beyond none.
        assertEquals("none", workouts[0]["sampleFetch"])
    }

    @Test
    fun sync_historicalSwimOutsideEnrichWindow_skipsDataTotalsOnly() {
        var dataCalls = 0
        val enrichingSync = HuaweiWorkoutSync(
            exchangeEncrypted = { _, service, cmd, _ ->
                when {
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_COUNT -> {
                        countFrame(number = 60, dataCount = 2, paceCount = 0, segmentsCount = 0)
                    }
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_TOTALS -> {
                        // Historical run/swim — start before enrich floor.
                        totalsFrame(number = 60, start = 1_600_000_000, duration = 400, type = 2)
                    }
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_DATA -> {
                        dataCalls++
                        null
                    }
                    else -> null
                }
            },
        )

        val result = enrichingSync.sync(
            startUnix = HuaweiWorkoutSync.FALLBACK_START_UNIX,
            endUnix = 999_999_999,
            enrichStartUnix = 1_700_000_000,
        )
        assertEquals("ok", result["status"])
        @Suppress("UNCHECKED_CAST")
        val workouts = result["workouts"] as List<Map<String, Any?>>
        assertEquals(1, workouts.size)
        assertEquals(2, workouts[0]["dataCount"])
        assertEquals("none", workouts[0]["enrichmentStatus"])
        assertEquals("none", workouts[0]["sampleFetch"])
        assertEquals(0, dataCalls)
    }

    @Test
    fun sync_historicalStrengthWithData_enrichesDespiteEnrichFloor() {
        var dataCalls = 0
        val enrichingSync = HuaweiWorkoutSync(
            exchangeEncrypted = { _, service, cmd, _ ->
                when {
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_COUNT -> {
                        countFrame(number = 61, dataCount = 1, paceCount = 0, segmentsCount = 0)
                    }
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_TOTALS -> {
                        totalsFrame(number = 61, start = 1_600_000_100, duration = 900, type = 140)
                    }
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_DATA -> {
                        dataCalls++
                        dataPageFrame(
                            workoutNumber = 61,
                            pageIndex = 0,
                            timestamp = 1_600_000_100,
                            intervalSec = 1,
                            sampleCount = 2,
                            dataLength = 2,
                            bitmap = 0x0001,
                            leftover = listOf(HuaweiFraming.Tlv(0x7a, byteArrayOf(0x01, 0x02))),
                        )
                    }
                    else -> null
                }
            },
            persistWorkoutSamples = { id, _ -> "workouts/hr_samples/$id.bin" },
        )

        val result = enrichingSync.sync(
            startUnix = HuaweiWorkoutSync.FALLBACK_START_UNIX,
            endUnix = 999_999_999,
            enrichStartUnix = 1_700_000_000,
        )
        assertEquals("ok", result["status"])
        @Suppress("UNCHECKED_CAST")
        val workouts = result["workouts"] as List<Map<String, Any?>>
        assertEquals(1, workouts.size)
        assertEquals(1, dataCalls)
        assertEquals("ok", workouts[0]["sampleFetch"])
        assertTrue(workouts[0].containsKey("samplePath"))
    }

    @Test
    fun sync_recentOutsideStrength_stillEnrichesWhenInWindow() {
        var swimCalls = 0
        val enrichingSync = HuaweiWorkoutSync(
            exchangeEncrypted = { _, service, cmd, _ ->
                when {
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_COUNT -> {
                        countFrame(number = 62, dataCount = 0, paceCount = 0, segmentsCount = 1)
                    }
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_TOTALS -> {
                        totalsFrame(number = 62, start = 1_700_000_500, duration = 200, type = 6)
                    }
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_SWIM -> {
                        swimCalls++
                        null
                    }
                    else -> null
                }
            },
        )

        val result = enrichingSync.sync(
            startUnix = HuaweiWorkoutSync.FALLBACK_START_UNIX,
            endUnix = 999_999_999,
            enrichStartUnix = 1_700_000_000,
        )
        assertEquals("partial_batch", result["status"])
        @Suppress("UNCHECKED_CAST")
        val workouts = result["workouts"] as List<Map<String, Any?>>
        assertEquals(1, workouts.size)
        assertEquals(1, swimCalls)
        assertEquals("partial", workouts[0]["enrichmentStatus"])
    }

    @Test
    fun toMap_smallLeftover_inlinesBodyOnChannel() {
        val unmatchedBody = byteArrayOf(0x0a, 0x0b, 0x0c)
        val container = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(42)),
                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(1_700_000_100)),
                HuaweiFraming.Tlv(0x12, HuaweiPacketCrypto.intBe(600)),
                HuaweiFraming.Tlv(0x14, byteArrayOf(140.toByte())),
                HuaweiFraming.Tlv(0x7f, unmatchedBody),
            ),
        )
        val frame = HuaweiFraming.Frame(
            HuaweiWorkoutSync.SVC,
            HuaweiWorkoutSync.CMD_TOTALS,
            listOf(HuaweiFraming.Tlv(0x81, container)),
        )
        val totals = sync.parseTotals(frame)!!
        val map = totals.toMap()
        assertTrue(map.containsKey("leftover"))
        assertFalse(map.containsKey("leftoverPath"))
        assertEquals(true, map["leftoverPresent"])
    }

    @Test
    fun toMap_largeLeftover_spillsToSinkOmitsBody() {
        val bigBody = ByteArray(HuaweiWorkoutSync.LEFTOVER_INLINE_MAX_BYTES + 16) { i ->
            (i % 251).toByte()
        }
        val container = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(77)),
                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(1_700_111_000)),
                HuaweiFraming.Tlv(0x12, HuaweiPacketCrypto.intBe(900)),
                HuaweiFraming.Tlv(0x14, byteArrayOf(140.toByte())),
                HuaweiFraming.Tlv(0x66, bigBody),
            ),
        )
        val frame = HuaweiFraming.Frame(
            HuaweiWorkoutSync.SVC,
            HuaweiWorkoutSync.CMD_TOTALS,
            listOf(HuaweiFraming.Tlv(0x81, container)),
        )
        val totals = sync.parseTotals(frame)!!
        var sinkCalls = 0
        var sunkId: String? = null
        var sunkLen = 0
        val map = totals.toMap(
            leftoverSink = { id, bytes ->
                sinkCalls++
                sunkId = id
                sunkLen = bytes.size
                "${HuaweiWorkoutSync.WORKOUT_LEFTOVERS_DIR}/$id.bin"
            },
            forceSpill = true,
        )
        assertEquals(1, sinkCalls)
        assertEquals("77_1700111000", sunkId)
        assertEquals(map["leftoverLen"], sunkLen)
        assertFalse(map.containsKey("leftover"))
        assertEquals(
            "${HuaweiWorkoutSync.WORKOUT_LEFTOVERS_DIR}/77_1700111000.bin",
            map["leftoverPath"],
        )
        assertEquals(true, map["leftoverPresent"])
    }

    @Test
    fun sync_largeLeftover_spillsViaSinkOmitsChannelBody() {
        val bigBody = ByteArray(HuaweiWorkoutSync.LEFTOVER_INLINE_MAX_BYTES + 32) { 7 }
        val spilled = mutableListOf<Pair<String, Int>>()
        val enrichingSync = HuaweiWorkoutSync(
            exchangeEncrypted = { _, service, cmd, _ ->
                when {
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_COUNT -> {
                        countFrame(
                            number = 88,
                            dataCount = 0,
                            paceCount = 0,
                            segmentsCount = 0,
                        )
                    }
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_TOTALS -> {
                        val container = HuaweiFraming.encodeTlvs(
                            listOf(
                                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(88)),
                                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(1_700_222_000)),
                                HuaweiFraming.Tlv(0x12, HuaweiPacketCrypto.intBe(300)),
                                HuaweiFraming.Tlv(0x14, byteArrayOf(140.toByte())),
                                HuaweiFraming.Tlv(0x7f, bigBody),
                            ),
                        )
                        HuaweiFraming.Frame(
                            HuaweiWorkoutSync.SVC,
                            HuaweiWorkoutSync.CMD_TOTALS,
                            listOf(HuaweiFraming.Tlv(0x81, container)),
                        )
                    }
                    else -> null
                }
            },
            persistWorkoutLeftovers = { id, bytes ->
                spilled += id to bytes.size
                "${HuaweiWorkoutSync.WORKOUT_LEFTOVERS_DIR}/$id.bin"
            },
        )
        val result = enrichingSync.sync(0, 999_999_999)
        assertEquals("ok", result["status"])
        @Suppress("UNCHECKED_CAST")
        val workouts = result["workouts"] as List<Map<String, Any?>>
        assertEquals(1, workouts.size)
        assertFalse(workouts[0].containsKey("leftover"))
        assertEquals(
            "${HuaweiWorkoutSync.WORKOUT_LEFTOVERS_DIR}/88_1700222000.bin",
            workouts[0]["leftoverPath"],
        )
        assertEquals(true, workouts[0]["leftoverPresent"])
        assertEquals(1, spilled.size)
        assertEquals("88_1700222000", spilled[0].first)
    }

    @Test
    fun sync_cumulativeLeftoverBudget_spillsLaterSessions() {
        // Chunks under INLINE_MAX so only cumulative budget forces spill.
        val chunk = HuaweiWorkoutSync.LEFTOVER_INLINE_MAX_BYTES - 2048
        val need =
            (HuaweiWorkoutSync.LEFTOVER_CHANNEL_BUDGET_BYTES / chunk) + 1
        val numbers = (1..need).toList()
        var countServed = false
        var totalsIndex = 0
        val spilled = mutableListOf<String>()
        val enrichingSync = HuaweiWorkoutSync(
            exchangeEncrypted = { _, service, cmd, _ ->
                when {
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_COUNT -> {
                        if (countServed) return@HuaweiWorkoutSync null
                        countServed = true
                        val entries = numbers.map { n ->
                            val entry = HuaweiFraming.encodeTlvs(
                                listOf(
                                    HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.shortBe(n)),
                                    HuaweiFraming.Tlv(0x07, HuaweiPacketCrypto.shortBe(0)),
                                    HuaweiFraming.Tlv(0x08, HuaweiPacketCrypto.shortBe(0)),
                                    HuaweiFraming.Tlv(0x09, HuaweiPacketCrypto.shortBe(0)),
                                ),
                            )
                            HuaweiFraming.Tlv(0x85, entry)
                        }
                        val container = HuaweiFraming.encodeTlvs(
                            listOf(HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(numbers.size))) +
                                entries,
                        )
                        HuaweiFraming.Frame(
                            HuaweiWorkoutSync.SVC,
                            HuaweiWorkoutSync.CMD_COUNT,
                            listOf(HuaweiFraming.Tlv(0x81, container)),
                        )
                    }
                    service == HuaweiWorkoutSync.SVC && cmd == HuaweiWorkoutSync.CMD_TOTALS -> {
                        val n = numbers[totalsIndex++]
                        val body = ByteArray(chunk) { n.toByte() }
                        val container = HuaweiFraming.encodeTlvs(
                            listOf(
                                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(n)),
                                HuaweiFraming.Tlv(
                                    0x04,
                                    HuaweiPacketCrypto.intBe(1_700_300_000 + n),
                                ),
                                HuaweiFraming.Tlv(0x12, HuaweiPacketCrypto.intBe(60)),
                                HuaweiFraming.Tlv(0x14, byteArrayOf(140.toByte())),
                                HuaweiFraming.Tlv(0x7f, body),
                            ),
                        )
                        HuaweiFraming.Frame(
                            HuaweiWorkoutSync.SVC,
                            HuaweiWorkoutSync.CMD_TOTALS,
                            listOf(HuaweiFraming.Tlv(0x81, container)),
                        )
                    }
                    else -> null
                }
            },
            persistWorkoutLeftovers = { id, _ ->
                spilled += id
                "${HuaweiWorkoutSync.WORKOUT_LEFTOVERS_DIR}/$id.bin"
            },
        )
        @Suppress("UNCHECKED_CAST")
        val workouts =
            enrichingSync.sync(0, 999_999_999)["workouts"] as List<Map<String, Any?>>
        assertEquals(need, workouts.size)
        assertTrue(workouts.first().containsKey("leftover"))
        assertFalse(workouts.first().containsKey("leftoverPath"))
        assertTrue(workouts.last().containsKey("leftoverPath"))
        assertFalse(workouts.last().containsKey("leftover"))
        assertTrue(spilled.isNotEmpty())
    }

    private fun countFrame(
        number: Int,
        dataCount: Int,
        paceCount: Int,
        segmentsCount: Int,
    ): HuaweiFraming.Frame {
        val entry = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.shortBe(number)),
                HuaweiFraming.Tlv(0x07, HuaweiPacketCrypto.shortBe(dataCount)),
                HuaweiFraming.Tlv(0x08, HuaweiPacketCrypto.shortBe(paceCount)),
                HuaweiFraming.Tlv(0x09, HuaweiPacketCrypto.shortBe(segmentsCount)),
            ),
        )
        val container = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(1)),
                HuaweiFraming.Tlv(0x85, entry),
            ),
        )
        return HuaweiFraming.Frame(
            HuaweiWorkoutSync.SVC,
            HuaweiWorkoutSync.CMD_COUNT,
            listOf(HuaweiFraming.Tlv(0x81, container)),
        )
    }

    private fun totalsFrame(
        number: Int,
        start: Int,
        duration: Int,
        type: Int,
    ): HuaweiFraming.Frame {
        val container = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(number)),
                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(start)),
                HuaweiFraming.Tlv(0x12, HuaweiPacketCrypto.intBe(duration)),
                HuaweiFraming.Tlv(0x14, byteArrayOf(type.toByte())),
            ),
        )
        return HuaweiFraming.Frame(
            HuaweiWorkoutSync.SVC,
            HuaweiWorkoutSync.CMD_TOTALS,
            listOf(HuaweiFraming.Tlv(0x81, container)),
        )
    }

    private fun dataPageFrame(
        workoutNumber: Int,
        pageIndex: Int,
        timestamp: Int,
        intervalSec: Int,
        sampleCount: Int,
        dataLength: Int,
        bitmap: Int,
        leftover: List<HuaweiFraming.Tlv>,
    ): HuaweiFraming.Frame {
        val inner = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(workoutNumber)),
                HuaweiFraming.Tlv(0x03, HuaweiPacketCrypto.shortBe(pageIndex)),
                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(timestamp)),
                HuaweiFraming.Tlv(0x05, HuaweiPacketCrypto.shortBe(intervalSec)),
                HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.shortBe(sampleCount)),
                HuaweiFraming.Tlv(0x07, HuaweiPacketCrypto.shortBe(dataLength)),
                HuaweiFraming.Tlv(0x08, HuaweiPacketCrypto.shortBe(bitmap)),
            ) + leftover,
        )
        return HuaweiFraming.Frame(
            HuaweiWorkoutSync.SVC,
            HuaweiWorkoutSync.CMD_DATA,
            listOf(HuaweiFraming.Tlv(0x81, inner)),
        )
    }
}
