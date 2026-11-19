package com.jnote.app

import android.app.Notification
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings

/**
 * Rings a due reminder with the sound and vibration of the "Reminders" category, until Snooze,
 * Dismiss, a tap on it, or the silence alarm. The app plays them here, not the notification,
 * because Android silences an insistent notification as soon as the notification shade opens.
 * Runs only while a reminder rings.
 */
class RingService : Service() {
    private var player: MediaPlayer? = null
    private var focus: AudioFocusRequest? = null
    private var vibrator: Vibrator? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val n = shown ?: return START_NOT_STICKY.also { stopSelf() }
        if (service === this) return START_NOT_STICKY // a second start while it already rings
        try {
            if (Build.VERSION.SDK_INT >= 34) startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED)
            else startForeground(ID, n)
        } catch (e: Exception) {
            // Refused after all: let the notification ring instead.
            ringing.takeIf { it != 0 }?.let { Reminders.repost(this, it, Reminders.SOUND) }
            ringing = 0
        }
        if (ringing == 0) { // stopped before it started
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        service = this
        alert()
        return START_NOT_STICKY
    }

    private fun alert() {
        if (player != null || vibrator != null) return
        val channel = getSystemService(NotificationManager::class.java).getNotificationChannel(Reminders.SOUND)
        if (channel == null || channel.importance < NotificationManager.IMPORTANCE_DEFAULT) return // set to silent
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val sound = channel.sound
        if (sound != null) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT).setAudioAttributes(attrs).build()
            // Refused during a call: then it only vibrates.
            if (getSystemService(AudioManager::class.java).requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                focus = request
                // The picked sound may be unreadable to the app (a file only the system may open).
                player = listOf(sound, Settings.System.DEFAULT_ALARM_ALERT_URI, Settings.System.DEFAULT_NOTIFICATION_URI)
                    .firstNotNullOfOrNull { play(it, attrs) }
            }
        }
        if (channel.shouldVibrate()) {
            val pattern = channel.vibrationPattern?.takeIf { p -> p.any { it > 0 } } ?: longArrayOf(0, 600, 600)
            vibrator = getSystemService(Vibrator::class.java)?.takeIf { it.hasVibrator() }?.apply {
                @Suppress("DEPRECATION") // the replacement needs Android 13
                vibrate(VibrationEffect.createWaveform(pattern, 0), attrs)
            }
        }
    }

    private fun play(uri: Uri, attrs: AudioAttributes): MediaPlayer? {
        val p = MediaPlayer()
        return try {
            // "Default sound" links go through a cache file that can be empty, and media links may be
            // in a canonical form the media server can't open: play the sound file itself.
            val actual = if (uri.authority == Settings.AUTHORITY) {
                RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.getDefaultType(uri)) ?: uri
            } else uri
            p.setAudioAttributes(attrs)
            p.setDataSource(this, contentResolver.uncanonicalize(actual) ?: actual)
            p.isLooping = true
            p.prepare()
            p.start()
            p
        } catch (e: Exception) {
            p.release()
            null
        }
    }

    override fun onDestroy() {
        player?.release()
        player = null
        focus?.let { getSystemService(AudioManager::class.java).abandonAudioFocusRequest(it) }
        vibrator?.cancel()
        if (service === this) service = null
        super.onDestroy()
    }

    companion object {
        private const val ID = Int.MAX_VALUE // apart from the notes' ids, which the reminders' own notifications use
        private var service: RingService? = null
        private var ringing = 0
        private var shown: Notification? = null

        /** Starts ringing for reminder [id]. False when Android doesn't allow it (Android 12+ after an inexact alarm). */
        fun ring(ctx: Context, id: Int, n: Notification): Boolean {
            val earlier = ringing
            service?.let {
                // One rings at a time: the newer reminder takes over, the earlier one stays as a quiet notification.
                ringing = id
                shown = n
                ctx.getSystemService(NotificationManager::class.java).notify(ID, n)
                if (earlier != 0 && earlier != id) Reminders.repost(ctx, earlier, Reminders.QUIET)
                return true
            }
            ringing = id
            shown = n
            return try {
                ctx.startForegroundService(Intent(ctx, RingService::class.java))
                if (earlier != 0 && earlier != id) Reminders.repost(ctx, earlier, Reminders.QUIET)
                true
            } catch (e: Exception) {
                ringing = earlier
                false
            }
        }

        /** Stops ringing when reminder [id] is the one ringing here. */
        fun stop(id: Int): Boolean {
            if (id == 0 || id != ringing) return false
            ringing = 0
            service?.run {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            return true
        }
    }
}
