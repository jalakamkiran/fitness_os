package com.example.fitness_os.huawei

import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Clean-room Normal (non-HiChain) LPv2 auth crypto.
 *
 * Independently reimplemented from the MIT-licensed public LPv2 reference
 * (zyv/huawei-lpv2 protocol.py) — not from Gadgetbridge AGPL sources.
 */
object HuaweiNormalAuth {
    enum class AuthVersion(val code: Int) {
        V1(1),
        V2(2),
        V3(3);

        companion object {
            fun fromCode(code: Int): AuthVersion? = entries.find { it.code == code }
        }
    }

    private val DIGEST_SECRETS = mapOf(
        AuthVersion.V1 to "70FB6C24035FDB552F38898AEEDE3F69",
        AuthVersion.V2 to "93ACDEF76ACB09857DBFE5261AABCD78",
        AuthVersion.V3 to "9C2763A9CCE134766DE3FF6118200553",
    )

    private val SECRET_KEYS = mapOf(
        AuthVersion.V1 to (
            "6F756A796D777134636C763933373879" to "6231306A676664397937767375646139"
            ),
        AuthVersion.V2 to (
            "555386FC632007AA86493522B86AE25C" to "33079BC57A886D3CF56137096F228000"
            ),
        AuthVersion.V3 to (
            "555386FC632007AA86493522B86AE25C" to "33079BC57A886D3CF56137096F228000"
            ),
    )

    private const val MESSAGE_CHALLENGE = "0100"
    private const val MESSAGE_RESPONSE = "0110"
    const val NONCE_LENGTH = 16
    private const val AES_KEY_SIZE = 16

    fun digestSecretKey(authVersion: AuthVersion): ByteArray =
        DIGEST_SECRETS.getValue(authVersion).hexToBytes()

    fun generateNonce(): ByteArray = ByteArray(NONCE_LENGTH).also { SecureRandom().nextBytes(it) }

    /**
     * Phone → watch challenge digest.
     *
     * Public Wireshark LPv2 dissector (MartinJM) uses MESSAGE_CHALLENGE (`0100`) for
     * the outbound auth request; response verification uses MESSAGE_RESPONSE (`0110`).
     * MIT helpers currently call both with RESPONSE — that mismatch yields watch
     * rejection (observed as result 100004 on GT5-A07).
     */
    fun digestChallenge(
        authVersion: AuthVersion,
        clientNonce: ByteArray,
        serverNonce: ByteArray,
    ): ByteArray = computeDigest(authVersion, MESSAGE_CHALLENGE, clientNonce, serverNonce)

    fun digestResponse(
        authVersion: AuthVersion,
        clientNonce: ByteArray,
        serverNonce: ByteArray,
    ): ByteArray = computeDigest(authVersion, MESSAGE_RESPONSE, clientNonce, serverNonce)

    fun createSecretKey(authVersion: AuthVersion, macAddress: String): ByteArray {
        val macAddressKey = (macAddress.replace(":", "") + "0000").toByteArray(Charsets.US_ASCII)
        val (leftHex, rightHex) = SECRET_KEYS.getValue(authVersion)
        val left = leftHex.hexToBytes()
        val right = rightHex.hexToBytes()

        val mixed = ByteArray(left.size) { i ->
            (
                ((left[i].toInt() and 0xFF) shl 4) xor (right[i].toInt() and 0xFF)
                ).and(0xFF).toByte()
        }
        val mixedHash = sha256(mixed)
        val finalMixed = ByteArray(minOf(mixedHash.size, macAddressKey.size)) { i ->
            (
                ((mixedHash[i].toInt() and 0xFF) ushr 6) xor (macAddressKey[i].toInt() and 0xFF)
                ).and(0xFF).toByte()
        }
        return sha256(finalMixed).copyOf(AES_KEY_SIZE)
    }

    fun createBondingKey(
        authVersion: AuthVersion,
        deviceMac: String,
        key: ByteArray,
        iv: ByteArray,
    ): ByteArray = encryptAesCbc(key, createSecretKey(authVersion, deviceMac), iv)

    fun encryptAesCbc(data: ByteArray, key: ByteArray, iv: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
        return cipher.doFinal(data)
    }

    private fun computeDigest(
        authVersion: AuthVersion,
        message: String,
        clientNonce: ByteArray,
        serverNonce: ByteArray,
    ): ByteArray {
        val completeNonce = serverNonce + clientNonce
        val secret = (DIGEST_SECRETS.getValue(authVersion) + message).hexToBytes()
        val inner = hmacSha256(secret, completeNonce)
        return hmacSha256(inner, completeNonce)
    }

    private fun hmacSha256(key: ByteArray, msg: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(msg)
    }

    private fun sha256(data: ByteArray): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(data)

    private fun String.hexToBytes(): ByteArray {
        val cleaned = replace(" ", "")
        require(cleaned.length % 2 == 0) { "odd hex length" }
        return ByteArray(cleaned.length / 2) { i ->
            cleaned.substring(i * 2, i * 2 + 2).toInt(16).toByte()
        }
    }
}
