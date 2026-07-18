package com.example.fitness_os.huawei

import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Clean-room Huawei wearable HiChain ISO exchange (cmd 0x28).
 *
 * Wire JSON field names / HKDF info strings match public OpenHarmony HiChain
 * ISO exchange conventions. Crypto uses only standard primitives
 * (SHA-256, HMAC-SHA256, HKDF-SHA256, AES-GCM). Not copied from AGPL sources.
 */
object HuaweiHiChain {
    const val CMD = 0x28
    const val CMD_PIN = 0x2C

    /** Well-known Health group id used on the wire for wearable companions. */
    const val GROUP_ID =
        "7B0BC0CBCE474F6C238D9661C63400B797B166EA7849B3A370FC73A9A236E989"

    private const val INFO_SESSION = "hichain_iso_session_key"
    private const val INFO_EXCHANGE = "hichain_iso_exchange"
    private const val INFO_RESULT = "hichain_iso_result"
    private const val INFO_RETURN = "hichain_return_key"

    data class Step1Peer(
        val isoSalt: ByteArray,
        val peerAuthId: ByteArray,
        val token: ByteArray,
    )

    data class BuiltPacket(
        val tlvs: List<HuaweiFraming.Tlv>,
        val sliced: Boolean = true,
    )

    fun decryptPin(
        ciphertext: ByteArray,
        iv: ByteArray,
        authVersion: HuaweiNormalAuth.AuthVersion,
        encryptMethod: Int,
    ): ByteArray {
        val key = HuaweiNormalAuth.digestSecretKey(authVersion)
        return if (encryptMethod == 1) {
            decryptAesGcm(ciphertext, key, iv, aad = null)
        } else {
            decryptAesCbc(ciphertext, key, iv)
        }
    }

    fun pskFromPin(pinBytes: ByteArray, seed: ByteArray): ByteArray {
        val pinHexUtf8 = pinBytes.toHex().toByteArray(Charsets.UTF_8)
        val key = sha256(pinHexUtf8)
        return hmacSha256(key, seed)
    }

    fun buildStepOne(
        operationCode: Int,
        requestId: Long,
        selfAuthId: ByteArray,
        randSelf: ByteArray,
        seed: ByteArray,
    ): BuiltPacket {
        val messageId = messageIdFor(operationCode, step = 1)
        val payload = basePayload().apply {
            put("isoSalt", randSelf.toHex())
            put("peerAuthId", selfAuthId.toHex())
            put("operationCode", operationCode)
            put("seed", seed.toHex())
            put("peerUserType", 0)
            if (operationCode == 0x02) {
                put("pkgName", "com.huawei.devicegroupmanage")
                put("serviceType", GROUP_ID)
                put("keyLength", 0x20)
            }
        }
        val value = envelope(operationCode, requestId, selfAuthId, messageId, payload).apply {
            if (operationCode == 0x02) put("isDeviceLevel", false)
        }
        return packet(value, operationCode, requestId)
    }

    fun buildStepTwo(
        operationCode: Int,
        requestId: Long,
        selfAuthId: ByteArray,
        selfToken: ByteArray,
    ): BuiltPacket {
        val messageId = messageIdFor(operationCode, step = 2)
        val payload = basePayload().apply {
            put("peerAuthId", selfAuthId.toHex())
            put("token", selfToken.toHex())
        }
        val value = envelope(operationCode, requestId, selfAuthId, messageId, payload).apply {
            if (operationCode == 0x02) put("isDeviceLevel", false)
        }
        return packet(value, operationCode, requestId)
    }

    fun buildStepThree(
        operationCode: Int,
        requestId: Long,
        selfAuthId: ByteArray,
        nonce: ByteArray,
        encData: ByteArray,
    ): BuiltPacket {
        val messageId = messageIdFor(operationCode, step = 3)
        val payload = basePayload().apply {
            put("nonce", nonce.toHex())
            put("encData", encData.toHex())
        }
        val value = envelope(operationCode, requestId, selfAuthId, messageId, payload)
        return packet(value, operationCode, requestId)
    }

