package com.example.fitness_os.huawei

import java.nio.ByteBuffer
import java.security.SecureRandom
import java.util.concurrent.atomic.AtomicLong
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Clean-room LPv2 session-packet encryption (tags 0x7C / 0x7D / 0x7E).
 *
 * Wire layout matches public LPv2 community docs: encrypted bodies replace
 * plaintext TLVs with encryption-flag + IV + ciphertext. Crypto uses standard
 * AES-GCM (HiChain3) or AES-CBC — not copied from AGPL sources.
 */
object HuaweiPacketCrypto {
    const val TAG_ENCRYPTION = 0x7C
    const val TAG_IV = 0x7D
    const val TAG_CIPHERTEXT = 0x7E

    /** Result code used in many Huawei status replies (100000). */
    const val RESULT_OK = 100_000

    fun useGcm(deviceSupportType: Int, encryptMethod: Int): Boolean =
        encryptMethod == 0x01 || deviceSupportType == 0x04

    fun nextIv(deviceSupportType: Int, counter: AtomicLong): ByteArray {
        return if (deviceSupportType == 0x04) {
            ByteArray(16).also { SecureRandom().nextBytes(it) }
        } else {
            var c = counter.incrementAndGet()
            if (c == 0xFFFFFFFFL || c <= 0L) {
                c = 1L
                counter.set(1L)
            }
            val iv = ByteArray(16)
            SecureRandom().nextBytes(iv)
            // Counter occupies the last 4 bytes (big-endian), matching public LPv2 IV layout.
            iv[12] = ((c shr 24) and 0xFF).toByte()
            iv[13] = ((c shr 16) and 0xFF).toByte()
            iv[14] = ((c shr 8) and 0xFF).toByte()
            iv[15] = (c and 0xFF).toByte()
            iv
        }
    }

    fun encryptTlvs(
        plainTlvs: List<HuaweiFraming.Tlv>,
        key: ByteArray,
        iv: ByteArray,
        useGcm: Boolean,
    ): List<HuaweiFraming.Tlv> {
        return encryptRaw(HuaweiFraming.encodeTlvs(plainTlvs), key, iv, useGcm)
    }

    /**
     * Encrypt arbitrary payload bytes into tags 0x7C/0x7D/0x7E.
     * Used for FileUpload chunk bodies (GB encryptRaw) which are not TLV lists.
     */
    fun encryptRaw(
        plain: ByteArray,
        key: ByteArray,
        iv: ByteArray,
        useGcm: Boolean,
    ): List<HuaweiFraming.Tlv> {
        val cipherBytes = encrypt(plain, key, iv, useGcm)
        return listOf(
            HuaweiFraming.Tlv(TAG_ENCRYPTION, byteArrayOf(0x01)),
            HuaweiFraming.Tlv(TAG_IV, iv),
            HuaweiFraming.Tlv(TAG_CIPHERTEXT, cipherBytes),
        )
    }

    fun decryptIfNeeded(
        frame: HuaweiFraming.Frame,
        key: ByteArray,
        useGcm: Boolean,
    ): HuaweiFraming.Frame {
        val enc = frame.tlvs.firstOrNull { it.tag == TAG_ENCRYPTION }?.value?.firstOrNull()?.toInt()?.and(0xFF)
        if (enc != 0x01) return frame
        val iv = frame.tlvs.firstOrNull { it.tag == TAG_IV }?.value
            ?: throw IllegalArgumentException("encrypted frame missing IV")
        val cipher = frame.tlvs.firstOrNull { it.tag == TAG_CIPHERTEXT }?.value
            ?: throw IllegalArgumentException("encrypted frame missing ciphertext")
        val plain = decrypt(cipher, key, iv, useGcm)
        return frame.copy(tlvs = HuaweiFraming.decodeTlvs(plain))
    }

