package com.example.fitness_os.huawei

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class HuaweiPhysioCaptureProbeTest {

    @Test
    fun run_dictPresent_skipsSleepDataWhenOvernightKeysFound() {
        val body = """{"avgHrv":12,"avgBreathRate":14}""".toByteArray()
        val probe = HuaweiPhysioCaptureProbe(
            fileDownload = {
                scriptedDownload(mapOf(HuaweiFileDownload.FILE_SEQUENCE_DATA to body))
            },
            listenFeatureUploadSequence = { null },
        )
        val out = probe.run(
            HuaweiPhysioCaptureProbe.Options(
                includeDict = true,
                includeSleepData = true,
                includePath2Intervals = false,
            ),
        )
        assertEquals("ok", out["status"])
        assertEquals(false, out["feedsProductSleepSot"])
        assertEquals(false, out["unmetOvernightSummary"])
        @Suppress("UNCHECKED_CAST")
        val keys = out["overnightSummaryKeys"] as List<*>
        assertTrue(keys.contains("avgHrv"))
        @Suppress("UNCHECKED_CAST")
        val attempts = out["dictAttempts"] as List<Map<String, Any?>>
        assertEquals("cand-fd-seq-dict", attempts.first()["candidateId"])
        assertEquals(
            HuaweiFileDownload.DICT_SLEEP_DETAILS_CLASS,
            attempts.first()["dictId"],
        )
        @Suppress("UNCHECKED_CAST")
        val sleepData = out["sleepData"] as Map<String, Any?>
        assertEquals("skipped", sleepData["status"])
        assertEquals("overnight_summaries_already_present", sleepData["reason"])
    }

    @Test
    fun run_dictAbsent_observesSleepData() {
        val sleepPayload = byteArrayOf(0x01, 0x02, 0x00, 0x55, 0x66)
        val probe = HuaweiPhysioCaptureProbe(
            fileDownload = {
                scriptedDownload(mapOf(HuaweiFileDownload.FILE_SLEEP_DATA to sleepPayload))
            },
            listenFeatureUploadSequence = { null },
        )
        val out = probe.run(
            HuaweiPhysioCaptureProbe.Options(
                includeDict = true,
                includeSleepData = true,
            ),
        )
        @Suppress("UNCHECKED_CAST")
        val attempts = out["dictAttempts"] as List<Map<String, Any?>>
        // primary SEQUENCE_DATA + 2 legacy routes × 2 types + FU listen
        assertEquals(6, attempts.size)
        assertEquals("cand-fd-seq-dict", attempts.first()["candidateId"])
        assertTrue(attempts.all { it["status"] == "absent" })
        @Suppress("UNCHECKED_CAST")
        val sleepData = out["sleepData"] as Map<String, Any?>
        assertEquals("present", sleepData["status"])
        assertEquals(sleepPayload.size, sleepData["len"])
        assertEquals(true, out["unmetOvernightSummary"])
    }

    @Test
    fun run_path2_recordsIntervalProxyWithoutSeries() {
        val probe = HuaweiPhysioCaptureProbe(
            fileDownload = { scriptedDownload(emptyMap()) },
            listenFeatureUploadSequence = { null },
            pullIntervalProxy = { _, _, _ ->
                mapOf(
                    "status" to "present",
                    "class" to "interval-proxy",
                    "hrBitmapDays" to 1,
                    "sampleCount" to 40,
                    "tagLenHistograms" to listOf("t=81:len=12x1"),
                    "lastNightSleepMinutes" to 300,
                    "lastNightHrMinutes" to 10,
                    "lastNightSpo2HintMinutes" to 0,
                    "lastNightHrCoveragePct" to 3,
                )
            },
        )
        val out = probe.run(
            HuaweiPhysioCaptureProbe.Options(
                includeDict = false,
                includeSleepData = false,
                includePath2Intervals = true,
            ),
        )
        @Suppress("UNCHECKED_CAST")
        val path2 = out["path2Intervals"] as Map<String, Any?>
        assertEquals("interval-proxy", path2["class"])
        assertEquals("present", path2["status"])
        assertFalse(path2.containsKey("samples"))
        assertFalse(out.toString().contains("bpm"))
    }

    private fun scriptedDownload(files: Map<String, ByteArray>): HuaweiFileDownload {
        var activeBody = ByteArray(0)
        val blockQueue = ArrayDeque<ByteArray>()
        return HuaweiFileDownload(
            exchangeEncrypted = { req, _, cmd, _ ->
                when (cmd) {
                    HuaweiFileDownload.CMD_INIT -> {
                        val name = req.tlvs.firstOrNull { it.tag == 0x01 }?.value
                            ?.toString(Charsets.UTF_8)
                            .orEmpty()
                        activeBody = files[name] ?: ByteArray(0)
                        blockQueue.clear()
                        if (activeBody.isNotEmpty()) {
                            blockQueue.add(blockChunk(1, 0, activeBody))
                        }
                        initResponse(name, activeBody.size)
                    }
                    HuaweiFileDownload.CMD_INFO ->
                        infoResponse(1, maxOf(64, activeBody.size))
                    else -> null
                }
            },
            sendEncrypted = {},
            awaitRawBlock = { _, _ -> blockQueue.removeFirstOrNull() },
            liveDownloadEnabled = true,
        )
    }

    private fun initResponse(name: String, size: Int): HuaweiFraming.Frame =
        HuaweiFraming.Frame(
            serviceId = HuaweiFileDownload.SVC_NEW,
            commandId = HuaweiFileDownload.CMD_INIT,
            tlvs = listOf(
                HuaweiFraming.Tlv(0x01, name.toByteArray(Charsets.UTF_8)),
                HuaweiFraming.Tlv(0x02, byteArrayOf(0x00)),
                HuaweiFraming.Tlv(0x03, byteArrayOf(1)),
                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(size)),
            ),
        )

    private fun infoResponse(fileId: Int, maxBlock: Int): HuaweiFraming.Frame =
        HuaweiFraming.Frame(
            serviceId = HuaweiFileDownload.SVC_NEW,
            commandId = HuaweiFileDownload.CMD_INFO,
            tlvs = listOf(
                HuaweiFraming.Tlv(0x01, byteArrayOf(fileId.toByte())),
                HuaweiFraming.Tlv(0x02, byteArrayOf(20)),
                HuaweiFraming.Tlv(0x03, HuaweiPacketCrypto.shortBe(256)),
                HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(maxBlock)),
                HuaweiFraming.Tlv(0x05, byteArrayOf(0x00)),
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
}
