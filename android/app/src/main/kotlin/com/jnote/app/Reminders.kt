package com.jnote.app

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.os.Build
import android.provider.Settings

/**
 * Reminder alarms. Nothing here runs unless the user set a reminder: no polling, and the
 * ringing service (RingService) runs only while a reminder rings.
 */
object Reminders {
    /** The "Reminders" category: its sound and vibration are the ones a reminder rings with. */
    const val SOUND = "reminders"
    /** Silent: shows the reminder while RingService plays the sound. */
    const val RINGING = "ringing"
    const val QUIET = "reminders_quiet"
    const val FIRE = "com.jnote.app.FIRE"
    const val SILENCE = "com.jnote.app.SILENCE"
    const val SNOOZE = "com.jnote.app.SNOOZE"
    const val DISMISS = "com.jnote.app.DISMISS"
    private const val RING_MS = 10 * 60_000L
    private const val LATE_MS = 60_000L
    private const val SNOOZE_MS = 10 * 60_000L

    /** True when a reminder can show: notifications are allowed and the Reminders category isn't switched off. */
    fun notificationsOn(ctx: Context): Boolean {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        return nm.areNotificationsEnabled() &&
            nm.getNotificationChannel(SOUND)?.importance != NotificationManager.IMPORTANCE_NONE
    }

    fun canExact(ctx: Context): Boolean =
        Build.VERSION.SDK_INT < 31 || ctx.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()