    /**
     * Fallbacks when primary GCM/CBC decrypt fails:
     * - strip a trailing 0x00 on ciphertext (seen in GB TLV notes)
     * - AES-128 using first 16 bytes of the 32-byte session key
     * - opposite cipher mode (GCM↔CBC)
     *
     * Returns decrypted frame + which fallback worked, or null.
     */
    fun decryptWithFallbacks(
        frame: HuaweiFraming.Frame,
        key: ByteArray,
        preferGcm: Boolean,
    ): Pair<HuaweiFraming.Frame, String>? {
        val iv = frame.tlvs.firstOrNull { it.tag == TAG_IV }?.value ?: return null
        val cipher = frame.tlvs.firstOrNull { it.tag == TAG_CIPHERTEXT }?.value ?: return null
        val variants = ArrayList<Triple<ByteArray, ByteArray, String>>()
        fun add(k: ByteArray, ct: ByteArray, label: String) {
            variants.add(Triple(k, ct, label))
        }
        add(key, cipher, if (preferGcm) "gcm" else "cbc")
        if (cipher.isNotEmpty() && cipher.last() == 0.toByte()) {
            add(key, cipher.copyOf(cipher.size - 1), "trim-null")
        }
        if (key.size >= 16) {
            add(key.copyOf(16), cipher, "aes128")
            if (cipher.isNotEmpty() && cipher.last() == 0.toByte()) {
                add(key.copyOf(16), cipher.copyOf(cipher.size - 1), "aes128+trim")
            }
        }
        for ((k, ct, label) in variants) {
            for (gcm in listOf(preferGcm, !preferGcm)) {
                try {
                    val plain = decrypt(ct, k, iv, gcm)
                    val mode = if (gcm) "gcm" else "cbc"
                    return frame.copy(tlvs = HuaweiFraming.decodeTlvs(plain)) to "$label/$mode"
                } catch (_: Exception) {
                }
            }
        }
        return null
    }

    fun isEncrypted(frame: HuaweiFraming.Frame): Boolean =
        frame.tlvs.any { it.tag == TAG_ENCRYPTION && it.value.firstOrNull()?.toInt()?.and(0xFF) == 0x01 }

    fun intBe(value: Int): ByteArray = ByteBuffer.allocate(4).putInt(value).array()

    fun shortBe(value: Int): ByteArray = ByteBuffer.allocate(2).putShort(value.toShort()).array()

    /**
     * Set-time TLV payload: unix seconds + timezone offset encoding.
     * Zone byte0 = hours (bit7 set if negative UTC offset), byte1 = minutes.
     */
    fun timeAndZoneTlvs(nowMillis: Long = System.currentTimeMillis()): List<HuaweiFraming.Tlv> {
        val cal = java.util.Calendar.getInstance()
        cal.timeInMillis = nowMillis
        val (unix, zoneShort) = unixAndZoneShort(cal)
        return listOf(
            HuaweiFraming.Tlv(0x01, intBe(unix)),
            HuaweiFraming.Tlv(0x02, shortBe(zoneShort)),
        )
    }

    /**
     * SetTimeZoneId (`1:0x32`) — unix + zone short + IANA zone id string.
     * Same time/zone encoding as set-time, plus tag 0x03 zone id.
     */
    fun timeZoneIdTlvs(nowMillis: Long = System.currentTimeMillis()): List<HuaweiFraming.Tlv> {
        val cal = java.util.Calendar.getInstance()
        cal.timeInMillis = nowMillis
        val (unix, zoneShort) = unixAndZoneShort(cal)
        val zoneId = cal.timeZone.id.toByteArray(Charsets.UTF_8)
        return listOf(
            HuaweiFraming.Tlv(0x01, intBe(unix)),
            HuaweiFraming.Tlv(0x02, shortBe(zoneShort)),
            HuaweiFraming.Tlv(0x03, zoneId),
        )
    }

    private fun unixAndZoneShort(cal: java.util.Calendar): Pair<Int, Int> {
        val zoneRawOffsetSec =
            (cal.get(java.util.Calendar.ZONE_OFFSET) + cal.get(java.util.Calendar.DST_OFFSET)) / 1000
        val zoneHours = if (zoneRawOffsetSec < 0) {
            (-zoneRawOffsetSec / 3600) + 128
        } else {
            zoneRawOffsetSec / 3600
        }
        val zoneMinutes = (kotlin.math.abs(zoneRawOffsetSec) / 60) % 60
        val unix = (cal.timeInMillis / 1000L).toInt()
        val zoneShort = ((zoneHours and 0xFF) shl 8) or (zoneMinutes and 0xFF)
        return unix to zoneShort
    }

    private fun encrypt(data: ByteArray, key: ByteArray, iv: ByteArray, useGcm: Boolean): ByteArray {
        return if (useGcm) {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, iv))
            cipher.doFinal(data)
        } else {
            val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
            cipher.doFinal(data)
        }
    }

    private fun decrypt(data: ByteArray, key: ByteArray, iv: ByteArray, useGcm: Boolean): ByteArray {
        return if (useGcm) {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, iv))
            cipher.doFinal(data)
        } else {
            val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
            cipher.doFinal(data)
        }
    }
}
