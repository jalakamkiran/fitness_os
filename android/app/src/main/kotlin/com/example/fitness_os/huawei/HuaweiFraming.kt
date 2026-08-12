package com.example.fitness_os.huawei

/**
 * Clean-room Huawei LPv2 frame encode/decode.
 *
 * Layout from public wire docs (zyv/huawei-lpv2 wiki) + Fitness OS wire-spec:
 * docs/wire-specs/huawei-br-gt5-gate-a.md
 *
 * No AGPL source. Framing only — no auth/crypto.
 */
object HuaweiFraming {
    const val MAGIC: Int = 0x5A
    const val FLAG_NON_SLICED: Int = 0x00
    const val FLAG_SLICE_FIRST: Int = 0x01
    const val FLAG_SLICE_MIDDLE: Int = 0x02
    const val FLAG_SLICE_LAST: Int = 0x03

    private const val HEADER_MIN = 1 + 2 + 1 // magic + length + flags
    private const val CRC_SIZE = 2
    private const val MIN_FRAME = HEADER_MIN + CRC_SIZE

    data class Tlv(
        val tag: Int,
        val value: ByteArray,
    ) {
        val isNested: Boolean get() = (tag and 0x80) != 0

        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is Tlv) return false
            return tag == other.tag && value.contentEquals(other.value)
        }

        override fun hashCode(): Int = 31 * tag + value.contentHashCode()
    }

    data class Frame(
        val serviceId: Int,
        val commandId: Int,
        val tlvs: List<Tlv>,
        val flags: Int = FLAG_NON_SLICED,
        val sliceIndex: Int? = null,
        /** When true, [serviceId]/[commandId]/[tlvs] are unset; [slicePayload] holds raw slice bytes. */
        val isSliceFragment: Boolean = false,
        val slicePayload: ByteArray? = null,
        /**
         * Non-TLV body for FileDownload block responses (`0x2c`/`0x0a` cmd `0x05`).
         * When set, [tlvs] is typically empty (or only the encrypted wrapper before decrypt).
         */
        val rawBody: ByteArray? = null,
    ) {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is Frame) return false
            return serviceId == other.serviceId &&
                commandId == other.commandId &&
                tlvs == other.tlvs &&
                flags == other.flags &&
                sliceIndex == other.sliceIndex &&
                isSliceFragment == other.isSliceFragment &&
                slicePayload.contentEquals(other.slicePayload) &&
                rawBody.contentEquals(other.rawBody)
        }

        override fun hashCode(): Int {
            var r = serviceId
            r = 31 * r + commandId
            r = 31 * r + tlvs.hashCode()
            r = 31 * r + flags
            r = 31 * r + (sliceIndex ?: 0)
            r = 31 * r + isSliceFragment.hashCode()
            r = 31 * r + (slicePayload?.contentHashCode() ?: 0)
            r = 31 * r + (rawBody?.contentHashCode() ?: 0)
            return r
        }
    }

    /** FileDownload block push — body is raw (fileId+offset+unk+data), not TLV. */
    fun isFileDownloadBlock(serviceId: Int, commandId: Int): Boolean =
        commandId == 0x05 && (serviceId == 0x2c || serviceId == 0x0a)

    sealed class ParseResult {
        data class Ok(val frame: Frame, val bytesConsumed: Int) : ParseResult()
        data object IncompleteFrame : ParseResult()
        data class Error(val reason: String) : ParseResult()
    }

    fun encode(frame: Frame): ByteArray {
        require(frame.flags == FLAG_NON_SLICED) {
            "encode supports non-sliced frames only; use encodePossiblySliced for large bodies"
        }
        val body = encodeBody(frame.serviceId, frame.commandId, frame.tlvs)
        return encodeNonSliced(body)
    }

    /**
     * Encode svc+cmd followed by a raw (non-TLV) body — used for unencrypted
     * FileUpload chunk packets (GB serializeFileChunk when no_encrypt=1).
     */
    fun encodeRawBody(serviceId: Int, commandId: Int, rawBody: ByteArray): ByteArray {
        val body = ByteArray(2 + rawBody.size)
        body[0] = (serviceId and 0xFF).toByte()
        body[1] = (commandId and 0xFF).toByte()
        System.arraycopy(rawBody, 0, body, 2, rawBody.size)
        return encodeNonSliced(body)
    }

    /**
     * Encode one or more packets. Uses slicing when [tlvBody] would exceed [sliceSize].
     */
    fun encodePossiblySliced(
        serviceId: Int,
        commandId: Int,
        tlvs: List<Tlv>,
        sliceSize: Int = 0x00F4,
    ): List<ByteArray> {
        val tlvBytes = encodeTlvs(tlvs)
        val headerLength = 5
        val footerLength = 2
        val bodyHeaderLength = 2
        val maxBodySize = sliceSize - headerLength - footerLength
        val totalPayload = bodyHeaderLength + tlvBytes.size
        if (totalPayload <= maxBodySize) {
            return listOf(encode(Frame(serviceId, commandId, tlvs)))
        }

        val packets = ArrayList<ByteArray>()
        var offset = 0
        var sliceFlag = FLAG_SLICE_FIRST
        var index = 0
        while (offset < tlvBytes.size) {
            val isFirst = sliceFlag == FLAG_SLICE_FIRST
            var contentBudget = maxBodySize
            if (isFirst) contentBudget -= 2 // svc+cmd
            val remaining = tlvBytes.size - offset
            val take = minOf(contentBudget, remaining)
            val isLast = offset + take >= tlvBytes.size
            if (isLast) sliceFlag = FLAG_SLICE_LAST

            val chunk = java.io.ByteArrayOutputStream()
            if (isFirst) {
                chunk.write(serviceId and 0xFF)
                chunk.write(commandId and 0xFF)
            }
            chunk.write(tlvBytes, offset, take)
            val sliceBody = chunk.toByteArray()
            // lengthField = len(SLICE-BODY) + 2
            val lengthField = sliceBody.size + 2
            val withoutCrc = ByteArray(1 + 2 + 1 + 1 + sliceBody.size)
            withoutCrc[0] = MAGIC.toByte()
            withoutCrc[1] = ((lengthField shr 8) and 0xFF).toByte()
            withoutCrc[2] = (lengthField and 0xFF).toByte()
            withoutCrc[3] = sliceFlag.toByte()
            withoutCrc[4] = (index and 0xFF).toByte()
            System.arraycopy(sliceBody, 0, withoutCrc, 5, sliceBody.size)
            val crc = crcCcittXmodem(withoutCrc)
            packets.add(
                withoutCrc + byteArrayOf(
                    ((crc shr 8) and 0xFF).toByte(),
                    (crc and 0xFF).toByte(),
                ),
            )
            offset += take
            index++
            sliceFlag = FLAG_SLICE_MIDDLE
        }
        return packets
    }

    fun encodeNonSliced(body: ByteArray): ByteArray {
        require(body.size <= 0xFFFF - 1) { "BODY too large" }
        val lengthField = body.size + 1
        val withoutCrc = ByteArray(HEADER_MIN + body.size)
        withoutCrc[0] = MAGIC.toByte()
        withoutCrc[1] = ((lengthField shr 8) and 0xFF).toByte()
        withoutCrc[2] = (lengthField and 0xFF).toByte()
        withoutCrc[3] = FLAG_NON_SLICED.toByte()
        System.arraycopy(body, 0, withoutCrc, 4, body.size)
        val crc = crcCcittXmodem(withoutCrc)
        return withoutCrc + byteArrayOf(
            ((crc shr 8) and 0xFF).toByte(),
            (crc and 0xFF).toByte(),
        )
    }

    fun encodeBody(serviceId: Int, commandId: Int, tlvs: List<Tlv>): ByteArray {
        val tlvBytes = encodeTlvs(tlvs)
        val body = ByteArray(2 + tlvBytes.size)
        body[0] = (serviceId and 0xFF).toByte()
        body[1] = (commandId and 0xFF).toByte()
        System.arraycopy(tlvBytes, 0, body, 2, tlvBytes.size)
        return body
    }

    fun encodeTlvs(tlvs: List<Tlv>): ByteArray {
        val parts = ArrayList<ByteArray>(tlvs.size)
        var total = 0
        for (tlv in tlvs) {
            val encoded = encodeTlv(tlv)
            parts.add(encoded)
            total += encoded.size
        }
        val out = ByteArray(total)
        var offset = 0
        for (part in parts) {
            System.arraycopy(part, 0, out, offset, part.size)
            offset += part.size
        }
        return out
    }

    fun encodeTlv(tlv: Tlv): ByteArray {
        val tag = tlv.tag and 0xFF
        val lenBytes = encodeVarInt(tlv.value.size)
        val out = ByteArray(1 + lenBytes.size + tlv.value.size)
        out[0] = tag.toByte()
        System.arraycopy(lenBytes, 0, out, 1, lenBytes.size)
        System.arraycopy(tlv.value, 0, out, 1 + lenBytes.size, tlv.value.size)
        return out
    }

    /**
     * Try to parse one frame from [buffer] starting at [offset].
     * Truncated input → [ParseResult.IncompleteFrame] (no crash).
     */
    fun tryParse(buffer: ByteArray, offset: Int = 0): ParseResult {
        if (buffer.size - offset < MIN_FRAME) return ParseResult.IncompleteFrame

        val magic = buffer[offset].toInt() and 0xFF
        if (magic != MAGIC) {
            return ParseResult.Error("invalid magic: 0x${magic.toString(16)}")
        }

        val lengthField = ((buffer[offset + 1].toInt() and 0xFF) shl 8) or
            (buffer[offset + 2].toInt() and 0xFF)
        val flags = buffer[offset + 3].toInt() and 0xFF

        when (flags) {
            FLAG_NON_SLICED -> {
                // lengthField = len(BODY) + 1 → bodyLen = lengthField - 1
                if (lengthField < 1) return ParseResult.Error("invalid length field: $lengthField")
                val bodyLen = lengthField - 1
                val frameLen = HEADER_MIN + bodyLen + CRC_SIZE
                if (buffer.size - offset < frameLen) return ParseResult.IncompleteFrame

                val frameBytes = buffer.copyOfRange(offset, offset + frameLen)
                val expectedCrc = readU16(frameBytes, frameBytes.size - 2)
                val actualCrc = crcCcittXmodem(frameBytes, 0, frameBytes.size - 2)
                if (expectedCrc != actualCrc) {
                    return ParseResult.Error(
                        "crc mismatch: expected=0x${expectedCrc.toString(16)} actual=0x${actualCrc.toString(16)}",
                    )
                }

                val body = frameBytes.copyOfRange(4, 4 + bodyLen)
                return parseBodyFrame(body, FLAG_NON_SLICED, sliceIndex = null, bytesConsumed = frameLen)
            }

            FLAG_SLICE_FIRST, FLAG_SLICE_MIDDLE, FLAG_SLICE_LAST -> {
                // lengthField = len(SLICE-BODY) + 2; header includes flags + index
                if (lengthField < 2) return ParseResult.Error("invalid sliced length: $lengthField")
                val sliceBodyLen = lengthField - 2
                // magic + len(2) + flags + index + sliceBody + crc
                val frameLen = 1 + 2 + 1 + 1 + sliceBodyLen + CRC_SIZE
                if (buffer.size - offset < 5) return ParseResult.IncompleteFrame
                if (buffer.size - offset < frameLen) return ParseResult.IncompleteFrame

                val frameBytes = buffer.copyOfRange(offset, offset + frameLen)
                val expectedCrc = readU16(frameBytes, frameBytes.size - 2)
                val actualCrc = crcCcittXmodem(frameBytes, 0, frameBytes.size - 2)
                if (expectedCrc != actualCrc) {
                    return ParseResult.Error(
                        "crc mismatch: expected=0x${expectedCrc.toString(16)} actual=0x${actualCrc.toString(16)}",
                    )
                }

                val sliceIndex = frameBytes[4].toInt() and 0xFF
                val slicePayload = frameBytes.copyOfRange(5, 5 + sliceBodyLen)
                return ParseResult.Ok(
                    Frame(
                        serviceId = 0,
                        commandId = 0,
                        tlvs = emptyList(),
                        flags = flags,
                        sliceIndex = sliceIndex,
                        isSliceFragment = true,
                        slicePayload = slicePayload,
                    ),
                    bytesConsumed = frameLen,
                )
            }

            else -> return ParseResult.Error("invalid flags/version: 0x${flags.toString(16)}")
        }
    }

    fun decodeTlvs(data: ByteArray): List<Tlv> {
        val out = ArrayList<Tlv>()
        var i = 0
        while (i < data.size) {
            val (tlv, consumed) = decodeTlvAt(data, i)
            out.add(tlv)
            i += consumed
        }
        return out
    }

    fun encodeVarInt(value: Int): ByteArray {
        require(value >= 0) { "VarInt must be non-negative" }
        if (value <= 0x7F) return byteArrayOf(value.toByte())

        // Big-endian 7-bit groups; continuation MSB on all but the last byte.
        var v = value
        val groups = ArrayList<Int>()
        while (true) {
            groups.add(v and 0x7F)
            v = v ushr 7
            if (v == 0) break
        }
        groups.reverse()
        val out = ByteArray(groups.size)
        for (i in groups.indices) {
            val cont = if (i < groups.lastIndex) 0x80 else 0x00
            out[i] = (groups[i] or cont).toByte()
        }
        return out
    }

    /**
     * @return Pair(value, bytesConsumed)
     */
    fun decodeVarInt(data: ByteArray, offset: Int = 0): Pair<Int, Int> {
        var value = 0
        var i = offset
        while (i < data.size) {
            val b = data[i].toInt() and 0xFF
            value = (value shl 7) or (b and 0x7F)
            i++
            if ((b and 0x80) == 0) {
                return value to (i - offset)
            }
            if (i - offset > 5) throw IllegalArgumentException("VarInt too long")
        }
        throw IllegalArgumentException("truncated VarInt")
    }

    /** CRC-16/CCITT-FALSE (XMODEM): poly 0x1021, init 0. */
    fun crcCcittXmodem(data: ByteArray, start: Int = 0, length: Int = data.size - start): Int {
        var crc = 0
        val end = start + length
        for (i in start until end) {
            crc = crc xor ((data[i].toInt() and 0xFF) shl 8)
            repeat(8) {
                crc = if ((crc and 0x8000) != 0) {
                    ((crc shl 1) xor 0x1021) and 0xFFFF
                } else {
                    (crc shl 1) and 0xFFFF
                }
            }
        }
        return crc and 0xFFFF
    }

    private fun parseBodyFrame(
        body: ByteArray,
        flags: Int,
        sliceIndex: Int?,
        bytesConsumed: Int,
    ): ParseResult {
        if (body.size < 2) {
            return ParseResult.Error("BODY too short for SS/CC")
        }
        val serviceId = body[0].toInt() and 0xFF
        val commandId = body[1].toInt() and 0xFF
        val payload = body.copyOfRange(2, body.size)
        // FileDownload blocks: raw body unless wrapped as encrypted 7C/7D/7E TLVs.
        if (isFileDownloadBlock(serviceId, commandId) && !isEncryptedTlvPrefix(payload)) {
            return ParseResult.Ok(
                Frame(
                    serviceId = serviceId,
                    commandId = commandId,
                    tlvs = emptyList(),
                    flags = flags,
                    sliceIndex = sliceIndex,
                    rawBody = payload,
                ),
                bytesConsumed = bytesConsumed,
            )
        }
        val tlvs = try {
            decodeTlvs(payload)
        } catch (e: Exception) {
            return ParseResult.Error("TLV decode failed: ${e.message}")
        }
        return ParseResult.Ok(
            Frame(
                serviceId = serviceId,
                commandId = commandId,
                tlvs = tlvs,
                flags = flags,
                sliceIndex = sliceIndex,
            ),
            bytesConsumed = bytesConsumed,
        )
    }

    /** Encrypted TLV prefix: tag 0x7C, len 0x01, value 0x01. */
    private fun isEncryptedTlvPrefix(payload: ByteArray): Boolean =
        payload.size >= 3 &&
            (payload[0].toInt() and 0xFF) == 0x7C &&
            (payload[1].toInt() and 0xFF) == 0x01 &&
            (payload[2].toInt() and 0xFF) == 0x01

    private fun decodeTlvAt(data: ByteArray, offset: Int): Pair<Tlv, Int> {
        if (offset >= data.size) throw IllegalArgumentException("truncated TLV")
        val tag = data[offset].toInt() and 0xFF
        val (len, lenSize) = decodeVarInt(data, offset + 1)
        val valueStart = offset + 1 + lenSize
        val valueEnd = valueStart + len
        if (valueEnd > data.size) throw IllegalArgumentException("truncated TLV value")
        val value = data.copyOfRange(valueStart, valueEnd)
        return Tlv(tag, value) to (valueEnd - offset)
    }

    private fun readU16(data: ByteArray, offset: Int): Int {
        return ((data[offset].toInt() and 0xFF) shl 8) or (data[offset + 1].toInt() and 0xFF)
    }
}
