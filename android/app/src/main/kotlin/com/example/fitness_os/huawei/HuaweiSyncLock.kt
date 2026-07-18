package com.example.fitness_os.huawei

/**
 * Native SoT single-flight lock for product Sync (activity + workouts).
 * Checked before sessionIo enqueue so overlap returns busy, not queued success.
 */
class HuaweiSyncLock {
    @Volatile
    private var inFlight: Boolean = false

    fun tryAcquire(): Boolean {
        synchronized(this) {
            if (inFlight) return false
            inFlight = true
            return true
        }
    }

    fun release() {
        synchronized(this) {
            inFlight = false
        }
    }

    val isHeld: Boolean
        get() = inFlight
}
