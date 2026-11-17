package com.example.fitness_os.huawei

import java.nio.ByteBuffer
import java.nio.charset.Charset

/**
 * Notifications svc 0x02 builders/parsers for on-watch strength set logging.
 * Wire layout per community LPv2 captures — not AGPL source.
 */
object HuaweiNotifyLift {
    const val SVC_NOTIFY = 0x02
    const val CMD_SEND = 0x01
    const val CMD_CONSTRAINTS = 0x02
    const val CMD_CAPABILITIES = 0x05
    const val CMD_REMOVE = 0x06
    const val CMD_REPLY = 0x10

    const val SVC_P2P = 0x34
    const val CMD_P2P = 0x01
    const val P2P_CMD_SEND = 0x02

    const val MODULE_SMS_QUICK = "hw.unitedevice.smsquick"
    const val DST_WATCH_HOME = "com.huawei.watch.home"
    const val SRC_PHONE_PKG = "com.example.fitness_os"
    const val CHANNEL_LIFT = "fathom_lift"

    const val CMD_QUICK_QUERY = 7001
    const val CMD_QUICK_UPDATE = 7002

    /** Public LPv2 community documentation — app signature hash placeholders for P2P. */
    const val FINGERPRINT_PHONE =
        "0000000000000000000000000000000000000000"
    const val FINGERPRINT_WATCH =
        "0000000000000000000000000000000000000000"

    const val TEXT_TITLE = 0x03
    const val TEXT_SENDER = 0x02
    const val TEXT_BODY = 0x01

    data class LiftCaps(
        val bit73ReplyActions: Boolean = false,
        val bit77Timestamp: Boolean = false,
        val bit82SmsQuick: Boolean = false,
        val bit89ReplyKey: Boolean = false,
        val bit94KeyedNotify: Boolean = false,
        val bit120Remove: Boolean = false,
    )

    data class NotifyConstraints(
        val contentMaxLen: Int?,
        val contentFormat: Int?,
    )

    data class LiftReply(
        val replyType: Int,
        val encoding: Int,
        val key: String,
        val extra: String,
        val text: String,
    )

    data class LastSentNotification(
        val msgId: Int,
        val notifyType: Int,
        val key: String,
        val notificationId: Int,
        val category: String?,
    )

    fun buildConstraintsRequest(): HuaweiFraming.Frame =
        HuaweiFraming.Frame(SVC_NOTIFY, CMD_CONSTRAINTS, listOf(HuaweiFraming.Tlv(0x01, byteArrayOf())))

    fun buildCapabilitiesRequest(): HuaweiFraming.Frame =
        HuaweiFraming.Frame(SVC_NOTIFY, CMD_CAPABILITIES, listOf(HuaweiFraming.Tlv(0x01, byteArrayOf())))

    fun parseConstraints(frame: HuaweiFraming.Frame): NotifyConstraints {
        var maxLen: Int? = null
        var format: Int? = null
        fun walk(tlvs: List<HuaweiFraming.Tlv>) {
            for (tlv in tlvs) {
                if (tlv.tag == 0x91) {
                    val inner = try {
                        HuaweiFraming.decodeTlvs(tlv.value)
                    } catch (_: Exception) {
                        continue
                    }
                    val kind = inner.firstOrNull { it.tag == 0x12 }?.value?.firstOrNull()?.toInt()?.and(0xFF)
                    if (kind == 0x01) {
                        val f = inner.firstOrNull { it.tag == 0x13 }?.value?.firstOrNull()?.toInt()?.and(0xFF)
                        val lenBytes = inner.firstOrNull { it.tag == 0x14 }?.value
                        if (lenBytes != null && lenBytes.size >= 2) {
                            maxLen = shortBeDecode(lenBytes)
                            format = f
                        }
                    }
                } else if (tlv.isNested) {
                    walk(HuaweiFraming.decodeTlvs(tlv.value))
                }
            }
        }
        walk(frame.tlvs)
        return NotifyConstraints(maxLen, format)
    }

