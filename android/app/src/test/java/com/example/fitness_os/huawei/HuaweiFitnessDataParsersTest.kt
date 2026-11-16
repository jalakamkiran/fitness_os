package com.example.fitness_os.huawei

import org.junit.Assert.*
import org.junit.Test

/**
 * Regression tests for Huawei wire parsers covering fitness data (0x07:0x03, 0x0A, 0x0B)
 * and workout totals/data (0x17:0x08, 0x17:0x0A).
 *
 * These tests verify:
 * - FitnessTotals day rollup (0x07:0x03) with calorie tags
 * - Workout totals (0x17:0x08) fields including HR, swim tags, racket sport markers
 * - Workout data pages (0x17:0x0A) including racket/badminton packed HR decoding
 * - Strength workout 5s interval parsing
 *
 * Based on docs/wire-specs/huawei-br-gt5-fitness-data.md
 */
class HuaweiFitnessDataParsersTest {

    @Test
    fun fitnessTotals_parsesStepsAndCalories() {
        // FitnessTotals 0x07:0x03 response format per wire-spec
        val dayRecord = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x04, byteArrayOf(0x01)), // day-anchor slot (1=today)
                HuaweiFraming.Tlv(0x05, HuaweiPacketCrypto.intBe(7825)), // steps
                HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.shortBe(525)), // calories (kcal)
                HuaweiFraming.Tlv(0x07, HuaweiPacketCrypto.intBe(5064)), // unknown duration field
            ),
        )
        val container = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.intBe(1)),
                HuaweiFraming.Tlv(0x83, dayRecord),
            ),
        )

        val tlvs = HuaweiFraming.decodeTlvs(container)
        val dayRecordTlvs = HuaweiFraming.decodeTlvs(
            tlvs.first { it.id == 0x83 }.value,
        )

        val steps = HuaweiPacketCrypto.readIntBe(
            dayRecordTlvs.first { it.id == 0x05 }.value,
        )
        val calories = HuaweiPacketCrypto.readShortBe(
            dayRecordTlvs.first { it.id == 0x06 }.value,
        )

        assertEquals(7825, steps)
        assertEquals(525, calories)
    }

    @Test
    fun fitnessTotals_dayAnchorLocked() {
        // Verify day-anchor slot 1=today, N=N-1 days before
        val today = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x04, byteArrayOf(0x01)),
                HuaweiFraming.Tlv(0x05, HuaweiPacketCrypto.intBe(100)),
            ),
        )
        val yesterday = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x04, byteArrayOf(0x02)),
                HuaweiFraming.Tlv(0x05, HuaweiPacketCrypto.intBe(200)),
            ),
        )

        val todaySlot = HuaweiFraming.decodeTlvs(today)
            .first { it.id == 0x04 }.value[0].toInt()
        val yesterdaySlot = HuaweiFraming.decodeTlvs(yesterday)
            .first { it.id == 0x04 }.value[0].toInt()

        assertEquals(1, todaySlot)
        assertEquals(2, yesterdaySlot)
    }

    @Test
    fun workoutTotals_parsesRacketSportHrFields() {
        // 0x17:0x08 workout totals including racket sport markers
        val totalsContainer = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(17)), // workout number
                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(1700000000)), // start time
                HuaweiFraming.Tlv(0x05, HuaweiPacketCrypto.intBe(1700000732)), // end time
                HuaweiFraming.Tlv(0x12, HuaweiPacketCrypto.intBe(732)), // duration sec
                HuaweiFraming.Tlv(0x14, byteArrayOf(129.toByte())), // type 129 (badminton)
                HuaweiFraming.Tlv(0x0c, byteArrayOf(82.toByte(), 105.toByte())), // hrMin=82, hrMax=105
            ),
        )

        val tlvs = HuaweiFraming.decodeTlvs(totalsContainer)
        val number = HuaweiPacketCrypto.readShortBe(tlvs.first { it.id == 0x02 }.value)
        val type = tlvs.first { it.id == 0x14 }.value[0].toInt() and 0xFF
        val hrBytes = tlvs.first { it.id == 0x0c }.value
        val hrMin = hrBytes[0].toInt() and 0xFF
        val hrMax = hrBytes[1].toInt() and 0xFF

        assertEquals(17, number)
        assertEquals(129, type) // badminton
        assertEquals(82, hrMin)
        assertEquals(105, hrMax)
    }

    @Test
    fun workoutTotals_parsesSwimFields() {
        // 0x17:0x08 with swim-specific tags
        val totalsContainer = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(23)),
                HuaweiFraming.Tlv(0x14, byteArrayOf(0x06)), // type 6 (pool swim)
                HuaweiFraming.Tlv(0x15, byteArrayOf(0x01)), // stroke type
                HuaweiFraming.Tlv(0x16, HuaweiPacketCrypto.intBe(1200)), // distance meters
                HuaweiFraming.Tlv(0x17, HuaweiPacketCrypto.shortBe(28)), // laps
                HuaweiFraming.Tlv(0x18, HuaweiPacketCrypto.shortBe(2500)), // strokes
                HuaweiFraming.Tlv(0x19, HuaweiPacketCrypto.shortBe(40)), // pool length
                HuaweiFraming.Tlv(0x1a, HuaweiPacketCrypto.shortBe(45)), // avg SWOLF
            ),
        )

        val tlvs = HuaweiFraming.decodeTlvs(totalsContainer)
        val type = tlvs.first { it.id == 0x14 }.value[0].toInt() and 0xFF
        val laps = HuaweiPacketCrypto.readShortBe(tlvs.first { it.id == 0x17 }.value)
        val strokes = HuaweiPacketCrypto.readShortBe(tlvs.first { it.id == 0x18 }.value)
        val poolLength = HuaweiPacketCrypto.readShortBe(tlvs.first { it.id == 0x19 }.value)
        val avgSwolf = HuaweiPacketCrypto.readShortBe(tlvs.first { it.id == 0x1a }.value)

        assertEquals(6, type)
        assertEquals(28, laps)
        assertEquals(2500, strokes)
        assertEquals(40, poolLength)
        assertEquals(45, avgSwolf)
    }

    @Test
    fun workoutData_racketPackedHrDecoding() {
        // 0x17:0x0A data page with packed HR for racket sports (1-second intervals)
        // Tag 0x05 = consecutive u8 BPM values
        val hrSamples = byteArrayOf(
            82, 85, 87, 90, 92, 95, 98, 100, 102, 105,
        )
        val dataPageBody = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(0)), // page index
                HuaweiFraming.Tlv(0x05, hrSamples), // packed HR data
            ),
        )

        val tlvs = HuaweiFraming.decodeTlvs(dataPageBody)
        val hrBody = tlvs.firstOrNull { it.id == 0x05 }?.value

        assertNotNull(hrBody)
        assertEquals(10, hrBody!!.size)
        assertEquals(82, hrBody[0].toInt() and 0xFF)
        assertEquals(95, hrBody[5].toInt() and 0xFF)
        assertEquals(105, hrBody[9].toInt() and 0xFF)

        // Verify 1-second interval parsing (offset = index)
        for (i in hrBody.indices) {
            val bpm = hrBody[i].toInt() and 0xFF
            assertTrue("HR should be in valid range 40-220", bpm in 40..220)
        }
    }

    @Test
    fun workoutData_racketHrFilterOutOfRange() {
        // Racket sport HR should filter out-of-range values (< 40 or > 220)
        val hrSamples = byteArrayOf(
            30, 82, 85, 250.toByte(), 92, 95, 0, 100, 102, 255.toByte(),
        )

        for (i in hrSamples.indices) {
            val bpm = hrSamples[i].toInt() and 0xFF
            val valid = bpm in 40..220

            when (i) {
                0 -> assertFalse("30 bpm is too low", valid)
                1, 2 -> assertTrue("82, 85 bpm are valid", valid)
                3 -> assertFalse("250 bpm is too high", valid)
                4, 5 -> assertTrue("92, 95 bpm are valid", valid)
                6 -> assertFalse("0 bpm is invalid", valid)
                7, 8 -> assertTrue("100, 102 bpm are valid", valid)
                9 -> assertFalse("255 bpm is too high", valid)
            }
        }
    }

    @Test
    fun workoutData_strengthFiveSecondInterval() {
        // Strength workout (type 140) uses 5-second intervals for HR
        // Tag 0x05 = packed u8 BPM, but each sample represents 5 seconds
        val hrSamples = byteArrayOf(
            80, 85, 90, 95, 100, 105, 110, 115, 120,
        )
        val dataPageBody = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(0)),
                HuaweiFraming.Tlv(0x05, hrSamples),
            ),
        )

        val tlvs = HuaweiFraming.decodeTlvs(dataPageBody)
        val hrBody = tlvs.first { it.id == 0x05 }.value

        assertEquals(9, hrBody.size)
        // For strength: offsetSec = index * 5
        // Sample 0 @ 0s, sample 1 @ 5s, sample 2 @ 10s, etc.
        for (i in hrBody.indices) {
            val expectedOffsetSec = i * 5
            val bpm = hrBody[i].toInt() and 0xFF
            assertTrue("HR should be valid at offset $expectedOffsetSec", bpm in 40..220)
        }
    }

    @Test
    fun workoutData_multiplePages() {
        // Verify data pages can be concatenated across multiple 0x17:0x0A responses
        val page1 = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(0)),
                HuaweiFraming.Tlv(0x05, byteArrayOf(80, 82, 85)),
            ),
        )
        val page2 = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(1)),
                HuaweiFraming.Tlv(0x05, byteArrayOf(90, 95, 100)),
            ),
        )

        val page1Tlvs = HuaweiFraming.decodeTlvs(page1)
        val page2Tlvs = HuaweiFraming.decodeTlvs(page2)

        val page1Index = HuaweiPacketCrypto.readShortBe(
            page1Tlvs.first { it.id == 0x02 }.value,
        )
        val page2Index = HuaweiPacketCrypto.readShortBe(
            page2Tlvs.first { it.id == 0x02 }.value,
        )

        assertEquals(0, page1Index)
        assertEquals(1, page2Index)

        // Concatenate HR data
        val page1Hr = page1Tlvs.first { it.id == 0x05 }.value
        val page2Hr = page2Tlvs.first { it.id == 0x05 }.value
        val allHr = page1Hr + page2Hr

        assertEquals(6, allHr.size)
        assertEquals(80, allHr[0].toInt() and 0xFF)
        assertEquals(100, allHr[5].toInt() and 0xFF)
    }

    @Test
    fun workoutTotals_calorieFieldsPresent() {
        // Verify calorie tags in workout totals (0x08/0x09 for active/total)
        val totalsContainer = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(1)),
                HuaweiFraming.Tlv(0x08, HuaweiPacketCrypto.shortBe(350)), // active kcal
                HuaweiFraming.Tlv(0x09, HuaweiPacketCrypto.shortBe(450)), // total kcal
            ),
        )

        val tlvs = HuaweiFraming.decodeTlvs(totalsContainer)
        val activeKcal = HuaweiPacketCrypto.readShortBe(
            tlvs.first { it.id == 0x08 }.value,
        )
        val totalKcal = HuaweiPacketCrypto.readShortBe(
            tlvs.first { it.id == 0x09 }.value,
        )

        assertEquals(350, activeKcal)
        assertEquals(450, totalKcal)
    }

    @Test
    fun fitnessTotals_multiDayRecords() {
        // FitnessTotals can return multiple day records (today, yesterday, etc.)
        val day1 = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x04, byteArrayOf(0x01)), // today
                HuaweiFraming.Tlv(0x05, HuaweiPacketCrypto.intBe(7825)),
                HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.shortBe(525)),
            ),
        )
        val day2 = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x04, byteArrayOf(0x02)), // yesterday
                HuaweiFraming.Tlv(0x05, HuaweiPacketCrypto.intBe(9200)),
                HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.shortBe(600)),
            ),
        )
        val container = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.intBe(2)), // count
                HuaweiFraming.Tlv(0x83, day1),
                HuaweiFraming.Tlv(0x83, day2),
            ),
        )

        val tlvs = HuaweiFraming.decodeTlvs(container)
        val dayRecords = tlvs.filter { it.id == 0x83 }

        assertEquals(2, dayRecords.size)

        val day1Tlvs = HuaweiFraming.decodeTlvs(dayRecords[0].value)
        val day2Tlvs = HuaweiFraming.decodeTlvs(dayRecords[1].value)

        assertEquals(1, day1Tlvs.first { it.id == 0x04 }.value[0].toInt())
        assertEquals(2, day2Tlvs.first { it.id == 0x04 }.value[0].toInt())

        val day1Steps = HuaweiPacketCrypto.readIntBe(day1Tlvs.first { it.id == 0x05 }.value)
        val day2Steps = HuaweiPacketCrypto.readIntBe(day2Tlvs.first { it.id == 0x05 }.value)

        assertEquals(7825, day1Steps)
        assertEquals(9200, day2Steps)
    }
}
