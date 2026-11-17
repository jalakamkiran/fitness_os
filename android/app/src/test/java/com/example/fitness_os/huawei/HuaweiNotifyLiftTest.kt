package com.example.fitness_os.huawei

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HuaweiNotifyLiftTest {

    private val allCaps = HuaweiNotifyLift.LiftCaps(
        bit73ReplyActions = true,
        bit77Timestamp = true,
        bit82SmsQuick = true,
        bit89ReplyKey = true,
        bit94KeyedNotify = true,
        bit120Remove = true,
    )

  private val noCaps = HuaweiNotifyLift.LiftCaps()

    @Test
    fun buildSendNotification_tagMatrix_allCaps() {
        val frame = HuaweiNotifyLift.buildSendNotification(
            msgId = 0x4C01,
            type = 0x7F,
            title = "Set 2/4 · Bench",
            sender = "Fathom",
            body = "60 kg × 8",
            sourceAppId = HuaweiNotifyLift.SRC_PHONE_PKG,
            key = "lift:ps_test:2",
            caps = allCaps,
            nowSec = 1_700_000_000L,
            notificationId = 99,
        )
        val tags = frame.tlvs.map { it.tag }.toSet()
        assertEquals(HuaweiNotifyLift.SVC_NOTIFY, frame.serviceId)
        assertEquals(HuaweiNotifyLift.CMD_SEND, frame.commandId)
        assertTrue(tags.containsAll(setOf(0x01, 0x02, 0x03, 0x84, 0x11, 0x18, 0x15, 0x19, 0x1A, 0x1B)))
    }

    @Test
    fun buildSendNotification_noOptionalTags_whenCapsOff() {
        val frame = HuaweiNotifyLift.buildSendNotification(
            msgId = 1,
            type = 0x7F,
            title = "T",
            sender = "F",
            body = "B",
            sourceAppId = HuaweiNotifyLift.SRC_PHONE_PKG,
            key = "lift:a:1",
            caps = noCaps,
            nowSec = 1L,
        )
        val tags = frame.tlvs.map { it.tag }
        assertTrue(0x18 !in tags)
        assertTrue(0x15 !in tags)
        assertTrue(0x19 !in tags)
    }

    @Test
    fun truncateUtf8_respectsEmojiAndMultiply() {
        val s = "60 kg × 8 rest"
        val out = HuaweiNotifyLift.truncateUtf8(s, 12)
        assertTrue(out.toByteArray(Charsets.UTF_8).size <= 12)
    }

    @Test
    fun parseReply_utf8_and_utf16() {
        val utf8 = HuaweiFraming.Frame(
            HuaweiNotifyLift.SVC_NOTIFY,
            HuaweiNotifyLift.CMD_REPLY,
            listOf(
                HuaweiFraming.Tlv(0x01, HuaweiPacketCrypto.intBe(2)),
                HuaweiFraming.Tlv(0x02, byteArrayOf(0x00)),
                HuaweiFraming.Tlv(0x04, "lift:s:1".toByteArray()),
                HuaweiFraming.Tlv(0x06, "Done".toByteArray()),
            ),
        )
        val r1 = HuaweiNotifyLift.parseReply(utf8)
        assertNotNull(r1)
        assertEquals("Done", r1!!.text)

        val utf16Bytes = "OK".toByteArray(Charsets.UTF_16BE)
        val utf16 = HuaweiFraming.Frame(
            HuaweiNotifyLift.SVC_NOTIFY,
            HuaweiNotifyLift.CMD_REPLY,
            listOf(
                HuaweiFraming.Tlv(0x01, HuaweiPacketCrypto.intBe(2)),
                HuaweiFraming.Tlv(0x02, byteArrayOf(3)),
                HuaweiFraming.Tlv(0x04, "lift:s:1".toByteArray()),
                HuaweiFraming.Tlv(0x06, utf16Bytes),
            ),
        )
        assertEquals("OK", HuaweiNotifyLift.parseReply(utf16)!!.text)
    }

    @Test
    fun buildReplyAck_shape() {
        val ack = HuaweiNotifyLift.buildReplyAck(0)
        assertEquals(0x07, ack.tlvs.single().tag)
        assertEquals(0x00, ack.tlvs.single().value[0])
    }

    @Test
    fun parseConstraints_findsContentMax() {
        val item = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x12, byteArrayOf(0x01)),
                HuaweiFraming.Tlv(0x13, byteArrayOf(0x02)),
                HuaweiFraming.Tlv(0x14, HuaweiPacketCrypto.shortBe(180)),
            ),
        )
        val frame = HuaweiFraming.Frame(
            HuaweiNotifyLift.SVC_NOTIFY,
            HuaweiNotifyLift.CMD_CONSTRAINTS,
            listOf(HuaweiFraming.Tlv(0x91, item)),
        )
        val c = HuaweiNotifyLift.parseConstraints(frame)
        assertEquals(180, c.contentMaxLen)
        assertEquals(0x02, c.contentFormat)
    }

    @Test
    fun quickReplyRoundTrip() {
        val payload = HuaweiNotifyLift.buildQuickReplyUpdate(listOf("Done", "Failed"))
        val list = HuaweiNotifyLift.parseQuickReplyList(payload)
        assertTrue(list.contains("Done"))
        assertTrue(list.contains("Failed"))
    }
}