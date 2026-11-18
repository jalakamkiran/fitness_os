package com.example.fitness_os.huawei

/**
 * Notifications svc (0x02) + related DeviceConfig probes for enabling watch notify.
 * Wire shapes from public LPv2 / community behavioral notes — not AGPL paste.
 */
object HuaweiNotifyEnable {
    const val SVC_DEVICE = 0x01
    const val SVC_NOTIFY = HuaweiNotifyLift.SVC_NOTIFY
    const val CMD_NOTIFY_STATE = 0x04
    const val CMD_NOTIFY_CAPS = HuaweiNotifyLift.CMD_CAPABILITIES
    const val CMD_WEAR_MSG_PUSH = 0x08
    const val CMD_DEFAULT_SWITCH = 0x21

    const val PKG_FATHOM = HuaweiNotifyLift.SRC_PHONE_PKG
    const val PKG_ANDROID_SMS = "com.google.android.apps.messaging"

    data class StepLog(
        val step: String,
        val svc: Int,
        val cmd: Int,
        val requestHex: String,
        val responseHex: String?,
        val resultCode: Int?,
        val resultLabel: String?,
        val ok: Boolean,
    )

    /** Nested 0x81 → tags 0x02 + 0x03 mirror the master notification enable switches. */
    fun buildNotificationStateEnable(enabled: Boolean): HuaweiFraming.Frame {
        val inner = listOf(
            HuaweiFraming.Tlv(0x02, byteArrayOf(if (enabled) 0x01 else 0x00)),
            HuaweiFraming.Tlv(0x03, byteArrayOf(if (enabled) 0x01 else 0x00)),
        )
        return HuaweiFraming.Frame(
            SVC_NOTIFY,
            CMD_NOTIFY_STATE,
            listOf(HuaweiFraming.Tlv(0x81, HuaweiFraming.encodeTlvs(inner))),
        )
    }

    /**
     * Wear-message-push while worn (Health “sync notifications” path).
     * Watch expects inverted boolean in tag 0x01: 0x00 = push enabled.
     */
    fun buildWearMessagePush(enablePush: Boolean): HuaweiFraming.Frame =
        HuaweiFraming.Frame(
            SVC_NOTIFY,
            CMD_WEAR_MSG_PUSH,
            listOf(HuaweiFraming.Tlv(0x01, byteArrayOf(if (enablePush) 0x00 else 0x01))),
        )

    fun buildDefaultSwitchQuery(): HuaweiFraming.Frame =
        HuaweiFraming.Frame(
            SVC_DEVICE,
            CMD_DEFAULT_SWITCH,
            listOf(HuaweiFraming.Tlv(0x01, byteArrayOf())),
        )

    fun frameTlvsHex(frame: HuaweiFraming.Frame): String =
        frame.tlvs.joinToString(" ") { tlv ->
            "0x${tlv.tag.toString(16)}:${tlv.value.toHexFull()}"
        }

    fun parseResultCode(frame: HuaweiFraming.Frame): Int? {
        val tlv = frame.tlvs.firstOrNull { it.tag == 0x7F } ?: return null
        return when {
            tlv.value.isEmpty() -> null
            tlv.value.size <= 2 -> tlv.value.last().toInt() and 0xFF
            else -> {
                var v = 0
                for (b in tlv.value) {
                    v = (v shl 8) or (b.toInt() and 0xFF)
                }
                v
            }
        }
    }

    fun resultLabel(code: Int?): String? {
        if (code == null) return null
        return when (code) {
            0 -> "ok"
            HuaweiPacketCrypto.RESULT_OK, 100_000 -> "result_ok"
            4 -> "rejected (notify off, app not allowlisted, or DND)"
            100_001 -> "result_not_supported"
            100_003 -> "result_invalid_param"
            100_004 -> "result_system_busy"
            else -> "result_$code"
        }
    }

    fun isSuccess(code: Int?): Boolean =
        code == null || code == 0 || code == HuaweiPacketCrypto.RESULT_OK || code == 100_000
}