    /** Sets the alarm (replacing any earlier one for this note). Returns false when it is inexact. */
    fun schedule(ctx: Context, id: Int, at: Long): Boolean {
        val am = ctx.getSystemService(AlarmManager::class.java)
        val exact = canExact(ctx)
        // Not setAlarmClock: that would show up as the phone's "next alarm" for other apps.
        if (exact) am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent(ctx, FIRE, id))
        else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent(ctx, FIRE, id))
        setBootReceiver(ctx, true)
        return exact
    }

    fun cancel(ctx: Context, id: Int) {
        ctx.getSystemService(AlarmManager::class.java).cancel(intent(ctx, FIRE, id))
        stopRinging(ctx, id)
    }

    /** Re-sets every pending reminder: after a reboot, an app update, a force-stop or a newly granted exact-alarm permission. */
    fun resync(ctx: Context) {
        val now = System.currentTimeMillis()
        val pending = NoteStore.with(ctx) { it.pendingReminders() }
        for ((id, at) in pending) {
            // Missed while the phone was off: show it quietly instead of ringing late.
            if (at > now - LATE_MS) schedule(ctx, id, at) else fire(ctx, id, ring = false)
        }
        setBootReceiver(ctx, pending.any { it.second > now - LATE_MS })
    }

    fun fire(ctx: Context, id: Int, ring: Boolean) {
        val note = NoteStore.with(ctx) { store ->
            store.note(id)?.takeIf { it.at != null && it.at <= System.currentTimeMillis() + LATE_MS }
                ?.also { store.setReminder(id, null) }
        } ?: return // deleted, removed, or moved to a later time
        createChannels(ctx)
        val nm = ctx.getSystemService(NotificationManager::class.java)
        // Never ring without a notification to stop it from.
        if (!ring || !notificationsOn(ctx)) return post(ctx, note, QUIET)
        // RingService keeps ringing when the shade opens. Android 12+ refuses it after an inexact
        // alarm; then an insistent notification rings instead, which the shade does silence.
        val shown = nm.getNotificationChannel(RINGING)?.importance != NotificationManager.IMPORTANCE_NONE
        if (!shown || !RingService.ring(ctx, note.id, build(ctx, note, RINGING))) post(ctx, note, SOUND)
        // Exact when allowed: an inexact alarm here lets it ring longer.
        val am = ctx.getSystemService(AlarmManager::class.java)
        val stop = System.currentTimeMillis() + RING_MS
        if (canExact(ctx)) am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, stop, intent(ctx, SILENCE, id))
        else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, stop, intent(ctx, SILENCE, id))
    }

    /** After RING_MS of ringing, keep the reminder as a quiet notification. */
    fun silence(ctx: Context, id: Int) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (!RingService.stop(id) && nm.activeNotifications.none { it.id == id }) return
        repost(ctx, id, QUIET)
    }

    /** Shows the reminder again: quietly, or (SOUND) ringing as an insistent notification. */
    fun repost(ctx: Context, id: Int, channel: String) {
        val note = NoteStore.with(ctx) { it.note(id) } ?: return
        ctx.getSystemService(NotificationManager::class.java).cancel(id) // cancelling is what reliably stops an insistent sound
        post(ctx, note, channel)
    }

    fun snooze(ctx: Context, id: Int) {
        stopRinging(ctx, id)
        val at = System.currentTimeMillis() + SNOOZE_MS
        NoteStore.with(ctx) { it.setReminder(id, at) }
        schedule(ctx, id, at)
    }

    /** Stops the sound and removes the reminder's notification, however it rings. */
    fun stopRinging(ctx: Context, id: Int) {
        RingService.stop(id)
        ctx.getSystemService(NotificationManager::class.java).cancel(id)
        ctx.getSystemService(AlarmManager::class.java).cancel(intent(ctx, SILENCE, id))
    }

    private fun post(ctx: Context, note: NoteStore.Reminder, channel: String) {
        val notification = build(ctx, note, channel)
        if (channel == SOUND) notification.flags = notification.flags or Notification.FLAG_INSISTENT
        ctx.getSystemService(NotificationManager::class.java).notify(note.id, notification)
    }

    private fun build(ctx: Context, note: NoteStore.Reminder, channel: String): Notification {
        val open = PendingIntent.getActivity(
            ctx, note.id,
            Intent(ctx, MainActivity::class.java).putExtra(MainActivity.EXTRA_DAY, note.day)
                .putExtra(MainActivity.EXTRA_REMINDER, note.id)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return Notification.Builder(ctx, channel)
            .setSmallIcon(R.drawable.ic_stat_note)
            .setContentTitle(ctx.getString(R.string.reminder_title))
            .setContentText(note.text)
            .setStyle(Notification.BigTextStyle().bigText(note.text))
            .setCategory(Notification.CATEGORY_REMINDER)
            .setContentIntent(open)
            .setDeleteIntent(intent(ctx, DISMISS, note.id)) // swiping a ringing reminder away stops it
            .setAutoCancel(true)
            .addAction(Notification.Action.Builder(null, ctx.getString(R.string.snooze), intent(ctx, SNOOZE, note.id)).build())
            .addAction(Notification.Action.Builder(null, ctx.getString(R.string.dismiss), intent(ctx, DISMISS, note.id)).build())
            .apply { if (Build.VERSION.SDK_INT >= 31) setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE) }
            .build()
    }

    fun createChannels(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(RINGING) != null) return
        nm.createNotificationChannel(
            NotificationChannel(RINGING, ctx.getString(R.string.channel_ringing), NotificationManager.IMPORTANCE_HIGH).apply {
                description = ctx.getString(R.string.channel_ringing_desc)
                setSound(null, null)
                enableVibration(false)
            }
        )
        // On an existing channel this only refreshes the name and description, never the user's sound.
        nm.createNotificationChannel(
            NotificationChannel(SOUND, ctx.getString(R.string.channel_reminders), NotificationManager.IMPORTANCE_HIGH).apply {
                description = ctx.getString(R.string.channel_reminders_desc)
                setSound(
                    Settings.System.DEFAULT_ALARM_ALERT_URI,
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                enableVibration(true)
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(QUIET, ctx.getString(R.string.channel_quiet), NotificationManager.IMPORTANCE_DEFAULT).apply {
                setSound(null, null)
                enableVibration(false)
            }
        )
    }

    private fun intent(ctx: Context, action: String, id: Int): PendingIntent = PendingIntent.getBroadcast(
        ctx, id, Intent(ctx, ReminderReceiver::class.java).setAction(action).putExtra("id", id),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    )

    /** The boot receiver is off while no reminder is pending, so jNote does not even start at boot. */
    private fun setBootReceiver(ctx: Context, on: Boolean) {
        val component = ComponentName(ctx, BootReceiver::class.java)
        val state = if (on) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        if (ctx.packageManager.getComponentEnabledSetting(component) != state) {
            ctx.packageManager.setComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
        }
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val id = intent.getIntExtra("id", -1).takeIf { it > 0 } ?: return
        when (intent.action) {
            Reminders.FIRE -> Reminders.fire(ctx, id, ring = true)
            Reminders.SILENCE -> Reminders.silence(ctx, id)
            Reminders.SNOOZE -> Reminders.snooze(ctx, id)
            Reminders.DISMISS -> Reminders.stopRinging(ctx, id)
        }
        MainActivity.remindersChanged()
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) = Reminders.resync(ctx)
}