    fun buildStepFour(
        operationCode: Int,
        requestId: Long,
        selfAuthId: ByteArray,
        nonce: ByteArray,
        encResult: ByteArray,
        /**
         * Wire message step before op-flag. Bind result must use 3 (→ 0x13) because
         * the client advances from step 3→4 inside one request; auth result uses 4.
         */
        messageStep: Int = 4,
    ): BuiltPacket {
        val messageId = messageIdFor(operationCode, messageStep)
        val payload = basePayload().apply {
            put("nonce", nonce.toHex())
            put("encResult", encResult.toHex())
            put("operationCode", operationCode)
        }
        val value = envelope(operationCode, requestId, selfAuthId, messageId, payload)
        return packet(value, operationCode, requestId)
    }

    fun parsePeerStep(frame: HuaweiFraming.Frame): PeerStep {
        val type = frame.tlvs.firstOrNull { it.tag == 0x04 }?.value?.firstOrNull()?.toInt()?.and(0xFF) ?: 0
        if (type != 0) {
            return PeerStep.Finished(frame.tlvs.firstOrNull { it.tag == 0x01 }?.value?.toString(Charsets.UTF_8))
        }
        val jsonStr = frame.tlvs.firstOrNull { it.tag == 0x01 }?.value?.toString(Charsets.UTF_8)
            ?: throw IllegalStateException("HiChain response missing JSON TLV")
        val value = JSONObject(jsonStr)
        val payload = value.getJSONObject("payload")
        if (payload.has("errorCode") && payload.getInt("errorCode") != 0) {
            throw IllegalStateException("HiChain errorCode=${payload.getInt("errorCode")}")
        }
        return when {
            payload.has("isoSalt") -> PeerStep.Step1(
                Step1Peer(
                    isoSalt = payload.getString("isoSalt").hexToBytes(),
                    peerAuthId = payload.getString("peerAuthId").hexToBytes(),
                    token = payload.getString("token").hexToBytes(),
                ),
            )
            payload.has("returnCodeMac") -> PeerStep.Step2(
                payload.getString("returnCodeMac").hexToBytes(),
            )
            payload.has("encAuthToken") -> PeerStep.Step3(
                nonce = payload.getString("nonce").hexToBytes(),
                encAuthToken = payload.getString("encAuthToken").hexToBytes(),
            )
            else -> throw IllegalStateException(
                "Unrecognized HiChain payload",
            )
        }
    }

    sealed class PeerStep {
        data class Step1(val data: Step1Peer) : PeerStep()
        data class Step2(val returnCodeMac: ByteArray) : PeerStep()
        data class Step3(val nonce: ByteArray, val encAuthToken: ByteArray) : PeerStep()
        data class Finished(val data: String?) : PeerStep()
    }

    fun verifyPeerToken(
        psk: ByteArray,
        randPeer: ByteArray,
        randSelf: ByteArray,
        authIdSelf: ByteArray,
        authIdPeer: ByteArray,
        peerToken: ByteArray,
    ): Boolean {
        val message = ByteBuffer.allocate(
            randPeer.size + randSelf.size + authIdSelf.size + authIdPeer.size,
        )
            .put(randPeer).put(randSelf).put(authIdSelf).put(authIdPeer)
            .array()
        return hmacSha256(psk, message).contentEquals(peerToken)
    }

    fun selfToken(
        psk: ByteArray,
        randSelf: ByteArray,
        randPeer: ByteArray,
        authIdSelf: ByteArray,
        authIdPeer: ByteArray,
    ): ByteArray {
        val message = ByteBuffer.allocate(
            randPeer.size + randSelf.size + authIdSelf.size + authIdPeer.size,
        )
            .put(randSelf).put(randPeer).put(authIdPeer).put(authIdSelf)
            .array()
        return hmacSha256(psk, message)
    }

    fun verifyReturnCodeMac(psk: ByteArray, returnCodeMac: ByteArray): Boolean {
        val expected = hmacSha256(psk, byteArrayOf(0, 0, 0, 0))
        return expected.contentEquals(returnCodeMac)
    }

    fun sessionKey(psk: ByteArray, randSelf: ByteArray, randPeer: ByteArray): ByteArray {
        val salt = randSelf + randPeer
        return hkdfSha256(psk, salt, INFO_SESSION.toByteArray(Charsets.UTF_8), 32)
    }

    fun encryptExchangeChallenge(sessionKey: ByteArray, challenge: ByteArray, nonce: ByteArray): ByteArray =
        encryptAesGcm(challenge, sessionKey, nonce, INFO_EXCHANGE.toByteArray(Charsets.UTF_8))

    fun decryptAuthToken(
        sessionKey: ByteArray,
        encAuthToken: ByteArray,
        nonce: ByteArray,
        challenge: ByteArray,
    ): ByteArray = decryptAesGcm(encAuthToken, sessionKey, nonce, challenge)

