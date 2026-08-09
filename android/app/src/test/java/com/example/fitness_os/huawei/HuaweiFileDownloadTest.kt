package com.example.fitness_os.huawei

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HuaweiFileDownloadTest {

    @Test
    fun probe_softSkipByDefault_pendingCapture() {
        val dl = HuaweiFileDownload(
            exchangeEncrypted = { _, _, _, _ ->
                throw AssertionError("live exchange must not run when soft-skip")
            },
            liveProbeEnabled = false,
        )
        val out = dl.probeSleepFiles(preferNewSync = true)
        assertEquals("skipped", out.status)
        assertEquals(HuaweiFileDownload.SVC_NEW, out.serviceId)
        assertEquals("pending_capture", out.reason)
        assertTrue(out.files.isEmpty())
    }

    @Test
    fun probe_liveTimeout_returnsAbsent() {
        val dl = HuaweiFileDownload(
            exchangeEncrypted = { _, _, _, _ -> null },
            liveProbeEnabled = true,
        )
        val out = dl.probeSleepFiles(preferNewSync = false)
        assertEquals("absent", out.status)
        assertEquals(HuaweiFileDownload.SVC_LEGACY, out.serviceId)
        assertTrue(out.reason!!.startsWith("timeout:"))
    }

    @Test
    fun probe_disconnected_skipped() {
        val dl = HuaweiFileDownload(
            exchangeEncrypted = { _, _, _, _ -> null },
            isConnected = { false },
            liveProbeEnabled = true,
        )
        val out = dl.probeSleepFiles()
        assertEquals("skipped", out.status)
        assertEquals("disconnected", out.reason)
    }
}
