package com.example.fitness_os.huawei

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HuaweiNotifyEnableTest {

    @Test
    fun notificationStateEnable_nested81() {
        val frame = HuaweiNotifyEnable.buildNotificationStateEnable(true)
        assertEquals(HuaweiNotifyEnable.SVC_NOTIFY, frame.serviceId)
        assertEquals(HuaweiNotifyEnable.CMD_NOTIFY_STATE, frame.commandId)
        val inner = HuaweiFraming.decodeTlvs(
            frame.tlvs.first { it.tag == 0x81 }.value,
        )
        assertEquals(0x02, inner[0].tag)
        assertEquals(0x01, inner[0].value.single().toInt())
    }

    @Test
    fun wearMessagePush_enableUsesZeroByte() {
        val frame = HuaweiNotifyEnable.buildWearMessagePush(true)
        assertEquals(0x08, frame.commandId)
        assertEquals(0x00, frame.tlvs.first { it.tag == 0x01 }.value.single().toInt())
    }

    @Test
    fun parseResult_smallCode4() {
        val frame = HuaweiFraming.Frame(
            HuaweiNotifyEnable.SVC_NOTIFY,
            0x01,
            listOf(HuaweiFraming.Tlv(0x7F, byteArrayOf(0x00, 0x00, 0x00, 0x04))),
        )
        assertEquals(4, HuaweiNotifyEnable.parseResultCode(frame))
        assertEquals(
            "rejected (notify off, app not allowlisted, or DND)",
            HuaweiNotifyEnable.resultLabel(4),
        )
    }

    @Test
    fun plainSend_omitsReplyTags() {
        val frame = HuaweiNotifyLift.buildSendPlainNotification(
            msgId = 1,
            type = 0x02,
            title = "T",
            body = "B",
            sourceAppId = HuaweiNotifyEnable.PKG_ANDROID_SMS,
        )
        val tags = frame.tlvs.map { it.tag }.toSet()
        assertFalse(tags.contains(0x18))
        assertFalse(tags.contains(0x19))
        assertTrue(tags.contains(0x11))
    }
}