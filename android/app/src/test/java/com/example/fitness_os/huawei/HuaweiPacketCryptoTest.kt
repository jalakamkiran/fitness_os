package com.example.fitness_os.huawei

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicLong

class HuaweiPacketCryptoTest {

    @Test
    fun gcmRoundTrip_preservesTlvs() {
        val key = ByteArray(32) { it.toByte() }
        val plain = listOf(
            HuaweiFraming.Tlv(0x01, byteArrayOf(0x11, 0x22)),
            HuaweiFraming.Tlv(0x02, byteArrayOf()),
        )
        val iv = HuaweiPacketCrypto.nextIv(deviceSupportType = 0x04, counter = AtomicLong(0))
        assertEquals(16, iv.size)

        val enc = HuaweiPacketCrypto.encryptTlvs(plain, key, iv, useGcm = true)
        assertEquals(3, enc.size)
        assertEquals(HuaweiPacketCrypto.TAG_ENCRYPTION, enc[0].tag)
        assertEquals(HuaweiPacketCrypto.TAG_IV, enc[1].tag)
        assertEquals(HuaweiPacketCrypto.TAG_CIPHERTEXT, enc[2].tag)

        val frame = HuaweiFraming.Frame(0x01, 0x07, enc)
        assertTrue(HuaweiPacketCrypto.isEncrypted(frame))
        val dec = HuaweiPacketCrypto.decryptIfNeeded(frame, key, useGcm = true)
        assertFalse(HuaweiPacketCrypto.isEncrypted(dec))
        assertEquals(2, dec.tlvs.size)
        assertEquals(0x01, dec.tlvs[0].tag)
        assertArrayEquals(byteArrayOf(0x11, 0x22), dec.tlvs[0].value)
        assertEquals(0, dec.tlvs[1].value.size)
    }

    @Test
    fun timeAndZoneTlvs_haveExpectedWidths() {
        val tlvs = HuaweiPacketCrypto.timeAndZoneTlvs(1_700_000_000_000L)
        assertEquals(2, tlvs.size)
        assertEquals(4, tlvs[0].value.size)
        assertEquals(2, tlvs[1].value.size)
        assertEquals(1_700_000_000, ((tlvs[0].value[0].toInt() and 0xFF) shl 24) or
            ((tlvs[0].value[1].toInt() and 0xFF) shl 16) or
            ((tlvs[0].value[2].toInt() and 0xFF) shl 8) or
            (tlvs[0].value[3].toInt() and 0xFF))
    }

    @Test
    fun watchZone_formatUnix_usesSyncedOffset() {
        // Aug 11 file segment start — IST vs UTC+5 differ by 30m (Health compare).
        val unix = 1_786_400_940
        val ist = HuaweiPacketCrypto.WatchZone(
            zoneId = "Asia/Kolkata",
            offsetSec = 5 * 3600 + 30 * 60,
            unixAtSync = unix,
        )
        val utc5 = HuaweiPacketCrypto.WatchZone(
            zoneId = "GMT+5:00",
            offsetSec = 5 * 3600,
            unixAtSync = unix,
        )
        assertEquals("2026-08-11 03:59", ist.formatUnix(unix))
        assertEquals("2026-08-11 03:29", utc5.formatUnix(unix))
        assertEquals("UTC+05:30", ist.formatOffsetLabel())
        assertEquals("UTC+05:00", utc5.formatOffsetLabel())
    }

    @Test
    fun parseUnixTag_readsBeInt() {
        val frame = HuaweiFraming.Frame(
            0x01,
            0x05,
            listOf(HuaweiFraming.Tlv(0x01, HuaweiPacketCrypto.intBe(1_700_000_000))),
        )
        assertEquals(1_700_000_000, HuaweiPacketCrypto.parseUnixTag(frame))
    }
}
