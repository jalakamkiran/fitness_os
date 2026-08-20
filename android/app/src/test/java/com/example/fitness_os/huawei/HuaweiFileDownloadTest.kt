package com.example.fitness_os.huawei

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class HuaweiFileDownloadTest {

    @Test
    fun download_softSkipByDefault_pendingCapture() {
        val dl = HuaweiFileDownload(
            exchangeEncrypted = { _, _, _, _ ->
                throw AssertionError("live exchange must not run when soft-skip")
            },
            liveDownloadEnabled = false,
        )
        val out = dl.downloadSleepFiles(preferNewSync = true)
        assertEquals("skipped", out.status)
        assertEquals(HuaweiFileDownload.SVC_NEW, out.serviceId)
        assertEquals("pending_capture", out.reason)
        assertTrue(out.files.isEmpty())
    }

    @Test
    fun download_legacy_unimplemented_absent() {
        val dl = HuaweiFileDownload(
            exchangeEncrypted = { _, _, _, _ -> null },
            liveDownloadEnabled = true,
        )
        val out = dl.downloadSleepFiles(preferNewSync = false)
        assertEquals("absent", out.status)
        assertEquals(HuaweiFileDownload.SVC_LEGACY, out.serviceId)
        assertEquals("legacy_unimplemented", out.reason)
    }

    @Test
    fun download_disconnected_skipped() {
        val dl = HuaweiFileDownload(
            exchangeEncrypted = { _, _, _, _ -> null },
            isConnected = { false },
            liveDownloadEnabled = true,
        )
        val out = dl.downloadSleepFiles()
        assertEquals("skipped", out.status)
        assertEquals("disconnected", out.reason)
    }

    @Test
    fun download_initTimeout_absent() {
        val dl = HuaweiFileDownload(
            exchangeEncrypted = { _, _, _, _ -> null },
            liveDownloadEnabled = true,
        )
        val out = dl.downloadSleepFiles(preferNewSync = true)
        assertEquals("absent", out.status)
        assertTrue(out.reason!!.contains("fail") || out.reason == "empty")
    }

    @Test
    fun download_emptyInit_absent() {
        // sleep_state only — size 0 → absent after complete.
        val responses = ArrayDeque(
            listOf(
                initResponse("sleep_state.bin", 0x0e, 1, 0),
            ),
        )
        val completes = ArrayList<HuaweiFraming.Frame>()
        val dl = HuaweiFileDownload(
            exchangeEncrypted = { _, _, _, _ -> responses.removeFirstOrNull() },
            sendEncrypted = { completes.add(it) },
            liveDownloadEnabled = true,
        )
        val out = dl.downloadSleepFiles(preferNewSync = true, startUnix = 0, endUnix = 1_700_000_000)
        assertEquals("absent", out.status)
        assertEquals(1, completes.size)
        assertEquals(HuaweiFileDownload.CMD_COMPLETE, completes[0].commandId)
    }

    @Test
    fun download_happyPath_sleepStateOnly() {
        val stateBytes = sleepStateBytes(
            start = 1_700_000_000,
            end = 1_700_014_400,
        )

        val encQueue = ArrayDeque<HuaweiFraming.Frame?>()
        encQueue.add(initResponse("sleep_state.bin", 0x0e, 7, stateBytes.size))
        encQueue.add(infoResponse(7, maxBlock = 64, noEncrypt = false))

        val blockQueue = ArrayDeque<ByteArray>()
        blockQueue.add(blockChunk(fileId = 7, offset = 0, data = stateBytes))

        val blockReqs = ArrayList<HuaweiFraming.Frame>()
        val dl = HuaweiFileDownload(
            exchangeEncrypted = { _, _, _, _ -> encQueue.removeFirstOrNull() },
            sendEncrypted = { frame ->
                if (frame.commandId == HuaweiFileDownload.CMD_REQUEST_BLOCK) {
                    blockReqs.add(frame)
                }
            },
            awaitRawBlock = { _, _ -> blockQueue.removeFirstOrNull() },
            liveDownloadEnabled = true,
        )
        val out = dl.downloadSleepFiles(preferNewSync = true, startUnix = 0, endUnix = 1_800_000_000)
        assertEquals("present", out.status)
        assertEquals(1, out.files.size)
        assertEquals("sleep_state", out.files[0].id)
        assertEquals(stateBytes.size, out.files[0].len)
        assertEquals(1, blockReqs.size)
        assertEquals(1, out.stateIntervals.size)
        assertEquals(1_700_000_000, out.stateIntervals[0].beginUnix)
    }

    @Test
    fun parseSleepStateIntervals_leRecords() {
        val buf = ByteBuffer.allocate(32).order(ByteOrder.LITTLE_ENDIAN)
        buf.putInt(1_700_000_000)
        buf.putInt(1_700_014_400)
        repeat(8) { buf.put(0) }
        buf.putInt(1_700_100_000)
        buf.putInt(1_700_110_000)
        repeat(8) { buf.put(0) }
        val intervals = HuaweiFileDownload.parseSleepStateIntervals(buf.array())
        assertEquals(2, intervals.size)
        assertEquals(1_700_000_000, intervals[0].beginUnix)
        assertEquals(1_700_014_400, intervals[0].endUnix)
    }

    @Test
    fun download_happyPath_persistsPaths() {
        val stateBytes = sleepStateBytes(start = 1_700_000_000, end = 1_700_014_400)
        val encQueue = ArrayDeque<HuaweiFraming.Frame?>()
        encQueue.add(initResponse("sleep_state.bin", 0x0e, 7, stateBytes.size))
        encQueue.add(infoResponse(7, maxBlock = 64, noEncrypt = false))
        val blockQueue = ArrayDeque<ByteArray>()
        blockQueue.add(blockChunk(fileId = 7, offset = 0, data = stateBytes))
        val persisted = LinkedHashMap<String, Int>()
        val dl = HuaweiFileDownload(
            exchangeEncrypted = { _, _, _, _ -> encQueue.removeFirstOrNull() },
            sendEncrypted = {},
            awaitRawBlock = { _, _ -> blockQueue.removeFirstOrNull() },
            liveDownloadEnabled = true,
            persistFile = { id, bytes ->
                persisted[id] = bytes.size
                "vitals/sleep_files/$id.bin"
            },
        )
        val out = dl.downloadSleepFiles(preferNewSync = true)
        assertEquals("vitals/sleep_files/sleep_state.bin", out.files[0].path)
        assertEquals(stateBytes.size, persisted["sleep_state"])
        assertEquals(1, out.files.size)
    }

    @Test
    fun download_productSpecs_neverIncludeSleepData() {
        // Regression: product Sync path must stay sleep_state-only.
        val responses = ArrayDeque(
            listOf(
                initResponse("sleep_state.bin", 0x0e, 1, 0),
            ),
        )
        val names = ArrayList<String>()
        val dl = HuaweiFileDownload(
            exchangeEncrypted = { req, _, _, _ ->
                val name = req.tlvs.firstOrNull { it.tag == 0x01 }?.value
                    ?.toString(Charsets.UTF_8)
                if (name != null) names.add(name)
                responses.removeFirstOrNull()
            },
            sendEncrypted = {},
            liveDownloadEnabled = true,
        )
        dl.downloadSleepFiles(preferNewSync = true, startUnix = 0, endUnix = 1)
        assertEquals(listOf("sleep_state.bin"), names)
        assertTrue(names.none { it.contains("sleep_data") })
    }

    @Test
    fun diagnosticNamedFile_jsonSummaries_redactsKeysNotValues() {
        val body = """{"avgHrv":64,"avgHeartRate":58,"avgBreathRate":14,"noise":"SECRET"}"""
            .toByteArray(Charsets.UTF_8)
        val encQueue = ArrayDeque<HuaweiFraming.Frame?>()
        encQueue.add(initResponse("SLEEP_DETAILS", 0x00, 3, body.size))
        encQueue.add(infoResponse(3, maxBlock = 256, noEncrypt = false))
        val blockQueue = ArrayDeque<ByteArray>()
        blockQueue.add(blockChunk(fileId = 3, offset = 0, data = body))
        val dl = HuaweiFileDownload(
            exchangeEncrypted = { _, _, _, _ -> encQueue.removeFirstOrNull() },
            sendEncrypted = {},
            awaitRawBlock = { _, _ -> blockQueue.removeFirstOrNull() },
            liveDownloadEnabled = true,
        )
        val out = dl.downloadDiagnosticNamedFileObserve(
            fileName = "SLEEP_DETAILS",
            fileType = 0x00,
            shortId = "cand-fd-sleep-details",
        )
        assertEquals("present", out.status)
        assertEquals(body.size, out.len)
        assertTrue(out.redactedKeys.contains("avgHrv"))
        assertTrue(out.overnightSummaryKeys.contains("avgHrv"))
        assertTrue(out.overnightSummaryKeys.contains("avgHeartRate"))
        assertTrue(out.overnightSummaryKeys.contains("avgBreathRate"))
        // Privacy: map must not embed body secret *values* (keys like "noise" may appear).
        val dumped = out.toMap().toString()
        assertTrue(!dumped.contains("SECRET"))
        assertTrue(out.redactedKeys.contains("noise"))
        assertTrue(!out.redactedKeys.contains("SECRET"))
    }

    @Test
    fun diagnosticNamedFile_empty_unmet() {
        val encQueue = ArrayDeque<HuaweiFraming.Frame?>()
        encQueue.add(initResponse("SLEEP_DETAILS", 0x00, 3, 0))
        val dl = HuaweiFileDownload(
            exchangeEncrypted = { _, _, _, _ -> encQueue.removeFirstOrNull() },
            sendEncrypted = {},
            liveDownloadEnabled = true,
        )
        val out = dl.downloadDiagnosticNamedFileObserve(
            fileName = "SLEEP_DETAILS",
            fileType = 0x00,
            shortId = "cand-fd-sleep-details",
        )
        assertEquals("absent", out.status)
        assertEquals("empty", out.reason)
    }

    @Test
    fun diagnosticNamedFile_flagOff_pendingCapture() {
        val dl = HuaweiFileDownload(
            exchangeEncrypted = { _, _, _, _ ->
                throw AssertionError("must soft-skip")
            },
            liveDownloadEnabled = false,
        )
        val out = dl.downloadDiagnosticNamedFileObserve(
            fileName = "SLEEP_DETAILS",
            fileType = 0x00,
            shortId = "x",
        )
        assertEquals("skipped", out.status)
        assertEquals("pending_capture", out.reason)
    }

    @Test
    fun sleepDataObserve_present_wipesAndOmitsBody() {
        // Synthetic TLV-like chunk: tag=0xA1 len=4 LE + payload
        val payload = byteArrayOf(0xA1.toByte(), 0x04, 0x00, 0x11, 0x22, 0x33, 0x44)
        val encQueue = ArrayDeque<HuaweiFraming.Frame?>()
        encQueue.add(initResponse("sleep_data.bin", 0x0f, 9, payload.size))
        encQueue.add(infoResponse(9, maxBlock = 64, noEncrypt = false))
        val blockQueue = ArrayDeque<ByteArray>()
        blockQueue.add(blockChunk(fileId = 9, offset = 0, data = payload))
        var wiped = false
        val dl = HuaweiFileDownload(
            exchangeEncrypted = { _, _, _, _ -> encQueue.removeFirstOrNull() },
            sendEncrypted = {},
            awaitRawBlock = { _, _ -> blockQueue.removeFirstOrNull() },
            liveDownloadEnabled = true,
        )
        val out = dl.downloadSleepDataStructureObserve(
            wipeBody = { wiped = true },
        )
        assertEquals("present", out.status)
        assertEquals(payload.size, out.len)
        assertTrue(wiped)
        assertTrue(out.tagHistogram.isNotEmpty())
        // Payload bytes must not appear as committed values — only tag/count/totalLen.
        assertTrue(out.tagHistogram.none { row -> row["tag"] == 0x11 })
        assertTrue(!out.toMap().toString().contains("0x11"))
    }

    @Test
    fun sleepDataObserve_midBlockFail_absent() {
        val encQueue = ArrayDeque<HuaweiFraming.Frame?>()
        encQueue.add(initResponse("sleep_data.bin", 0x0f, 9, 100))
        encQueue.add(infoResponse(9, maxBlock = 64, noEncrypt = false))
        val dl = HuaweiFileDownload(
            exchangeEncrypted = { _, _, _, _ -> encQueue.removeFirstOrNull() },
            sendEncrypted = {},
            awaitRawBlock = { _, _ -> null },
            liveDownloadEnabled = true,
        )
        val out = dl.downloadSleepDataStructureObserve()
        assertEquals("absent", out.status)
        assertTrue(out.reason!!.startsWith("fail"))
    }

    @Test
    fun observeBinaryStructure_privacySafeKeysOnly() {
        val json = """{"avgOxygenSaturation":98,"ppgBlob":"AABBCCDDEEFF"}"""
            .toByteArray()
        val obs = HuaweiFileDownload.observeBinaryStructure(json)
        assertTrue(obs.overnightSummaryKeys.any { it.contains("avgOxygen", ignoreCase = true) })
        assertTrue(!obs.redactedKeys.contains("AABBCCDDEEFF"))
        assertTrue(!obs.toMap().toString().contains("AABBCC"))
        val inventory = obs.privacyInventoryLog()
        assertTrue(inventory.contains("keyNames=["))
        assertTrue(inventory.contains("avgOxygenSaturation"))
        assertTrue(!inventory.contains("AABBCC"))
    }

    @Test
    fun framing_fileDownloadBlock_preservesRawBody() {
        val raw = byteArrayOf(0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0xAA.toByte(), 0xBB.toByte())
        val body = ByteArray(2 + raw.size)
        body[0] = HuaweiFileDownload.SVC_NEW.toByte()
        body[1] = HuaweiFileDownload.CMD_BLOCK.toByte()
        System.arraycopy(raw, 0, body, 2, raw.size)
        val encoded = HuaweiFraming.encodeRawBody(
            HuaweiFileDownload.SVC_NEW,
            HuaweiFileDownload.CMD_BLOCK,
            raw,
        )
        when (val result = HuaweiFraming.tryParse(encoded)) {
            is HuaweiFraming.ParseResult.Ok -> {
                assertEquals(HuaweiFileDownload.SVC_NEW, result.frame.serviceId)
                assertEquals(HuaweiFileDownload.CMD_BLOCK, result.frame.commandId)
                assertTrue(result.frame.rawBody.contentEquals(raw))
                assertTrue(result.frame.tlvs.isEmpty())
            }
            else -> throw AssertionError("expected Ok, got $result")
        }
    }

    private fun initResponse(
        name: String,
        type: Int,
        fileId: Int,
        size: Int,
    ): HuaweiFraming.Frame =
        HuaweiFraming.Frame(
            serviceId = HuaweiFileDownload.SVC_NEW,
            commandId = HuaweiFileDownload.CMD_INIT,
            tlvs = listOf(
                HuaweiFraming.Tlv(0x01, name.toByteArray(Charsets.UTF_8)),
                HuaweiFraming.Tlv(0x02, byteArrayOf(type.toByte())),
                HuaweiFraming.Tlv(0x03, byteArrayOf(fileId.toByte())),
                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(size)),
            ),
        )

    private fun infoResponse(
        fileId: Int,
        maxBlock: Int,
        noEncrypt: Boolean,
    ): HuaweiFraming.Frame =
        HuaweiFraming.Frame(
            serviceId = HuaweiFileDownload.SVC_NEW,
            commandId = HuaweiFileDownload.CMD_INFO,
            tlvs = listOf(
                HuaweiFraming.Tlv(0x01, byteArrayOf(fileId.toByte())),
                HuaweiFraming.Tlv(0x02, byteArrayOf(20)), // timeout sec
                HuaweiFraming.Tlv(0x03, HuaweiPacketCrypto.shortBe(256)), // burst
                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(maxBlock)),
                HuaweiFraming.Tlv(0x05, byteArrayOf(if (noEncrypt) 0x01 else 0x00)),
            ),
        )

    private fun blockChunk(fileId: Int, offset: Int, data: ByteArray): ByteArray {
        val buf = ByteBuffer.allocate(6 + data.size).order(ByteOrder.BIG_ENDIAN)
        buf.put(fileId.toByte())
        buf.putInt(offset)
        buf.put(0x00)
        buf.put(data)
        return buf.array()
    }

    private fun sleepStateBytes(start: Int, end: Int): ByteArray {
        val buf = ByteBuffer.allocate(16).order(ByteOrder.LITTLE_ENDIAN)
        buf.putInt(start)
        buf.putInt(end)
        repeat(8) { buf.put(0) }
        return buf.array()
    }
}