    fun encryptResult(sessionKey: ByteArray, nonce: ByteArray): ByteArray =
        encryptAesGcm(byteArrayOf(0, 0, 0, 0), sessionKey, nonce, INFO_RESULT.toByteArray(Charsets.UTF_8))

    fun returnKey(sessionKey: ByteArray, randSelf: ByteArray, randPeer: ByteArray): ByteArray {
        val salt = randSelf + randPeer
        return hkdfSha256(sessionKey, salt, INFO_RETURN.toByteArray(Charsets.UTF_8), 32)
    }

    fun random(size: Int): ByteArray = ByteArray(size).also { SecureRandom().nextBytes(it) }

    private fun messageIdFor(operationCode: Int, step: Int): Int =
        if (operationCode == 0x02) step or 0x10 else step

    private fun basePayload(): JSONObject = JSONObject().put(
        "version",
        JSONObject()
            .put("minVersion", "1.0.0")
            .put("currentVersion", "2.0.16"),
    )

    private fun envelope(
        operationCode: Int,
        requestId: Long,
        selfAuthId: ByteArray,
        messageId: Int,
        payload: JSONObject,
    ): JSONObject {
        val value = JSONObject()
            .put("authForm", 0)
            .put("payload", payload)
            .put("groupAndModuleVersion", "2.0.1")
            .put("message", messageId)
        if (operationCode == 0x01) {
            val idStr = String(selfAuthId, StandardCharsets.UTF_8)
            value
                .put("requestId", requestId.toString())
                .put("groupId", GROUP_ID)
                .put("groupName", "health_group_name")
                .put("groupOp", 2)
                .put("groupType", 256)
                .put("peerDeviceId", idStr)
                .put("connDeviceId", idStr)
                .put("appId", "com.huawei.health")
                .put("ownerName", "")
        }
        return value
    }

    private fun packet(value: JSONObject, operationCode: Int, requestId: Long): BuiltPacket {
        val reqId = ByteBuffer.allocate(8).putLong(requestId).array()
        return BuiltPacket(
            tlvs = listOf(
                HuaweiFraming.Tlv(0x01, value.toString().toByteArray(Charsets.UTF_8)),
                HuaweiFraming.Tlv(0x02, byteArrayOf(operationCode.toByte())),
                HuaweiFraming.Tlv(0x03, reqId),
            ),
            sliced = true,
        )
    }

    private fun sha256(data: ByteArray): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(data)

    private fun hmacSha256(key: ByteArray, msg: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(msg)
    }

    private fun hkdfSha256(ikm: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray {
        val prk = hmacSha256(if (salt.isEmpty()) ByteArray(32) else salt, ikm)
        var t = ByteArray(0)
        val out = ByteArrayOutputGrow(length)
        var counter = 1
        while (out.size < length) {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(prk, "HmacSHA256"))
            mac.update(t)
            mac.update(info)
            mac.update(counter.toByte())
            t = mac.doFinal()
            out.write(t)
            counter++
        }
        return out.toByteArray().copyOf(length)
    }

    private fun encryptAesGcm(data: ByteArray, key: ByteArray, iv: ByteArray, aad: ByteArray?): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, iv))
        if (aad != null) cipher.updateAAD(aad)
        return cipher.doFinal(data)
    }

    private fun decryptAesGcm(data: ByteArray, key: ByteArray, iv: ByteArray, aad: ByteArray?): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, iv))
        if (aad != null) cipher.updateAAD(aad)
        return cipher.doFinal(data)
    }

    private fun decryptAesCbc(data: ByteArray, key: ByteArray, iv: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
        return cipher.doFinal(data)
    }

    private class ByteArrayOutputGrow(private val hint: Int) {
        private val buf = java.io.ByteArrayOutputStream(hint)
        val size: Int get() = buf.size()
        fun write(b: ByteArray) = buf.write(b)
        fun toByteArray(): ByteArray = buf.toByteArray()
    }

    private fun ByteArray.toHex(): String = joinToString("") { "%02X".format(it) }

    private fun String.hexToBytes(): ByteArray {
        val cleaned = replace(" ", "")
        require(cleaned.length % 2 == 0)
        return ByteArray(cleaned.length / 2) { i ->
            cleaned.substring(i * 2, i * 2 + 2).toInt(16).toByte()
        }
    }
}
