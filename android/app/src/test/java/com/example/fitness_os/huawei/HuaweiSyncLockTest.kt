package com.example.fitness_os.huawei

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HuaweiSyncLockTest {

    @Test
    fun tryAcquire_refusesOverlap() {
        val lock = HuaweiSyncLock()
        assertTrue(lock.tryAcquire())
        assertTrue(lock.isHeld)
        assertFalse(lock.tryAcquire())
        lock.release()
        assertFalse(lock.isHeld)
        assertTrue(lock.tryAcquire())
        lock.release()
    }
}
