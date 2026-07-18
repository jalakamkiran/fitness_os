package com.example.fitness_os.huawei

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HuaweiFitnessDataSyncTest {

    @Test
    fun sync_happyPath_overnightNapAndHr() {
        val overnightBegin = 1_700_000_000L
        val overnightEnd = overnightBegin + 8 * 3600
        val napBegin = overnightEnd + 4 * 3600
        val napEnd = napBegin + 45 * 60

        val sleepCount = countFrame(HuaweiFitnessDataSync.CMD_SLEEP_COUNT, listOf(1, 2))
        val sleep1 = sleepDataFrame(
            listOf(
                Triple(overnightBegin, overnightEnd, null as Int?),
            ),
        )
        val sleep2 = sleepDataFrame(
            listOf(
                Triple(napBegin, napEnd, 1),
            ),
        )
        val stepCount = countFrame(HuaweiFitnessDataSync.CMD_STEP_COUNT, listOf(1))
        val stepData = stepHrFrame(
            bitmap = HuaweiFitnessDataSync.BITMAP_HR,
            samples = listOf(overnightBegin + 12 * 3600 to 72, overnightBegin + 12 * 3600 + 60 to 75),
        )
        val enableOk = HuaweiFraming.Frame(
            HuaweiFitnessDataSync.SVC,
            0,
            listOf(HuaweiFraming.Tlv(0x7F, HuaweiPacketCrypto.intBe(0))),
        )

        val queue = ArrayDeque(
            listOf(
                enableOk.copy(commandId = HuaweiFitnessDataSync.CMD_TRUSLEEP_ENABLE),
                enableOk.copy(commandId = HuaweiFitnessDataSync.CMD_AUTO_HR_ENABLE),
                sleepCount,
                sleep1,
                sleep2,
                stepCount,
                stepData,
                enableOk.copy(commandId = HuaweiFitnessDataSync.CMD_FITNESS_TOTALS),
            ),
        )

        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, cmd, _ ->
                val next = queue.removeFirstOrNull()
                assertEquals("unexpected cmd 0x${cmd.toString(16)}", cmd, next?.commandId ?: cmd)
                next
            },
        )

        val result = sync.sync(overnightBegin - 86400, overnightBegin + 86400)
        assertEquals("ok", result["status"])
        @Suppress("UNCHECKED_CAST")
        val sleeps = result["sleepSessions"] as List<Map<String, Any?>>
        assertEquals(2, sleeps.size)
        @Suppress("UNCHECKED_CAST")
        val hr = result["dailyHrSamples"] as List<Map<String, Any?>>
        assertEquals(2, hr.size)
        @Suppress("UNCHECKED_CAST")
        val completed = result["completedContainers"] as List<String>
        assertTrue(completed.contains("sleep"))
        assertTrue(completed.contains("daily_hr"))
    }

    @Test
    fun sync_sleepPresentHrBitmapAbsent_notPartialBatch() {
        val begin = 1_700_000_000L
        val end = begin + 8 * 3600
        val queue = ArrayDeque(
            listOf(
                null, // enable trusleep skip
                null, // enable hr skip
                countFrame(HuaweiFitnessDataSync.CMD_SLEEP_COUNT, listOf(1)),
                sleepDataFrame(listOf(Triple(begin, end, null))),
                countFrame(HuaweiFitnessDataSync.CMD_STEP_COUNT, listOf(1)),
                stepHrFrame(bitmap = 0x01, samples = emptyList()), // no HR bit
                null, // fitness totals
            ),
        )
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, _, _ -> queue.removeFirstOrNull() },
        )
        val result = sync.sync(begin - 100, end + 100)
        assertEquals("ok", result["status"])
        @Suppress("UNCHECKED_CAST")
        val completed = result["completedContainers"] as List<String>
        assertTrue(completed.contains("sleep"))
        assertFalse(completed.contains("daily_hr"))
    }

    @Test
    fun sync_napOnly() {
        val begin = 1_700_010_000L
        val end = begin + 40 * 60
        val queue = ArrayDeque(
            listOf(
                null,
                null,
                countFrame(HuaweiFitnessDataSync.CMD_SLEEP_COUNT, listOf(1)),
                sleepDataFrame(listOf(Triple(begin, end, null))),
                countFrame(HuaweiFitnessDataSync.CMD_STEP_COUNT, emptyList()),
                null,
            ),
        )
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, _, _ -> queue.removeFirstOrNull() },
        )
        val result = sync.sync(begin - 100, end + 100)
        @Suppress("UNCHECKED_CAST")
        val sleeps = result["sleepSessions"] as List<Map<String, Any?>>
        assertEquals(1, sleeps.size)
        assertEquals(begin, sleeps[0]["beginUnix"])
    }

    @Test
    fun sync_timeoutAfterSleepData_partialBatch() {
        val begin = 1_700_000_000L
        val end = begin + 8 * 3600
        val queue = ArrayDeque(
            listOf(
                null,
                null,
                countFrame(HuaweiFitnessDataSync.CMD_SLEEP_COUNT, listOf(1, 2)),
                sleepDataFrame(listOf(Triple(begin, end, null))),
                null, // second sleepData timeout
            ),
        )
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, _, _ -> queue.removeFirstOrNull() },
        )
        val result = sync.sync(begin - 100, end + 100)
        assertEquals("partial_batch", result["status"])
        @Suppress("UNCHECKED_CAST")
        val sleeps = result["sleepSessions"] as List<Map<String, Any?>>
        assertEquals(1, sleeps.size)
        @Suppress("UNCHECKED_CAST")
        val completed = result["completedContainers"] as List<String>
        assertTrue(completed.contains("sleep"))
    }

    @Test
    fun parseSleepData_recordsUnknownTagsWithoutFailing() {
        val sync = HuaweiFitnessDataSync(exchangeEncrypted = { _, _, _, _ -> null })
        val entry = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x01, HuaweiPacketCrypto.intBe(100)),
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.intBe(200)),
                HuaweiFraming.Tlv(0x55, byteArrayOf(0x01)),
            ),
        )
        val container = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x83, entry),
                HuaweiFraming.Tlv(0x99, byteArrayOf(0x02)),
            ),
        )
        val frame = HuaweiFraming.Frame(
            HuaweiFitnessDataSync.SVC,
            HuaweiFitnessDataSync.CMD_SLEEP_DATA,
            listOf(HuaweiFraming.Tlv(0x81, container)),
        )
        val parsed = sync.parseSleepData(frame)
        assertEquals(1, parsed.sessions.size)
        assertTrue(parsed.unknownTags >= 1)
    }

    private fun countFrame(cmd: Int, indices: List<Int>): HuaweiFraming.Frame {
        val children = indices.map { idx ->
            HuaweiFraming.Tlv(
                0x85,
                HuaweiFraming.encodeTlvs(
                    listOf(HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(idx))),
                ),
            )
        }
        val container = HuaweiFraming.encodeTlvs(
            listOf(HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(indices.size))) + children,
        )
        return HuaweiFraming.Frame(
            HuaweiFitnessDataSync.SVC,
            cmd,
            listOf(HuaweiFraming.Tlv(0x81, container)),
        )
    }

    private fun sleepDataFrame(
        sessions: List<Triple<Long, Long, Int?>>,
    ): HuaweiFraming.Frame {
        val entries = sessions.map { (b, e, t) ->
            val inner = mutableListOf(
                HuaweiFraming.Tlv(0x01, HuaweiPacketCrypto.intBe(b.toInt())),
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.intBe(e.toInt())),
            )
            if (t != null) inner += HuaweiFraming.Tlv(0x03, byteArrayOf(t.toByte()))
            HuaweiFraming.Tlv(0x83, HuaweiFraming.encodeTlvs(inner))
        }
        val container = HuaweiFraming.encodeTlvs(entries)
        return HuaweiFraming.Frame(
            HuaweiFitnessDataSync.SVC,
            HuaweiFitnessDataSync.CMD_SLEEP_DATA,
            listOf(HuaweiFraming.Tlv(0x81, container)),
        )
    }

    private fun stepHrFrame(
        bitmap: Int,
        samples: List<Pair<Long, Int>>,
    ): HuaweiFraming.Frame {
        val children = mutableListOf(
            HuaweiFraming.Tlv(0x02, byteArrayOf(bitmap.toByte())),
        )
        for ((ts, bpm) in samples) {
            children += HuaweiFraming.Tlv(
                0x84,
                HuaweiFraming.encodeTlvs(
                    listOf(
                        HuaweiFraming.Tlv(0x01, HuaweiPacketCrypto.intBe(ts.toInt())),
                        HuaweiFraming.Tlv(0x02, byteArrayOf(bpm.toByte())),
                    ),
                ),
            )
        }
        return HuaweiFraming.Frame(
            HuaweiFitnessDataSync.SVC,
            HuaweiFitnessDataSync.CMD_STEP_DATA,
            listOf(HuaweiFraming.Tlv(0x81, HuaweiFraming.encodeTlvs(children))),
        )
    }

    private fun HuaweiFraming.Frame.copy(commandId: Int): HuaweiFraming.Frame =
        HuaweiFraming.Frame(serviceId, commandId, tlvs)
}
