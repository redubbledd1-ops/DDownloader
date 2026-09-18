package com.example.downoader

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import java.util.concurrent.atomic.AtomicInteger

/**
 * Houdt het app-proces (en daarmee het yt-dlp/python-kindproces) in leven
 * zolang er gedownload wordt.
 *
 * youtubedl-android start yt-dlp als los kindproces via ProcessBuilder. Zonder
 * foreground service staat ons proces op een lage oom_adj-prioriteit: zodra het
 * geheugen krap wordt — en een downloadend python-proces met meerdere fragment-
 * buffers maakt het krap — ruimt Androids lowmemorykiller het op. Vanaf Android
 * 12 ruimt de PhantomProcessKiller bovendien juist dit soort kindprocessen op.
 * Voor de gebruiker ziet dat er uit alsof de app "minimaliseert" en daarna met
 * splashscreen opnieuw laadt, terwijl de taak in recents blijft staan.
 *
 * Een foreground service tilt het hele proces naar FOREGROUND_SERVICE-prioriteit
 * en stelt het vrij van de phantom-process-limiet; de wakelock houdt de CPU aan
 * als het scherm uit gaat.
 */
class DownloadKeepAliveService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopEverything()
            return START_NOT_STICKY
        }
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Bezig met downloaden..."
        startForegroundCompat(text)
        acquireWakeLock()
        // NOT_STICKY: als het systeem ons alsnog afschiet moet de app niet
        // vanzelf opnieuw opstarten — dat is precies het "herstart"-gedrag dat
        // we hier proberen te voorkomen.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    private fun stopEverything() {
        releaseWakeLock()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun startForegroundCompat(text: String) {
        val notification = buildNotification(text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(text: String): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            manager.getNotificationChannel(CHANNEL_ID) == null
        ) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Downloads",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    setShowBadge(false)
                    enableVibration(false)
                },
            )
        }
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Downloader")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(contentIntent)
            .build()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "downoader:download",
        ).also {
            it.setReferenceCounted(false)
            // Harde bovengrens: een vergeten wakelock mag nooit de accu leegtrekken.
            it.acquire(4 * 60 * 60 * 1000L)
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
    }

    companion object {
        private const val CHANNEL_ID = "downoader_downloads"
        private const val NOTIFICATION_ID = 4711
        private const val ACTION_STOP = "com.example.downoader.STOP_KEEPALIVE"
        private const val EXTRA_TEXT = "text"

        // Downloaden en yt-dlp bijwerken kunnen los van elkaar bescherming
        // vragen. Zonder telling zou de eerste die klaar is de service voor de
        // ander ook afzetten.
        private val holders = AtomicInteger(0)

        /** Vraagt bescherming aan; elke start hoort een stop te krijgen. */
        fun start(context: Context, text: String) {
            holders.incrementAndGet()
            send(context, text)
        }

        /** Werkt alleen de notificatietekst bij, zonder de telling te raken. */
        fun updateText(context: Context, text: String) {
            if (holders.get() > 0) send(context, text)
        }

        private fun send(context: Context, text: String) {
            val intent = Intent(context, DownloadKeepAliveService::class.java)
                .putExtra(EXTRA_TEXT, text)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (_: Exception) {
                // Geen foreground service kunnen starten mag een download nooit
                // blokkeren; dan draaien we zoals voorheen zonder bescherming.
            }
        }

        fun stop(context: Context) {
            if (holders.decrementAndGet() > 0) return
            holders.set(0)
            try {
                context.startService(
                    Intent(context, DownloadKeepAliveService::class.java)
                        .setAction(ACTION_STOP),
                )
            } catch (_: Exception) {
                try {
                    context.stopService(Intent(context, DownloadKeepAliveService::class.java))
                } catch (_: Exception) {
                }
            }
        }
    }
}