    fun buildSendNotification(
        msgId: Int,
        type: Int,
        title: String,
        sender: String,
        body: String,
        sourceAppId: String,
        key: String,
        caps: LiftCaps,
        nowSec: Long,
        contentFormat: Int = 0x02,
        contentMaxLen: Int? = null,
        notificationId: Int = msgId,
        category: String? = null,
    ): HuaweiFraming.Frame {
        val maxBody = contentMaxLen?.let { (it - 3).coerceAtLeast(8) }
        val safeTitle = truncateUtf8(title, 120)
        val safeSender = truncateUtf8(sender, 40)
        val safeBody = truncateUtf8(body, maxBody ?: 240)

        val texts = listOf(
            Triple(TEXT_TITLE, safeTitle),
            Triple(TEXT_SENDER, safeSender),
            Triple(TEXT_BODY, safeBody),
        )
        val elements = texts.map { (textType, text) ->
            val inner = listOf(
                HuaweiFraming.Tlv(0x0E, byteArrayOf(textType.toByte())),
                HuaweiFraming.Tlv(0x0F, byteArrayOf(contentFormat.toByte())),
                HuaweiFraming.Tlv(0x10, text.toByteArray(Charsets.UTF_8)),
            )
            HuaweiFraming.Tlv(0x8D, HuaweiFraming.encodeTlvs(inner))
        }
        val contentContainer = HuaweiFraming.Tlv(0x8C, HuaweiFraming.encodeTlvs(elements))
        val outerContent = HuaweiFraming.Tlv(0x84, HuaweiFraming.encodeTlvs(listOf(contentContainer)))

        val tlvs = mutableListOf<HuaweiFraming.Tlv>(
            HuaweiFraming.Tlv(0x01, HuaweiPacketCrypto.shortBe(msgId)),
            HuaweiFraming.Tlv(0x02, byteArrayOf(type.toByte())),
            HuaweiFraming.Tlv(0x03, byteArrayOf(0x01)),
            outerContent,
            HuaweiFraming.Tlv(0x11, sourceAppId.toByteArray(Charsets.UTF_8)),
        )
        if (caps.bit89ReplyKey && key.isNotEmpty()) {
            tlvs += HuaweiFraming.Tlv(0x18, key.toByteArray(Charsets.UTF_8))
        }
        if (caps.bit77Timestamp) {
            tlvs += HuaweiFraming.Tlv(0x15, HuaweiPacketCrypto.intBe(nowSec.toInt()))
        }
        if (caps.bit94KeyedNotify || caps.bit120Remove) {
            tlvs += HuaweiFraming.Tlv(0x19, key.toByteArray(Charsets.UTF_8))
            tlvs += HuaweiFraming.Tlv(0x1A, HuaweiPacketCrypto.intBe(notificationId))
            tlvs += HuaweiFraming.Tlv(0x1B, CHANNEL_LIFT.toByteArray(Charsets.UTF_8))
        }
        category?.let {
            tlvs += HuaweiFraming.Tlv(0x12, it.toByteArray(Charsets.UTF_8))
        }
        return HuaweiFraming.Frame(SVC_NOTIFY, CMD_SEND, tlvs)
    }

