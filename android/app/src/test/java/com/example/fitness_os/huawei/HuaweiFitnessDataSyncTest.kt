package com.example.fitness_os.huawei

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HuaweiFitnessDataSyncTest {

    @Test
    fun parseSleepData_captureShapedStages_aggregateToSession() {
        // Shape from capture:POC-2026-07-18-activity-sync-sleep (timestamps synthetic).
        val begin = 1_700_000_000L
        val sync = HuaweiFitnessDataSync(exchangeEncrypted = { _, _, _, _ -> null })
        val frame = sleepDataFrame(
            index = 1,
            stages = listOf(
                Stage(begin, 10, 1),
                Stage(begin + 10 * 60, 15, 1),
                Stage(begin + 25 * 60, 20, 3),
            ),
        )
        val parsed = sync.parseSleepData(frame)
        assertEquals(1, parsed.sessions.size)
        assertEquals(begin, parsed.sessions[0].beginUnix)
        // last stage ends at begin+25m + 20m
        assertEquals(begin + 45 * 60, parsed.sessions[0].endUnix)
        assertEquals(3, parsed.sessions[0].stages.size)
        assertEquals(begin, parsed.sessions[0].stages[0].timestampUnix)
        assertEquals(20, parsed.sessions[0].stages[2].durationMin)
        assertEquals(3, parsed.sessions[0].stages[2].wireType)
    }

    @Test
    fun parseSleepData_gapSplitCreatesTwoSessions() {
        val begin = 1_700_000_000L
        val sync = HuaweiFitnessDataSync(exchangeEncrypted = { _, _, _, _ -> null })
        val frame = sleepDataFrame(
            index = 1,
            stages = listOf(
                Stage(begin, 30, 1),
                // 2h later — new session (nap vs overnight)
                Stage(begin + 3 * 3600, 40, 1),
            ),
        )
        val parsed = sync.parseSleepData(frame)
        assertEquals(2, parsed.sessions.size)
        assertEquals(30 * 60L, parsed.sessions[0].endUnix - parsed.sessions[0].beginUnix)
        assertEquals(40 * 60L, parsed.sessions[1].endUnix - parsed.sessions[1].beginUnix)
        assertEquals(1, parsed.sessions[0].stages.size)
        assertEquals(1, parsed.sessions[1].stages.size)
        assertEquals(begin + 3 * 3600, parsed.sessions[1].stages[0].timestampUnix)
    }

    @Test
    fun sync_mergesStagePagesIntoOneContinuousNap() {
        // One ~1h54m nap paged across three 0x0D indices (observed GT5 shape).
        val begin = 1_700_000_000L
        val queue = ArrayDeque(
            listOf(
                null,
                countFrame(HuaweiFitnessDataSync.CMD_SLEEP_COUNT, 3),
                sleepDataFrame(1, listOf(Stage(begin, 30, 1), Stage(begin + 30 * 60, 20, 1))),
                sleepDataFrame(2, listOf(Stage(begin + 55 * 60, 40, 3))),
                sleepDataFrame(3, listOf(Stage(begin + 100 * 60, 14, 1))),
                null,
            ),
        )
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, _, _ -> queue.removeFirstOrNull() },
        )
        val result = sync.sync(begin - 100, begin + 20_000)
        @Suppress("UNCHECKED_CAST")
        val sleeps = result["sleepSessions"] as List<Map<String, Any?>>
        assertEquals(1, sleeps.size)
        assertEquals(begin, sleeps[0]["beginUnix"])
        assertEquals(begin + 114 * 60L, sleeps[0]["endUnix"])
        @Suppress("UNCHECKED_CAST")
        val stages = sleeps[0]["stages"] as List<Map<String, Any?>>
        assertEquals(4, stages.size)
        assertEquals(begin, stages[0]["timestampUnix"])
        assertEquals(14, stages[3]["durationMin"])
    }

    @Test
    fun parseSleepData_zeroTimestampStageSkipped() {
        val sync = HuaweiFitnessDataSync(exchangeEncrypted = { _, _, _, _ -> null })
        val frame = sleepDataFrame(
            index = 5,
            stages = listOf(Stage(0, 0, 0)),
        )
        val parsed = sync.parseSleepData(frame)
        assertTrue(parsed.sessions.isEmpty())
    }

    @Test
    fun sync_fileDownloadAbsent_keepsSleepSessions() {
        val begin = 1_700_000_000L
        val queue = ArrayDeque(
            listOf(
                null,
                countFrame(HuaweiFitnessDataSync.CMD_SLEEP_COUNT, 1),
                sleepDataFrame(1, listOf(Stage(begin, 60, 1), Stage(begin + 60 * 60, 60, 1))),
                null,
            ),
        )
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, _, _ -> queue.removeFirstOrNull() },
            sleepFileDownloadProbe = {
                HuaweiFileDownload.ProbeOutcome(
                    status = "absent",
                    serviceId = HuaweiFileDownload.SVC_NEW,
                    reason = "timeout:sleep_state",
                )
            },
        )
        val result = sync.sync(begin - 100, begin + 20_000)
        @Suppress("UNCHECKED_CAST")
        val sleeps = result["sleepSessions"] as List<Map<String, Any?>>
        assertEquals(1, sleeps.size)
        assertEquals(begin, sleeps[0]["beginUnix"])
        @Suppress("UNCHECKED_CAST")
        val enrich = result["sleepEnrich"] as List<*>
        assertTrue(enrich.isEmpty())
        assertEquals("ok", result["status"])
    }

    @Test
    fun sync_fileDownloadPresent_withMessages_stillEmitsEnrich() {
        val begin = 1_700_000_000L
        val intervalBegin = 1_700_000_000
        val intervalEnd = 1_700_014_400
        val queue = ArrayDeque(
            listOf(
                null,
                countFrame(HuaweiFitnessDataSync.CMD_SLEEP_COUNT, 1),
                sleepDataFrame(1, listOf(Stage(begin, 90, 1))),
                null,
            ),
        )
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, _, _ -> queue.removeFirstOrNull() },
            sleepFileDownloadProbe = {
                HuaweiFileDownload.ProbeOutcome(
                    status = "present",
                    serviceId = HuaweiFileDownload.SVC_NEW,
                    files = listOf(
                        HuaweiFileDownload.FileRef("sleep_state", 128),
                    ),
                    stateIntervals = listOf(
                        HuaweiFileDownload.StateInterval(intervalBegin, intervalEnd),
                    ),
                )
            },
        )
        val result = sync.sync(begin - 100, begin + 20_000)
        @Suppress("UNCHECKED_CAST")
        val sleeps = result["sleepSessions"] as List<Map<String, Any?>>
        assertEquals(1, sleeps.size)
        @Suppress("UNCHECKED_CAST")
        val enrich = result["sleepEnrich"] as List<Map<String, Any?>>
        assertEquals(1, enrich.size)
        assertEquals(true, enrich[0]["present"])
        assertEquals(intervalBegin, enrich[0]["beginUnix"])
        assertEquals(intervalEnd, enrich[0]["endUnix"])
        @Suppress("UNCHECKED_CAST")
        val intervals = enrich[0]["stateIntervals"] as List<Map<String, Any?>>
        assertEquals(1, intervals.size)
        @Suppress("UNCHECKED_CAST")
        val refs = enrich[0]["refs"] as List<Map<String, Any?>>
        assertEquals(1, refs.size)
        assertEquals("sleep_state", refs[0]["id"])
        assertEquals("ok", result["status"])
    }

    @Test
    fun sync_happyPath_overnightNapWithoutHr() {
        val overnightBegin = 1_700_000_000L
        val napBegin = overnightBegin + 12 * 3600

        val sleepCount = countFrame(HuaweiFitnessDataSync.CMD_SLEEP_COUNT, 2)
        val sleep1 = sleepDataFrame(
            1,
            listOf(
                Stage(overnightBegin, 60, 1),
                Stage(overnightBegin + 60 * 60, 60, 3),
                Stage(overnightBegin + 120 * 60, 60, 1),
            ),
        )
        val sleep2 = sleepDataFrame(
            2,
            listOf(Stage(napBegin, 45, 1)),
        )
        val enableOk = HuaweiFraming.Frame(
            HuaweiFitnessDataSync.SVC,
            0,
            listOf(HuaweiFraming.Tlv(0x7F, HuaweiPacketCrypto.intBe(HuaweiPacketCrypto.RESULT_OK))),
        )

        val queue = ArrayDeque(
            listOf(
                enableOk.copy(commandId = HuaweiFitnessDataSync.CMD_TRUSLEEP_ENABLE),
                sleepCount,
                sleep1,
                sleep2,
                enableOk.copy(commandId = HuaweiFitnessDataSync.CMD_FITNESS_TOTALS),
            ),
        )

        val cmds = mutableListOf<Int>()
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, cmd, _ ->
                cmds.add(cmd)
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
        assertTrue(hr.isEmpty())
        @Suppress("UNCHECKED_CAST")
        val completed = result["completedContainers"] as List<String>
        assertTrue(completed.contains("sleep"))
        assertFalse(completed.contains("daily_hr"))
        assertFalse(cmds.contains(HuaweiFitnessDataSync.CMD_AUTO_HR_ENABLE))
        assertFalse(cmds.contains(HuaweiFitnessDataSync.CMD_STEP_COUNT))
        assertFalse(cmds.contains(HuaweiFitnessDataSync.CMD_STEP_DATA))
    }

    @Test
    fun sync_skipsAutoHrSoftAndDailyHr() {
        val begin = 1_700_000_000L
        val enableOk = HuaweiFraming.Frame(
            HuaweiFitnessDataSync.SVC,
            0,
            listOf(HuaweiFraming.Tlv(0x7F, HuaweiPacketCrypto.intBe(HuaweiPacketCrypto.RESULT_OK))),
        )
        val queue = ArrayDeque(
            listOf(
                enableOk.copy(commandId = HuaweiFitnessDataSync.CMD_TRUSLEEP_ENABLE),
                countFrame(HuaweiFitnessDataSync.CMD_SLEEP_COUNT, 1),
                sleepDataFrame(1, listOf(Stage(begin, 90, 1))),
                null,
            ),
        )
        val cmds = mutableListOf<Int>()
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, cmd, _ ->
                cmds.add(cmd)
                queue.removeFirstOrNull()
            },
        )
        val result = sync.sync(begin - 100, begin + 10_000)
        assertEquals("ok", result["status"])
        assertTrue(cmds.contains(HuaweiFitnessDataSync.CMD_TRUSLEEP_ENABLE))
        assertFalse(cmds.contains(HuaweiFitnessDataSync.CMD_AUTO_HR_ENABLE))
        assertFalse(cmds.contains(HuaweiFitnessDataSync.CMD_STEP_COUNT))
        assertFalse(cmds.contains(HuaweiFitnessDataSync.CMD_STEP_DATA))
        @Suppress("UNCHECKED_CAST")
        val hr = result["dailyHrSamples"] as List<*>
        assertTrue(hr.isEmpty())
        @Suppress("UNCHECKED_CAST")
        val completed = result["completedContainers"] as List<String>
        assertTrue(completed.contains("sleep"))
        assertFalse(completed.contains("daily_hr"))
    }

    @Test
    fun sync_messagesEmpty_fileIntervalsPresent_emitsEnrichAndOk() {
        val begin = 1_700_000_000L
        val intervalBegin = 1_700_000_000
        val intervalEnd = 1_700_014_400
        val queue = ArrayDeque(
            listOf(
                null,
                countFrame(HuaweiFitnessDataSync.CMD_SLEEP_COUNT, 0),
                null,
            ),
        )
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, _, _ -> queue.removeFirstOrNull() },
            sleepFileDownloadProbe = {
                HuaweiFileDownload.ProbeOutcome(
                    status = "present",
                    serviceId = HuaweiFileDownload.SVC_NEW,
                    files = listOf(HuaweiFileDownload.FileRef("sleep_state", 128)),
                    stateIntervals = listOf(
                        HuaweiFileDownload.StateInterval(intervalBegin, intervalEnd),
                    ),
                )
            },
        )
        val result = sync.sync(begin - 100, begin + 20_000)
        @Suppress("UNCHECKED_CAST")
        val sleeps = result["sleepSessions"] as List<*>
        assertTrue(sleeps.isEmpty())
        @Suppress("UNCHECKED_CAST")
        val enrich = result["sleepEnrich"] as List<Map<String, Any?>>
        assertEquals(1, enrich.size)
        assertEquals(true, enrich[0]["present"])
        @Suppress("UNCHECKED_CAST")
        val intervals = enrich[0]["stateIntervals"] as List<Map<String, Any?>>
        assertEquals(1, intervals.size)
        assertEquals(intervalBegin, intervals[0]["beginUnix"])
        assertEquals("ok", result["status"])
    }

    @Test
    fun sync_fileDownloadPresent_zeroIntervals_emptyMessages_noSoTFromFiles() {
        val begin = 1_700_000_000L
        val queue = ArrayDeque(
            listOf(
                null,
                countFrame(HuaweiFitnessDataSync.CMD_SLEEP_COUNT, 0),
                null,
            ),
        )
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, _, _ -> queue.removeFirstOrNull() },
            sleepFileDownloadProbe = {
                HuaweiFileDownload.ProbeOutcome(
                    status = "present",
                    serviceId = HuaweiFileDownload.SVC_NEW,
                    files = listOf(HuaweiFileDownload.FileRef("sleep_state", 128)),
                    stateIntervals = emptyList(),
                )
            },
        )
        val result = sync.sync(begin - 100, begin + 20_000)
        @Suppress("UNCHECKED_CAST")
        val sleeps = result["sleepSessions"] as List<*>
        assertTrue(sleeps.isEmpty())
        @Suppress("UNCHECKED_CAST")
        val enrich = result["sleepEnrich"] as List<*>
        assertTrue(enrich.isEmpty())
        assertEquals("empty", result["status"])
    }

    @Test
    fun sync_napOnly() {
        val begin = 1_700_010_000L
        val queue = ArrayDeque(
            listOf(
                null,
                countFrame(HuaweiFitnessDataSync.CMD_SLEEP_COUNT, 1),
                sleepDataFrame(1, listOf(Stage(begin, 40, 1))),
                null,
            ),
        )
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, _, _ -> queue.removeFirstOrNull() },
        )
        val result = sync.sync(begin - 100, begin + 10_000)
        @Suppress("UNCHECKED_CAST")
        val sleeps = result["sleepSessions"] as List<Map<String, Any?>>
        assertEquals(1, sleeps.size)
        assertEquals(begin, sleeps[0]["beginUnix"])
        assertEquals(begin + 40 * 60, sleeps[0]["endUnix"])
    }

    @Test
    fun sync_timeoutAfterSleepData_partialBatch() {
        val begin = 1_700_000_000L
        val queue = ArrayDeque(
            listOf(
                null,
                countFrame(HuaweiFitnessDataSync.CMD_SLEEP_COUNT, 2),
                sleepDataFrame(1, listOf(Stage(begin, 60, 1))),
                null,
            ),
        )
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, _, _ -> queue.removeFirstOrNull() },
        )
        val result = sync.sync(begin - 100, begin + 10_000)
        assertEquals("partial_batch", result["status"])
        @Suppress("UNCHECKED_CAST")
        val sleeps = result["sleepSessions"] as List<Map<String, Any?>>
        assertEquals(1, sleeps.size)
        @Suppress("UNCHECKED_CAST")
        val completed = result["completedContainers"] as List<String>
        assertTrue(completed.contains("sleep"))
    }

    @Test
    fun extractHrBpm_readsAfterLowerBitmapFields() {
        val sync = HuaweiFitnessDataSync(exchangeEncrypted = { _, _, _, _ -> null })
        // bitmap 0x41 = steps + HR; steps u16 + hr u8
        val payload = byteArrayOf(
            (0x01 or HuaweiFitnessDataSync.BITMAP_HR).toByte(),
            0x00, 0x10, // steps
            72, // hr
        )
        assertEquals(72, sync.extractHrBpm(payload))
        assertEquals(null, sync.extractHrBpm(byteArrayOf(0x0E, 0, 1, 0, 2, 0, 3)))
    }

    @Test
    fun tlvTagLenHistogram_countsTopAndNested() {
        val nested = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(1)),
                HuaweiFraming.Tlv(0x05, HuaweiPacketCrypto.intBe(966)),
                HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.shortBe(127)),
            ),
        )
        val tlvs = listOf(HuaweiFraming.Tlv(0x81, nested))
        val hist = HuaweiFitnessDataSync.tlvTagLenHistogram(tlvs)
        assertTrue(hist.contains("t=81:len=${nested.size}x1"))
        assertTrue(hist.contains("nested["))
        assertTrue(hist.contains("t=2:len=2x1"))
        assertTrue(hist.contains("t=5:len=4x1"))
        assertTrue(hist.contains("t=6:len=2x1"))
    }

    @Test
    fun leafScalarCandidates_decodesBeLeavesWithoutClaimingMeaning() {
        val nested = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x05, HuaweiPacketCrypto.intBe(966)),
                HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.shortBe(127)),
            ),
        )
        val tlvs = listOf(HuaweiFraming.Tlv(0x81, nested))
        val scalars = HuaweiFitnessDataSync.leafScalarCandidates(tlvs)
        assertTrue(scalars.contains("0x81/0x5:u32=966"))
        assertTrue(scalars.contains("0x81/0x6:u16=127"))
    }

    @Test
    fun sync_stuckSleepCount_stillRequestsFitnessTotalsWhenConnected() {
        val begin = 1_700_000_000L
        val cmds = mutableListOf<Int>()
        val queue = ArrayDeque(
            listOf(
                null, // soft TruSleep enable
                null, // sleepCount timeout
                HuaweiFraming.Frame(
                    HuaweiFitnessDataSync.SVC,
                    HuaweiFitnessDataSync.CMD_FITNESS_TOTALS,
                    listOf(
                        HuaweiFraming.Tlv(
                            0x81,
                            HuaweiFraming.encodeTlvs(
                                listOf(HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(1))),
                            ),
                        ),
                    ),
                ),
            ),
        )
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, cmd, _ ->
                cmds.add(cmd)
                queue.removeFirstOrNull()
            },
        )
        val result = sync.sync(begin - 100, begin + 10_000)
        assertEquals("stuck", result["status"])
        assertTrue(cmds.contains(HuaweiFitnessDataSync.CMD_FITNESS_TOTALS))
        @Suppress("UNCHECKED_CAST")
        val totals = result["fitnessTotals"] as List<*>
        assertTrue(totals.isEmpty())
        @Suppress("UNCHECKED_CAST")
        val completed = result["completedContainers"] as List<String>
        assertFalse(completed.contains("fitness_totals"))
    }

    @Test
    fun parseFitnessTotals_ownedTags_mapsSlotTag1OntoLocalToday() {
        // capture:owner-2026-08-07 + capture:owner-2026-08-08-swim:
        // 0x04=1 → today; tag 0 skipped (padding).
        val end = 1_704_067_200L + 12 * 3600 // 2024-01-01 noon UTC
        val sync = HuaweiFitnessDataSync(exchangeEncrypted = { _, _, _, _ -> null })
        val frame = fitnessTotalsFrame(
            slots = listOf(
                FitnessSlot(slotTag = 1, steps = 7825, calories = 525, durationSec = 5064),
                FitnessSlot(slotTag = 0, steps = 0, calories = 0, durationSec = 0),
            ),
        )
        val parsed = sync.parseFitnessTotals(frame, endUnix = end)
        assertEquals(1, parsed.days.size)
        val today = parsed.days[0]
        assertEquals(HuaweiFitnessDataSync.localDayKey(end), today.dayKey)
        assertEquals(7825, today.steps)
        assertEquals(525, today.calories)
        assertEquals(5064, today.exerciseDurationSec)
    }

    @Test
    fun parseFitnessTotals_slotTagN_mapsToNMinusOneDaysBefore() {
        val end = 1_704_067_200L + 12 * 3600
        val sync = HuaweiFitnessDataSync(exchangeEncrypted = { _, _, _, _ -> null })
        val frame = fitnessTotalsFrame(
            slots = listOf(
                FitnessSlot(slotTag = 1, steps = 27, calories = 1, durationSec = 15),
                FitnessSlot(slotTag = 3, steps = 76, calories = 3, durationSec = 52),
            ),
        )
        val parsed = sync.parseFitnessTotals(frame, endUnix = end)
        assertEquals(2, parsed.days.size)
        val today = parsed.days.first { it.calories == 1 }
        val older = parsed.days.first { it.calories == 3 }
        assertEquals(HuaweiFitnessDataSync.localDayKey(end), today.dayKey)
        assertEquals(
            HuaweiFitnessDataSync.localDayKey(
                HuaweiFitnessDataSync.localDayStartUnix(end, daysBefore = 2),
            ),
            older.dayKey,
        )
    }

    @Test
    fun parseFitnessTotals_unknownTagsOnly_notUsable() {
        val sync = HuaweiFitnessDataSync(exchangeEncrypted = { _, _, _, _ -> null })
        val frame = HuaweiFraming.Frame(
            HuaweiFitnessDataSync.SVC,
            HuaweiFitnessDataSync.CMD_FITNESS_TOTALS,
            listOf(
                HuaweiFraming.Tlv(
                    0x81,
                    HuaweiFraming.encodeTlvs(
                        listOf(HuaweiFraming.Tlv(0x09, ByteArray(8))),
                    ),
                ),
            ),
        )
        val parsed = sync.parseFitnessTotals(frame, endUnix = 1_704_067_200L)
        assertTrue(parsed.days.isEmpty())
    }

    @Test
    fun sync_happyPath_parsesFitnessTotalsIntoCompletedContainer() {
        val overnightBegin = 1_700_000_000L
        val end = overnightBegin + 86400
        val sleepCount = countFrame(HuaweiFitnessDataSync.CMD_SLEEP_COUNT, 1)
        val sleep1 = sleepDataFrame(1, listOf(Stage(overnightBegin, 90, 1)))
        val totals = fitnessTotalsFrame(
            slots = listOf(
                FitnessSlot(slotTag = 1, steps = 8500, calories = 966, durationSec = 7620),
            ),
        )
        val enableOk = HuaweiFraming.Frame(
            HuaweiFitnessDataSync.SVC,
            0,
            listOf(HuaweiFraming.Tlv(0x7F, HuaweiPacketCrypto.intBe(HuaweiPacketCrypto.RESULT_OK))),
        )
        val queue = ArrayDeque(
            listOf(
                enableOk.copy(commandId = HuaweiFitnessDataSync.CMD_TRUSLEEP_ENABLE),
                sleepCount,
                sleep1,
                totals,
            ),
        )
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, cmd, _ ->
                val next = queue.removeFirstOrNull()
                assertEquals("unexpected cmd 0x${cmd.toString(16)}", cmd, next?.commandId ?: cmd)
                next
            },
        )
        val result = sync.sync(overnightBegin - 86400, end)
        assertEquals("ok", result["status"])
        @Suppress("UNCHECKED_CAST")
        val completed = result["completedContainers"] as List<String>
        assertTrue(completed.contains("sleep"))
        assertTrue(completed.contains("fitness_totals"))
        @Suppress("UNCHECKED_CAST")
        val days = result["fitnessTotals"] as List<Map<String, Any?>>
        assertEquals(1, days.size)
        assertEquals(966, days[0]["calories"])
        assertEquals(8500, days[0]["steps"])
        assertEquals(7620, days[0]["exerciseDurationSec"])
        assertEquals(HuaweiFitnessDataSync.localDayKey(end), days[0]["dayKey"])
    }

    @Test
    fun sync_fitnessTotalsTimeout_softOmitsCompletedBit() {
        val begin = 1_700_000_000L
        val queue = ArrayDeque(
            listOf(
                null,
                countFrame(HuaweiFitnessDataSync.CMD_SLEEP_COUNT, 1),
                sleepDataFrame(1, listOf(Stage(begin, 90, 1))),
                null, // FitnessTotals timeout
            ),
        )
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, _, _ -> queue.removeFirstOrNull() },
        )
        val result = sync.sync(begin - 100, begin + 10_000)
        assertEquals("ok", result["status"])
        @Suppress("UNCHECKED_CAST")
        val completed = result["completedContainers"] as List<String>
        assertTrue(completed.contains("sleep"))
        assertFalse(completed.contains("fitness_totals"))
        @Suppress("UNCHECKED_CAST")
        val totals = result["fitnessTotals"] as List<*>
        assertTrue(totals.isEmpty())
    }

    @Test
    fun sync_sleepDataTimeout_stillIssuesFitnessTotalsThenPartialBatch() {
        val begin = 1_700_000_000L
        val cmds = mutableListOf<Int>()
        val totals = fitnessTotalsFrame(
            slots = listOf(
                FitnessSlot(slotTag = 1, steps = 100, calories = 50, durationSec = 600),
            ),
        )
        val queue = ArrayDeque(
            listOf(
                null,
                countFrame(HuaweiFitnessDataSync.CMD_SLEEP_COUNT, 2),
                sleepDataFrame(1, listOf(Stage(begin, 90, 1))),
                null, // sleepData timeout for index 2
                totals,
            ),
        )
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, cmd, _ ->
                cmds.add(cmd)
                queue.removeFirstOrNull()
            },
        )
        val result = sync.sync(begin - 100, begin + 10_000)
        assertEquals("partial_batch", result["status"])
        assertTrue(cmds.contains(HuaweiFitnessDataSync.CMD_FITNESS_TOTALS))
        assertFalse(cmds.contains(HuaweiFitnessDataSync.CMD_STEP_COUNT))
        @Suppress("UNCHECKED_CAST")
        val completed = result["completedContainers"] as List<String>
        assertTrue(completed.contains("sleep"))
        assertTrue(completed.contains("fitness_totals"))
        @Suppress("UNCHECKED_CAST")
        val days = result["fitnessTotals"] as List<Map<String, Any?>>
        assertEquals(1, days.size)
        assertEquals(50, days[0]["calories"])
    }

    @Test
    fun sync_totalsOnlyPayload_statusOkNotEmpty() {
        val begin = 1_700_000_000L
        val end = begin + 3600
        val totals = fitnessTotalsFrame(
            slots = listOf(
                FitnessSlot(slotTag = 1, steps = 10, calories = 5, durationSec = 60),
            ),
        )
        val queue = ArrayDeque(
            listOf(
                null,
                countFrame(HuaweiFitnessDataSync.CMD_SLEEP_COUNT, 0),
                totals,
            ),
        )
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, _, _ -> queue.removeFirstOrNull() },
        )
        val result = sync.sync(begin, end)
        assertEquals("ok", result["status"])
        @Suppress("UNCHECKED_CAST")
        val completed = result["completedContainers"] as List<String>
        assertTrue(completed.contains("fitness_totals"))
        @Suppress("UNCHECKED_CAST")
        val sleeps = result["sleepSessions"] as List<*>
        assertTrue(sleeps.isEmpty())
    }

    @Test
    fun probeDailyHrIntervalProxy_recordsHistogramWithoutSeries() {
        val dayStart = 1_700_000_000L
        val queue = ArrayDeque(
            listOf(
                countFrame(HuaweiFitnessDataSync.CMD_STEP_COUNT, 1),
                stepHrFrame(
                    index = 1,
                    dayStart = dayStart,
                    samples = listOf(
                        MinuteSample(
                            minute = 1,
                            bitmap = HuaweiFitnessDataSync.BITMAP_HR,
                            payloadAfterBitmap = byteArrayOf(72),
                        ),
                    ),
                ),
            ),
        )
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, _, _ -> queue.removeFirstOrNull() },
        )
        val out = sync.probeDailyHrIntervalProxy(dayStart, dayStart + 86400)
        assertEquals("present", out["status"])
        assertEquals("interval-proxy", out["class"])
        assertEquals(1, out["hrBitmapDays"])
        assertEquals(1, out["sampleCount"])
        assertFalse(out.containsKey("samples"))
        assertFalse(out.containsKey("dailyHrSamples"))
        assertFalse(out.toString().contains("72"))
    }

    @Test
    fun probeDailyHrIntervalProxy_timeout_absent() {
        val sync = HuaweiFitnessDataSync(
            exchangeEncrypted = { _, _, _, _ -> null },
        )
        val out = sync.probeDailyHrIntervalProxy(1_700_000_000L, 1_700_086_400L)
        assertEquals("absent", out["status"])
        assertEquals("step_count_timeout", out["reason"])
    }

    private data class Stage(val ts: Long, val durMin: Int, val type: Int)

    private data class FitnessSlot(
        val slotTag: Int,
        val steps: Int,
        val calories: Int,
        val durationSec: Int,
    )

    private data class MinuteSample(
        val minute: Int,
        val bitmap: Int,
        val payloadAfterBitmap: ByteArray,
    )

    private fun countFrame(cmd: Int, count: Int): HuaweiFraming.Frame {
        val container = HuaweiFraming.encodeTlvs(
            listOf(HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(count))),
        )
        return HuaweiFraming.Frame(
            HuaweiFitnessDataSync.SVC,
            cmd,
            listOf(HuaweiFraming.Tlv(0x81, container)),
        )
    }

    private fun sleepDataFrame(index: Int, stages: List<Stage>): HuaweiFraming.Frame {
        val entries = mutableListOf(
            HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(index)),
        )
        for (s in stages) {
            val tsBytes = ByteArray(6)
            val be = HuaweiPacketCrypto.intBe(s.ts.toInt())
            System.arraycopy(be, 0, tsBytes, 0, 4)
            tsBytes[4] = ((s.durMin shr 8) and 0xFF).toByte()
            tsBytes[5] = (s.durMin and 0xFF).toByte()
            entries += HuaweiFraming.Tlv(
                0x83,
                HuaweiFraming.encodeTlvs(
                    listOf(
                        HuaweiFraming.Tlv(0x04, byteArrayOf(s.type.toByte())),
                        HuaweiFraming.Tlv(0x06, byteArrayOf(0x00)),
                        HuaweiFraming.Tlv(0x05, tsBytes),
                    ),
                ),
            )
        }
        return HuaweiFraming.Frame(
            HuaweiFitnessDataSync.SVC,
            HuaweiFitnessDataSync.CMD_SLEEP_DATA,
            listOf(HuaweiFraming.Tlv(0x81, HuaweiFraming.encodeTlvs(entries))),
        )
    }

    private fun stepHrFrame(
        index: Int,
        dayStart: Long,
        samples: List<MinuteSample>,
    ): HuaweiFraming.Frame {
        val children = mutableListOf(
            HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.shortBe(index)),
            HuaweiFraming.Tlv(0x03, HuaweiPacketCrypto.intBe(dayStart.toInt())),
        )
        for (s in samples) {
            val payload = byteArrayOf(s.bitmap.toByte()) + s.payloadAfterBitmap
            children += HuaweiFraming.Tlv(
                0x84,
                HuaweiFraming.encodeTlvs(
                    listOf(
                        HuaweiFraming.Tlv(0x05, byteArrayOf(s.minute.toByte())),
                        HuaweiFraming.Tlv(0x06, payload),
                    ),
                ),
            )
        }
        children += HuaweiFraming.Tlv(0x08, byteArrayOf(0x00))
        return HuaweiFraming.Frame(
            HuaweiFitnessDataSync.SVC,
            HuaweiFitnessDataSync.CMD_STEP_DATA,
            listOf(HuaweiFraming.Tlv(0x81, HuaweiFraming.encodeTlvs(children))),
        )
    }

    /** Synthetic FitnessTotals shaped like wire-spec nested `0x83` day slots. */
    private fun fitnessTotalsFrame(slots: List<FitnessSlot>): HuaweiFraming.Frame {
        val entries = mutableListOf(
            HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.intBe(1)),
        )
        for (s in slots) {
            entries += HuaweiFraming.Tlv(
                0x83,
                HuaweiFraming.encodeTlvs(
                    listOf(
                        HuaweiFraming.Tlv(0x04, byteArrayOf(s.slotTag.toByte())),
                        HuaweiFraming.Tlv(0x05, HuaweiPacketCrypto.intBe(s.steps)),
                        HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.shortBe(s.calories)),
                        HuaweiFraming.Tlv(0x07, HuaweiPacketCrypto.intBe(s.durationSec)),
                        HuaweiFraming.Tlv(0x08, HuaweiPacketCrypto.shortBe(0)),
                        HuaweiFraming.Tlv(0x0B, HuaweiPacketCrypto.intBe(0)),
                    ),
                ),
            )
        }
        entries += HuaweiFraming.Tlv(0x09, ByteArray(8))
        return HuaweiFraming.Frame(
            HuaweiFitnessDataSync.SVC,
            HuaweiFitnessDataSync.CMD_FITNESS_TOTALS,
            listOf(HuaweiFraming.Tlv(0x81, HuaweiFraming.encodeTlvs(entries))),
        )
    }

    private fun HuaweiFraming.Frame.copy(commandId: Int): HuaweiFraming.Frame =
        HuaweiFraming.Frame(serviceId, commandId, tlvs)
}
