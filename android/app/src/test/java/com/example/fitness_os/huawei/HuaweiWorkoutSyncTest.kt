package com.example.fitness_os.huawei

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class HuaweiWorkoutSyncTest {

    private val sync = HuaweiWorkoutSync(
        exchangeEncrypted = { _, _, _, _ -> null },
    )

    @Test
    fun parseCount_readsWorkoutNumbers() {
        val entry1 = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.shortBe(1)),
                HuaweiFraming.Tlv(0x07, HuaweiPacketCrypto.shortBe(2)),
                HuaweiFraming.Tlv(0x08, HuaweiPacketCrypto.shortBe(3)),
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
}
