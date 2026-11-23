package com.example.fitness_os.huawei

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class HuaweiSleepDetailsSequenceParserTest {

    @Test
    fun parse_syntheticFixture_summaryAndStages() {
        val bytes = buildSynthetic()
        val parsed = HuaweiSleepDetailsSequenceParser.parse(bytes)
        assertNotNull(parsed)
        assertEquals(HuaweiSleepDetailsSequenceParser.DICT_CLASS, parsed!!.dictId)
        assertEquals(1, parsed.sessions.size)
        val s = parsed.sessions.first()
        assertEquals(1_700_000_000, s.beginUnix)
        assertEquals(1_700_003_600, s.endUnix)
        assertEquals(88, s.sleepScore)
        assertEquals(40, s.avgHrv)
        assertEquals(58, s.avgHeartRate)
        assertEquals(14, s.avgBreathRate)
        assertEquals(97, s.avgOxygenSaturation)
        assertEquals(3, s.stages.size)
        assertEquals(
            HuaweiSleepDetailsSequenceParser.STAGE_AWAKE,
            s.stages[0].stage,
        )
        assertEquals(600, s.stages[0].durationSec)
        assertEquals(
            HuaweiSleepDetailsSequenceParser.STAGE_LIGHT,
            s.stages[1].stage,
        )
        assertEquals(
            HuaweiSleepDetailsSequenceParser.STAGE_DEEP,
            s.stages[2].stage,
        )
        val mins = HuaweiSleepDetailsSequenceParser.stageMinutes(s.stages)
        assertEquals(10, mins["awake"])
        assertEquals(30, mins["light"])
        assertEquals(20, mins["deep"])
        assertTrue(s.toMap()["stages"] is List<*>)
    }

    @Test
    fun toProductStages_subMinuteFragments_doNotInflateToSixtyMinutes() {
        val begin = 1_700_000_000
        val segments = List(60) {
            HuaweiSleepDetailsSequenceParser.StageSegment(
                durationSec = 10,
                stage = HuaweiSleepDetailsSequenceParser.STAGE_LIGHT,
            )
        }
        val product = HuaweiSleepDetailsSequenceParser.toProductStages(begin, segments)
        val sumMin = product.sumOf { (it["durationMin"] as Int) }
        assertEquals(10, sumMin)
    }

    @Test
    fun parse_rejectsWrongDictClass() {
        val bytes = buildSynthetic(dictId = 1)
        assertEquals(null, HuaweiSleepDetailsSequenceParser.parse(bytes))
    }

    /** Minimal SEQUENCE_DATA bytes matching observed GT5 layout (no personal data). */
    private fun buildSynthetic(dictId: Int = 700_013): ByteArray {
        val start = 1_700_000_000
        val end = 1_700_003_600
        val stages = listOf(
            600 to HuaweiSleepDetailsSequenceParser.STAGE_AWAKE,
            1800 to HuaweiSleepDetailsSequenceParser.STAGE_LIGHT,
            1200 to HuaweiSleepDetailsSequenceParser.STAGE_DEEP,
        )
        val detailLen = stages.size * 8

        fun field(fid: Int, type: Int, value: ByteArray): ByteArray {
            val inner = ByteBuffer.allocate(2 + 4 + 3 + 2 + value.size)
                .order(ByteOrder.BIG_ENDIAN)
            inner.put(0x03.toByte()).put(0x04.toByte()).putInt(fid)
            inner.put(0x04.toByte()).put(0x01.toByte()).put(type.toByte())
            inner.put(0x05.toByte()).put(value.size.toByte()).put(value)
            val body = inner.array()
            return byteArrayOf(0x82.toByte(), body.size.toByte()) + body
        }

        val summary = field(700_013_878, 2, intBe(40)) +
            field(700_013_580, 2, intBe(58)) +
            field(700_013_886, 2, intBe(14)) +
            field(700_013_468, 2, intBe(97)) +
            field(700_013_686, 2, intBe(start)) +
            field(700_013_156, 2, intBe(end)) +
            field(700_013_245, 1, byteArrayOf(88.toByte()))

        val stageBytes = ByteBuffer.allocate(detailLen).order(ByteOrder.LITTLE_ENDIAN)
        for ((dur, st) in stages) {
            stageBytes.putInt(dur)
            stageBytes.putInt(st)
        }

        val recordBody = ByteArray(32 + summary.size + detailLen)
        val record = ByteBuffer.wrap(recordBody).order(ByteOrder.BIG_ENDIAN)
        record.putInt(start)
        record.putInt(end)
        record.putShort(0x0102)
        record.putShort(0x01b2.toShort())
        record.putInt(detailLen)
        record.putInt(0)
        // remaining 16 B of 32 B header already zero
        record.position(32)
        record.put(summary)
        record.put(stageBytes.array())

        val out = ByteArray(32 + recordBody.size)
        val payload = ByteBuffer.wrap(out).order(ByteOrder.BIG_ENDIAN)
        payload.putInt(out.size)
        payload.putInt(dictId)
        payload.putShort(1)
        payload.putShort(1)
        payload.position(32)
        payload.put(recordBody)
        return out
    }

    private fun intBe(v: Int): ByteArray =
        ByteBuffer.allocate(4).order(ByteOrder.BIG_ENDIAN).putInt(v).array()
}
