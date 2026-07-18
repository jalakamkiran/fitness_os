package com.example.fitness_os.huawei

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class HuaweiNormalAuthTest {
    @Test
    fun challengeAndResponseDigestsDiffer() {
        val client = ByteArray(16) { it.toByte() }
        val server = ByteArray(16) { (255 - it).toByte() }
        val challenge = HuaweiNormalAuth.digestChallenge(
            HuaweiNormalAuth.AuthVersion.V1,
            client,
            server,
        )
        val response = HuaweiNormalAuth.digestResponse(
            HuaweiNormalAuth.AuthVersion.V1,
            client,
            server,
        )
        assertEquals(32, challenge.size)
        assertEquals(32, response.size)
        // MESSAGE_CHALLENGE (0100) vs MESSAGE_RESPONSE (0110)
        assert(!challenge.contentEquals(response))
    }

    @Test
    fun secretKeyIs16Bytes() {
        val key = HuaweiNormalAuth.createSecretKey(
            HuaweiNormalAuth.AuthVersion.V1,
            "AA:BB:CC:DD:EE:FF",
        )
        assertEquals(16, key.size)
    }

    @Test
    fun bondingKeyEncrypts() {
        val key = HuaweiNormalAuth.generateNonce()
        val iv = HuaweiNormalAuth.generateNonce()
        val bonding = HuaweiNormalAuth.createBondingKey(
            HuaweiNormalAuth.AuthVersion.V1,
            "AA:BB:CC:DD:EE:FF",
            key,
            iv,
        )
        assertNotNull(bonding)
        // PKCS5 pad → at least 16 bytes
        assert(bonding.size >= 16)
    }

    @Test
    fun authVersionFromOwnerCapture() {
        // Owner link-params ServerNonce TLV started with 00 01 → V1
        assertEquals(
            HuaweiNormalAuth.AuthVersion.V1,
            HuaweiNormalAuth.AuthVersion.fromCode(1),
        )
    }
}
