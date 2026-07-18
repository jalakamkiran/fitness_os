package com.example.fitness_os.huawei

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HuaweiFitnessDataEnableTest {

    @Test
    fun enableAutoTracking_threeResultOk_allArmed() {
        val ok = resultOkFrame()
        val queue = ArrayDeque(
            listOf(
                ok.copy(commandId = HuaweiFitnessDataSync.CMD_TRUSLEEP_ENABLE),
                ok.copy(commandId = HuaweiFitnessDataSync.CMD_AUTO_HR_ENABLE),
                ok.copy(commandId = HuaweiFitnessDataSync.CMD_AUTO_SPO2_ENABLE),
            ),
        )
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, cmd, _ ->
                val next = queue.removeFirstOrNull()
                assertEquals(cmd, next?.commandId)
                next
            },
        )
        val result = sync.enableAutoTracking()
        assertEquals("ok", result["status"])
        assertEquals("all_armed", result["overall"])
        @Suppress("UNCHECKED_CAST")
        val features = result["features"] as List<Map<String, Any?>>
        assertEquals(3, features.size)
        assertTrue(features.all { it["outcome"] == "armed" })
        assertFalse(result.containsKey("sleepSessions"))
        assertFalse(result.containsKey("dailyHrSamples"))
    }

    @Test
    fun enableAutoTracking_nonResultOkFrame_failedNotArmed() {
        val junk = HuaweiFraming.Frame(
            HuaweiFitnessDataSync.SVC,
            HuaweiFitnessDataSync.CMD_AUTO_HR_ENABLE,
            listOf(HuaweiFraming.Tlv(0x01, byteArrayOf(0x01))),
        )
        val ok = resultOkFrame()
        val queue = ArrayDeque(
            listOf(
                ok.copy(commandId = HuaweiFitnessDataSync.CMD_TRUSLEEP_ENABLE),
                junk,
                ok.copy(commandId = HuaweiFitnessDataSync.CMD_AUTO_SPO2_ENABLE),
            ),
        )
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, _, _ -> queue.removeFirstOrNull() },
        )
        val result = sync.enableAutoTracking()
        assertEquals("partial", result["overall"])
        @Suppress("UNCHECKED_CAST")
        val features = result["features"] as List<Map<String, Any?>>
        assertEquals("armed", featureOutcome(features, "trusleep"))
        assertEquals("failed", featureOutcome(features, "auto_hr"))
        assertEquals("armed", featureOutcome(features, "auto_spo2"))
    }

    @Test
    fun enableAutoTracking_timeoutWhileUp_continuesRemaining() {
        val ok = resultOkFrame()
        val queue = ArrayDeque(
            listOf(
                ok.copy(commandId = HuaweiFitnessDataSync.CMD_TRUSLEEP_ENABLE),
                null, // auto_hr timeout
                ok.copy(commandId = HuaweiFitnessDataSync.CMD_AUTO_SPO2_ENABLE),
            ),
        )
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, _, _ -> queue.removeFirstOrNull() },
            isConnected = { true },
        )
        val result = sync.enableAutoTracking()
        assertEquals("partial", result["overall"])
        @Suppress("UNCHECKED_CAST")
        val features = result["features"] as List<Map<String, Any?>>
        assertEquals("armed", featureOutcome(features, "trusleep"))
        assertEquals("timed_out", featureOutcome(features, "auto_hr"))
        assertEquals("armed", featureOutcome(features, "auto_spo2"))
    }

    @Test
    fun enableAutoTracking_disconnectAfterFirst_stopsRemainderFailed() {
        val ok = resultOkFrame()
        var connected = true
        val queue = ArrayDeque(
            listOf(ok.copy(commandId = HuaweiFitnessDataSync.CMD_TRUSLEEP_ENABLE)),
        )
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, _, _ ->
                val next = queue.removeFirstOrNull()
                connected = false
                next
            },
            isConnected = { connected },
        )
        val result = sync.enableAutoTracking()
        assertEquals("partial", result["overall"])
        @Suppress("UNCHECKED_CAST")
        val features = result["features"] as List<Map<String, Any?>>
        assertEquals("armed", featureOutcome(features, "trusleep"))
        assertEquals("failed", featureOutcome(features, "auto_hr"))
        assertEquals("failed", featureOutcome(features, "auto_spo2"))
        assertTrue(queue.isEmpty())
    }

    @Test
    fun enableAutoTracking_nackResultCode_failed() {
        val nack = HuaweiFraming.Frame(
            HuaweiFitnessDataSync.SVC,
            HuaweiFitnessDataSync.CMD_AUTO_SPO2_ENABLE,
            listOf(HuaweiFraming.Tlv(0x7F, HuaweiPacketCrypto.intBe(100_001))),
        )
        val ok = resultOkFrame()
        val queue = ArrayDeque(
            listOf(
                ok.copy(commandId = HuaweiFitnessDataSync.CMD_TRUSLEEP_ENABLE),
                ok.copy(commandId = HuaweiFitnessDataSync.CMD_AUTO_HR_ENABLE),
                nack,
            ),
        )
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, _, _ -> queue.removeFirstOrNull() },
        )
        val result = sync.enableAutoTracking()
        assertEquals("partial", result["overall"])
        @Suppress("UNCHECKED_CAST")
        val features = result["features"] as List<Map<String, Any?>>
        assertEquals("failed", featureOutcome(features, "auto_spo2"))
        assertEquals(100_001, features.first { it["id"] == "auto_spo2" }["resultCode"])
    }

    @Test
    fun enableAutoTracking_capAbsent_skippedWithoutSend() {
        val ok = resultOkFrame()
        val sent = mutableListOf<Int>()
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { req, _, cmd, _ ->
                sent.add(cmd)
                ok.copy(commandId = cmd)
            },
        )
        val result = sync.enableAutoTracking(
            supportedCmds = setOf(
                HuaweiFitnessDataSync.CMD_TRUSLEEP_ENABLE,
                HuaweiFitnessDataSync.CMD_AUTO_HR_ENABLE,
            ),
        )
        assertEquals("partial", result["overall"])
        @Suppress("UNCHECKED_CAST")
        val features = result["features"] as List<Map<String, Any?>>
        assertEquals("armed", featureOutcome(features, "trusleep"))
        assertEquals("armed", featureOutcome(features, "auto_hr"))
        assertEquals("skipped", featureOutcome(features, "auto_spo2"))
        assertFalse(sent.contains(HuaweiFitnessDataSync.CMD_AUTO_SPO2_ENABLE))
    }

    @Test
    fun enableAutoTracking_noneArmed_overallNone() {
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, _, _ -> null },
            isConnected = { true },
        )
        val result = sync.enableAutoTracking()
        assertEquals("none_armed", result["overall"])
        @Suppress("UNCHECKED_CAST")
        val features = result["features"] as List<Map<String, Any?>>
        assertTrue(features.all { it["outcome"] == "timed_out" })
    }

    private fun resultOkFrame(): HuaweiFraming.Frame =
        HuaweiFraming.Frame(
            HuaweiFitnessDataSync.SVC,
            0,
            listOf(
                HuaweiFraming.Tlv(
                    0x7F,
                    HuaweiPacketCrypto.intBe(HuaweiPacketCrypto.RESULT_OK),
                ),
            ),
        )

    private fun featureOutcome(features: List<Map<String, Any?>>, id: String): String =
        features.first { it["id"] == id }["outcome"] as String
}
