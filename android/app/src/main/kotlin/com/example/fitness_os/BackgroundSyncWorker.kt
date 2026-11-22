package com.example.fitness_os

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkRequest
import androidx.work.WorkerParameters
import com.example.fitness_os.huawei.HuaweiBtPlugin
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.TimeUnit

class BackgroundSyncWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    @Volatile
    private var syncChannel: MethodChannel? = null

    override suspend fun doWork(): Result {
        if (AppForeground.isResumed) {
            return Result.success()
        }

        var engine: FlutterEngine? = null
        val doneDeferred = CompletableDeferred<Map<String, Any?>>()

        try {
            running = this

            withContext(Dispatchers.Main) {
                val ctx = applicationContext
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(ctx)
                loader.ensureInitializationComplete(ctx, null)

                engine = FlutterEngine(ctx)
                val huawei = HuaweiBtPlugin(ctx) { null }
                huawei.register(engine!!)

                val channel = MethodChannel(
                    engine!!.dartExecutor.binaryMessenger,
                    CHANNEL,
                )
                syncChannel = channel
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "done" -> {
                            @Suppress("UNCHECKED_CAST")
                            val payload =
                                (call.arguments as? Map<String, Any?>) ?: emptyMap()
                            if (!doneDeferred.isCompleted) {
                                doneDeferred.complete(payload)
                            }
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }

                val entrypoint = DartExecutor.DartEntrypoint(
                    loader.findAppBundlePath(),
                    DART_ENTRYPOINT,
                )
                engine!!.dartExecutor.executeDartEntrypoint(entrypoint)
            }

            val payload = withTimeoutOrNull(SYNC_TIMEOUT_MS) {
                doneDeferred.await()
            } ?: return Result.retry()

            val ok = payload["ok"] as? Boolean ?: false
            return if (ok) Result.success() else Result.retry()
        } catch (_: Exception) {
            return Result.retry()
        } finally {
            syncChannel = null
            withContext(Dispatchers.Main) {
                engine?.destroy()
            }
            if (running === this) {
                running = null
            }
        }
    }

    fun abort() {
        mainHandler.post {
            syncChannel?.invokeMethod("abort", null)
        }
    }

    companion object {
        private const val CHANNEL = "fathom/background_sync"
        private const val DART_ENTRYPOINT = "backgroundSyncMain"
        private const val WORK_NAME = "BackendSyncWork"
        private const val SYNC_INTERVAL_HOURS = 1L
        private const val SYNC_TIMEOUT_MS = 8 * 60 * 1000L

        private val mainHandler = Handler(Looper.getMainLooper())

        @Volatile
        var running: BackgroundSyncWorker? = null

        fun abortIfRunning() {
            running?.abort()
        }

        fun schedule(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val syncWork = PeriodicWorkRequestBuilder<BackgroundSyncWorker>(
                SYNC_INTERVAL_HOURS,
                TimeUnit.HOURS,
                15,
                TimeUnit.MINUTES,
            )
                .setConstraints(constraints)
                .setBackoffCriteria(
                    BackoffPolicy.EXPONENTIAL,
                    WorkRequest.MIN_BACKOFF_MILLIS,
                    TimeUnit.MILLISECONDS,
                )
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                syncWork,
            )
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        }
    }
}