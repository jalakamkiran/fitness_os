package com.example.fitness_os.huawei

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * Synthetic framing fixtures (owner-style) — not extracted from Gadgetbridge jars.
 *
 * Known public link-params shape from community LPv2 logs is used only as a
 * structural template; bytes below are produced by [HuaweiFraming.encode].
 */
class HuaweiFramingTest {

    @Test
    fun roundTrip_linkParamsStyleFrame() {
        // Synthetic: SS=0x01 CC=0x01 with empty TLVs tag 1..4 (link-params request shape).
        val frame = HuaweiFraming.Frame(
            serviceId = 0x01,
            commandId = 0x01,
            tlvs = listOf(
                HuaweiFraming.Tlv(0x01, byteArrayOf()),
                HuaweiFraming.Tlv(0x02, byteArrayOf()),
                HuaweiFraming.Tlv(0x03, byteArrayOf()),
                HuaweiFraming.Tlv(0x04, byteArrayOf()),
            ),
        )

        val encoded = HuaweiFraming.encode(frame)
        // Cross-check against independently computed CRC-CCITT XMODEM vector.
        // 5A 00 0B 00 01 01 01 00 02 00 03 00 04 00 | CRC
        val expectedHex = "5A000B0001010100020003000400F13B"
        assertEquals(expectedHex, encoded.toHex())

        when (val result = HuaweiFraming.tryParse(encoded)) {
            is HuaweiFraming.ParseResult.Ok -> {
                assertEquals(encoded.size, result.bytesConsumed)
                assertEquals(0x01, result.frame.serviceId)
                assertEquals(0x01, result.frame.commandId)
                assertEquals(4, result.frame.tlvs.size)
                assertEquals(0x01, result.frame.tlvs[0].tag)
                assertEquals(0, result.frame.tlvs[0].value.size)
                assertEquals(HuaweiFraming.FLAG_NON_SLICED, result.frame.flags)
            }
            is HuaweiFraming.ParseResult.IncompleteFrame -> fail("expected Ok, got IncompleteFrame")
            is HuaweiFraming.ParseResult.Error -> fail("expected Ok, got Error: ${result.reason}")
        }
    }

    @Test
    fun roundTrip_nestedTlvAndVarInt() {
        val nested = HuaweiFraming.encodeTlvs(
            listOf(HuaweiFraming.Tlv(0x01, byteArrayOf(0x02))),
        )
        val frame = HuaweiFraming.Frame(
            serviceId = 0x01,
            commandId = 0x02,
            tlvs = listOf(
                HuaweiFraming.Tlv(0x81, nested), // MSB set → nested container
                HuaweiFraming.Tlv(0x05, byteArrayOf(0x00, 0x01)),
            ),
        )
        val bytes = HuaweiFraming.encode(frame)
        val parsed = HuaweiFraming.tryParse(bytes) as HuaweiFraming.ParseResult.Ok
        assertEquals(frame.serviceId, parsed.frame.serviceId)
        assertEquals(frame.commandId, parsed.frame.commandId)
        assertEquals(2, parsed.frame.tlvs.size)
        assertTrue(parsed.frame.tlvs[0].isNested)
        assertEquals(0x81, parsed.frame.tlvs[0].tag)
        assertTrue(parsed.frame.tlvs[0].value.contentEquals(nested))
        assertEquals(bytes.toHex(), HuaweiFraming.encode(parsed.frame).toHex())
    }

    @Test
    fun truncatedBuffer_returnsIncomplete_doesNotCrash() {
        val full = HuaweiFraming.encode(
            HuaweiFraming.Frame(
                serviceId = 0x01,
                commandId = 0x01,
                tlvs = listOf(HuaweiFraming.Tlv(0x01, byteArrayOf(0x02))),
            ),
        )
        for (n in 0 until full.size) {
            val partial = full.copyOf(n)
            val result = HuaweiFraming.tryParse(partial)
            assertEquals(
                "n=$n should be IncompleteFrame",
                HuaweiFraming.ParseResult.IncompleteFrame,
                result,
            )
        }
    }

    @Test
    fun invalidMagic_rejected() {
        val good = HuaweiFraming.encode(
            HuaweiFraming.Frame(0x01, 0x01, listOf(HuaweiFraming.Tlv(0x01, byteArrayOf()))),
        )
        val bad = good.copyOf()
        bad[0] = 0x00
        when (val result = HuaweiFraming.tryParse(bad)) {
            is HuaweiFraming.ParseResult.Error ->
                assertTrue(result.reason.contains("magic", ignoreCase = true))
            else -> fail("expected Error for invalid magic, got $result")
        }
    }

    @Test
    fun invalidFlags_rejected() {
        val body = byteArrayOf(0x01, 0x01, 0x01, 0x00)
        val lengthField = body.size + 1
        val withoutCrc = byteArrayOf(
            0x5A.toByte(),
            ((lengthField shr 8) and 0xFF).toByte(),
            (lengthField and 0xFF).toByte(),
            0x7F.toByte(), // not a valid non-slice / slice flag
        ) + body
        val crc = HuaweiFraming.crcCcittXmodem(withoutCrc)
        val frame = withoutCrc + byteArrayOf(
            ((crc shr 8) and 0xFF).toByte(),
            (crc and 0xFF).toByte(),
        )
        when (val result = HuaweiFraming.tryParse(frame)) {
            is HuaweiFraming.ParseResult.Error ->
                assertTrue(result.reason.contains("flags", ignoreCase = true))
            else -> fail("expected Error for invalid flags, got $result")
        }
    }

    @Test
    fun varInt_roundTrip() {
        val samples = listOf(0, 1, 127, 128, 255, 300, 16383)
        for (v in samples) {
            val enc = HuaweiFraming.encodeVarInt(v)
            val (decoded, consumed) = HuaweiFraming.decodeVarInt(enc)
            assertEquals(v, decoded)
            assertEquals(enc.size, consumed)
        }
    }

    private fun ByteArray.toHex(): String =
        joinToString("") { b -> "%02X".format(b.toInt() and 0xFF) }
}
