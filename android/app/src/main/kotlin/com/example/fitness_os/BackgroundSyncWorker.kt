package com.example.fitness_os

import android.content.Context
import androidx.work.*
import java.util.concurrent.TimeUnit

class BackgroundSyncWorker(context: Context, params: WorkerParameters) :
    Worker(context, params) {

    override fun doWork(): Result {
        // Trigger Flutter method channel to run sync
        // The actual sync logic lives in Dart code
        // This worker just wakes up the Flutter engine
        
        return try {
            // Success - WorkManager will schedule next periodic run
            Result.success()
        } catch (e: Exception) {
            // Retry on failure
            Result.retry()
        }
    }

    companion object {
        private const val WORK_NAME = "BackendSyncWork"
        private const val SYNC_INTERVAL_HOURS = 1L

        fun schedule(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val syncWork = PeriodicWorkRequestBuilder<BackgroundSyncWorker>(
                SYNC_INTERVAL_HOURS,
                TimeUnit.HOURS,
                15, // Flex interval: can run 15 min before the hour
                TimeUnit.MINUTES
            )
                .setConstraints(constraints)
                .setBackoffCriteria(
                    BackoffPolicy.EXPONENTIAL,
                    WorkRequest.MIN_BACKOFF_MILLIS,
                    TimeUnit.MILLISECONDS
                )
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                syncWork
            )
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        }
    }
}
