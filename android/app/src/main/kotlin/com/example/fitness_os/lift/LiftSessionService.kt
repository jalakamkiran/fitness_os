package com.example.fitness_os.lift

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.example.fitness_os.MainActivity
import com.example.fitness_os.R

/**
 * Session-scoped foreground service — keeps RFCOMM up during a lift session.
 * Started only when the user starts a lift session (not auto-sync).
 */
class LiftSessionService : Service() {
    companion object {
        const val CHANNEL_ID = "fathom_lift_session"
        const val NOTIFICATION_ID = 4812
        const val ACTION_START = "com.example.fitness_os.lift.START"
        const val ACTION_STOP = "com.example.fitness_os.lift.STOP"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"

        fun start(context: Context, title: String, body: String) {
            val intent = Intent(context, LiftSessionService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_BODY, body)
            }
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, LiftSessionService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Fathom Lift",
                NotificationManager.IMPORTANCE_LOW,
            )
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START, null -> {
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Fathom Lift"
                val body = intent?.getStringExtra(EXTRA_BODY) ?: "Session active"
                startForeground(NOTIFICATION_ID, buildNotification(title, body))
            }
        }
        return START_STICKY
    }

    private fun buildNotification(title: String, body: String): Notification {
        val launch = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(launch)
            .setOngoing(true)
            .build()
    }
}