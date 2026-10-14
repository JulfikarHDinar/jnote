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
 * Reminder alarms. Nothing here runs unless the user set a reminder: no services,
 * no polling, no wake locks. The ringing is an insistent notification sound on the
 * alarm stream, so the system plays it, handles audio focus, and stops it when the
 * notification goes away.
 */
object Reminders {
    const val RINGING = "reminders"
    private const val QUIET = "reminders_quiet"
    const val FIRE = "com.jnote.app.FIRE"
    const val SILENCE = "com.jnote.app.SILENCE"
    const val SNOOZE = "com.jnote.app.SNOOZE"
    const val DISMISS = "com.jnote.app.DISMISS"
    private const val RING_MS = 60_000L
    private const val SNOOZE_MS = 10 * 60_000L

    /** True when a reminder can show: notifications are allowed and the Reminders category isn't switched off. */
    fun notificationsOn(ctx: Context): Boolean {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        return nm.areNotificationsEnabled() &&
            nm.getNotificationChannel(RINGING)?.importance != NotificationManager.IMPORTANCE_NONE
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
        val am = ctx.getSystemService(AlarmManager::class.java)
        am.cancel(intent(ctx, FIRE, id))
        am.cancel(intent(ctx, SILENCE, id))
        ctx.getSystemService(NotificationManager::class.java).cancel(id)
    }

    /** Re-sets every pending reminder: after a reboot, an app update, a force-stop or a newly granted exact-alarm permission. */
    fun resync(ctx: Context) {
        val now = System.currentTimeMillis()
        val pending = NoteStore.with(ctx) { it.pendingReminders() }
        for ((id, at) in pending) {
            // Missed while the phone was off: show it quietly instead of ringing late.
            if (at > now - RING_MS) schedule(ctx, id, at) else fire(ctx, id, ring = false)
        }
        setBootReceiver(ctx, pending.any { it.second > now - RING_MS })
    }

    fun fire(ctx: Context, id: Int, ring: Boolean) {
        val note = NoteStore.with(ctx) { store ->
            store.note(id)?.takeIf { it.at != null && it.at <= System.currentTimeMillis() + RING_MS }
                ?.also { store.setReminder(id, null) }
        } ?: return // deleted, removed, or moved to a later time
        post(ctx, note, ring)
        if (ring) {
            // Exact when allowed: an inexact alarm here lets the sound run up to 45 s longer.
            val am = ctx.getSystemService(AlarmManager::class.java)
            val stop = System.currentTimeMillis() + RING_MS
            if (canExact(ctx)) am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, stop, intent(ctx, SILENCE, id))
            else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, stop, intent(ctx, SILENCE, id))
        }
    }

    /** After a minute of ringing, keep the notification but stop the sound. */
    fun silence(ctx: Context, id: Int) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (nm.activeNotifications.none { it.id == id }) return
        val note = NoteStore.with(ctx) { it.note(id) } ?: return
        nm.cancel(id) // cancelling is what reliably stops an insistent sound
        post(ctx, note, ring = false)
    }

    fun snooze(ctx: Context, id: Int) {
        stopRinging(ctx, id)
        val at = System.currentTimeMillis() + SNOOZE_MS
        NoteStore.with(ctx) { it.setReminder(id, at) }
        schedule(ctx, id, at)
    }

    fun stopRinging(ctx: Context, id: Int) {
        ctx.getSystemService(NotificationManager::class.java).cancel(id)
        ctx.getSystemService(AlarmManager::class.java).cancel(intent(ctx, SILENCE, id))
    }

    private fun post(ctx: Context, note: NoteStore.Reminder, ring: Boolean) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        createChannels(ctx)
        val open = PendingIntent.getActivity(
            ctx, note.id,
            Intent(ctx, MainActivity::class.java).putExtra(MainActivity.EXTRA_DAY, note.day)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val notification = Notification.Builder(ctx, if (ring) RINGING else QUIET)
            .setSmallIcon(R.drawable.ic_stat_note)
            .setContentTitle(ctx.getString(R.string.reminder_title))
            .setContentText(note.text)
            .setStyle(Notification.BigTextStyle().bigText(note.text))
            .setCategory(Notification.CATEGORY_REMINDER)
            .setContentIntent(open)
            .setAutoCancel(true)
            .addAction(Notification.Action.Builder(null, ctx.getString(R.string.snooze), intent(ctx, SNOOZE, note.id)).build())
            .addAction(Notification.Action.Builder(null, ctx.getString(R.string.dismiss), intent(ctx, DISMISS, note.id)).build())
            .build()
        if (ring) notification.flags = notification.flags or Notification.FLAG_INSISTENT
        nm.notify(note.id, notification)
    }

    fun createChannels(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(RINGING) != null) return
        nm.createNotificationChannel(
            NotificationChannel(RINGING, ctx.getString(R.string.channel_reminders), NotificationManager.IMPORTANCE_HIGH).apply {
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