    fun buildRemove(
        type: Int,
        sourceAppId: String,
        key: String,
        notificationId: Int,
        category: String? = null,
    ): HuaweiFraming.Frame {
        val tlvs = mutableListOf(
            HuaweiFraming.Tlv(0x01, byteArrayOf(type.toByte())),
            HuaweiFraming.Tlv(0x02, sourceAppId.toByteArray(Charsets.UTF_8)),
            HuaweiFraming.Tlv(0x03, key.toByteArray(Charsets.UTF_8)),
            HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(notificationId)),
            HuaweiFraming.Tlv(0x05, CHANNEL_LIFT.toByteArray(Charsets.UTF_8)),
        )
        category?.let { tlvs += HuaweiFraming.Tlv(0x06, it.toByteArray(Charsets.UTF_8)) }
        return HuaweiFraming.Frame(SVC_NOTIFY, CMD_REMOVE, tlvs)
    }

    fun parseReply(frame: HuaweiFraming.Frame): LiftReply? {
        if (frame.serviceId != SVC_NOTIFY || frame.commandId != CMD_REPLY) return null
        val replyType = frame.tlvs.firstOrNull { it.tag == 0x01 }?.value?.let { intFromValue(it) } ?: return null
        val encoding = frame.tlvs.firstOrNull { it.tag == 0x02 }?.value?.let { intFromValue(it) } ?: 0
        val key = frame.tlvs.firstOrNull { it.tag == 0x04 }?.value?.toString(Charsets.UTF_8) ?: ""
        val extra = frame.tlvs.firstOrNull { it.tag == 0x05 }?.value?.toString(Charsets.UTF_8) ?: ""
        val raw = frame.tlvs.firstOrNull { it.tag == 0x06 }?.value ?: return null
        val text = if (encoding == 3) {
            decodeUtf16(raw)
        } else {
            raw.toString(Charsets.UTF_8)
        }
        return LiftReply(replyType, encoding, key, extra, text)
    }

    fun buildReplyAck(code: Int = 0x00): HuaweiFraming.Frame =
        HuaweiFraming.Frame(
            SVC_NOTIFY,
            CMD_REPLY,
            listOf(HuaweiFraming.Tlv(0x07, byteArrayOf(code.toByte()))),
        )

    fun buildQuickReplyQuery(): ByteArray {
        val payload = HuaweiFraming.encodeTlvs(
            listOf(HuaweiFraming.Tlv(0x01, HuaweiPacketCrypto.intBe(CMD_QUICK_QUERY))),
        )
        return payload
    }

    fun buildQuickReplyUpdate(replies: List<String>): ByteArray {
        val items = replies.take(5).map { text ->
            HuaweiFraming.Tlv(
                0x83,
                HuaweiFraming.encodeTlvs(
                    listOf(HuaweiFraming.Tlv(0x04, text.toByteArray(Charsets.UTF_8))),
                ),
            )
        }
        val container = HuaweiFraming.Tlv(0x82, HuaweiFraming.encodeTlvs(items))
        return HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x01, HuaweiPacketCrypto.intBe(CMD_QUICK_UPDATE)),
                container,
            ),
        )
    }

    fun parseQuickReplyList(bytes: ByteArray): List<String> {
        val out = mutableListOf<String>()
        fun walk(tlvs: List<HuaweiFraming.Tlv>) {
            for (tlv in tlvs) {
                if (tlv.tag == 0x04) {
                    out += tlv.value.toString(Charsets.UTF_8)
                } else if (tlv.isNested) {
                    walk(HuaweiFraming.decodeTlvs(tlv.value))
                }
            }
        }
        walk(HuaweiFraming.decodeTlvs(bytes))
        return out
    }

    fun buildP2PSend(
        seq: Int,
        srcPkg: String,
        dstPkg: String,
        srcFp: String,
        dstFp: String,
        payload: ByteArray,
    ): HuaweiFraming.Frame {
        val tlvs = listOf(
            HuaweiFraming.Tlv(0x01, byteArrayOf(P2P_CMD_SEND.toByte())),
            HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(seq)),
            HuaweiFraming.Tlv(0x03, srcPkg.toByteArray(Charsets.UTF_8)),
            HuaweiFraming.Tlv(0x04, dstPkg.toByteArray(Charsets.UTF_8)),
            HuaweiFraming.Tlv(0x05, srcFp.toByteArray(Charsets.UTF_8)),
            HuaweiFraming.Tlv(0x06, dstFp.toByteArray(Charsets.UTF_8)),
            HuaweiFraming.Tlv(0x07, payload),
        )
        return HuaweiFraming.Frame(SVC_P2P, CMD_P2P, tlvs)
    }

    fun buildP2PSmsQuickPayload(module: String, innerPayload: ByteArray): ByteArray {
        val wrapped = listOf(
            HuaweiFraming.Tlv(0x01, byteArrayOf(P2P_CMD_SEND.toByte())),
            HuaweiFraming.Tlv(0x03, SRC_PHONE_PKG.toByteArray(Charsets.UTF_8)),
            HuaweiFraming.Tlv(0x04, MODULE_SMS_QUICK.toByteArray(Charsets.UTF_8)),
            HuaweiFraming.Tlv(0x07, innerPayload),
        )
        return HuaweiFraming.encodeTlvs(wrapped)
    }

    fun truncateUtf8(input: String, maxBytes: Int): String {
        if (maxBytes <= 0) return ""
        val bytes = input.toByteArray(Charsets.UTF_8)
        if (bytes.size <= maxBytes) return input
        var end = maxBytes
        while (end > 0 && (bytes[end - 1].toInt() and 0xC0) == 0x80) {
            end--
        }
        val truncated = String(bytes, 0, end, Charsets.UTF_8)
        return if (truncated.length < input.length && end >= 3) {
            truncated.dropLast(1) + "…"
        } else {
            truncated
        }
    }

    private fun intFromValue(v: ByteArray): Int = when {
        v.size >= 4 -> ByteBuffer.wrap(v).int
        v.isNotEmpty() -> v.last().toInt() and 0xFF
        else -> 0
    }

    private fun decodeUtf16(bytes: ByteArray): String =
        String(bytes, Charset.forName("UTF-16BE"))

    private fun shortBeDecode(bytes: ByteArray): Int {
        if (bytes.size < 2) return 0
        return ((bytes[0].toInt() and 0xFF) shl 8) or (bytes[1].toInt() and 0xFF)
    }
}