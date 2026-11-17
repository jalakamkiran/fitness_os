package com.example.fitness_os.huawei

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

/**
 * Dispatch-path contract: a decrypted `0x02:0x10` frame maps to one lift_reply
 * payload (ACK wire is built separately when lift is enabled).
 */
class HuaweiSessionLiftDispatchTest {

    @Test
    fun decryptedReplyFrame_mapsToLiftReplyEventFields() {
        val frame = HuaweiFraming.Frame(
            HuaweiNotifyLift.SVC_NOTIFY,
            HuaweiNotifyLift.CMD_REPLY,
            listOf(
                HuaweiFraming.Tlv(0x01, HuaweiPacketCrypto.intBe(2)),
                HuaweiFraming.Tlv(0x02, byteArrayOf(0x00)),
                HuaweiFraming.Tlv(0x04, "lift:ps1:3".toByteArray(Charsets.UTF_8)),
                HuaweiFraming.Tlv(0x06, "Done".toByteArray(Charsets.UTF_8)),
            ),
        )
        val parsed = HuaweiNotifyLift.parseReply(frame)
        assertNotNull(parsed)
        val event = mapOf(
            "type" to "lift_reply",
            "key" to parsed!!.key,
            "text" to parsed.text,
            "replyType" to parsed.replyType,
        )
        assertEquals("lift_reply", event["type"])
        assertEquals("lift:ps1:3", event["key"])
        assertEquals("Done", event["text"])
        assertEquals(2, event["replyType"])
    }

    @Test
    fun nonReplyCmd_doesNotParseAsReply() {
        val frame = HuaweiFraming.Frame(
            HuaweiNotifyLift.SVC_NOTIFY,
            0x04,
            listOf(HuaweiFraming.Tlv(0x01, byteArrayOf(0x00))),
        )
        assertEquals(null, HuaweiNotifyLift.parseReply(frame))
    }
}