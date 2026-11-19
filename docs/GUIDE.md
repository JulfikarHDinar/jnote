# jNote user guide

Everything jNote does, in more detail than the [README](../README.md).

## Home-screen widgets

The widget is a dark bar with "Write a note…" and a round tick. It comes in two sizes that look the same:
- **Note bar (3×1)**
- **Small note bar (2×1)**

Neither ever refreshes, because they show no note data.

To add one, either:
- In jNote, open **Settings > Widgets** and tap **Add note bar** or **Add small note bar** (the launcher asks you to confirm), or
- Touch and hold an empty spot on the home screen, tap **Widgets**, find **jNote**, and drag one onto the home screen.

Tapping the bar opens a small card over the home screen with the keyboard ready:
- Type and tap ✓. The note is saved to today, a "Saved" toast shows, and you are back on the home screen.
- Tapping outside closes the card only while it is empty, so a stray tap never loses typed text. Back closes it.
- Text you leave unsaved (Back, Home, a call, the screen turning off) is kept as a draft and is back in the card next time.
- The card never appears in recent apps.

## Settings

- **Theme:** six themes. Each one is a whole color world (background, text tones, surfaces and accent), not just a different accent.
  - Dark: Graphite (warm charcoal with amber, the default), Midnight (navy with sky blue), Forest (deep green with mint).
  - Light: Snow (cool white with cobalt), Sand (warm sand with ochre), Lilac (pale lilac with violet).
- **Week starts on:** Monday or Sunday. Used by the calendar, the "This week" shortcut and every date picker.
- **Reminders:**
  - **Notifications:** shows whether they are on. When off, tapping asks Android's Allow prompt (or opens the right Settings page if Android won't ask again).
  - **Exact timing:** shows whether reminders ring on the minute. Tap to allow.
  - **Sound and vibration:** opens Android's page for the Reminders category. Reminders ring with the sound and vibration chosen there. It asks for notifications first if they are off.
- **Widgets:** add the note bar or the small note bar.
- **Notes:**
  - **Export all notes** as plain text, to copy, share or save as a file.
  - **Import notes** from a jNote text file (see below).
  - **Delete notes:** pick a date range, see how many notes it holds, confirm, and you can still undo for a few seconds.
- **Backup:** Automatic backup, and Back up now with the time of the last backup (see below).
- **About:** privacy summary, open-source licenses, and Check for updates, which shows your version and opens the latest release on GitHub in your browser.

Left out on purpose:
- Text size and 12/24-hour time: these follow the phone's own settings.
- Snooze length.
- Cloud sync.
- An app lock.

## Export and import

Export writes plain text in one fixed format, and Import reads exactly that format back:

```
Mon, 12 Oct 2026
08:42 Standup: API freeze moved to Thursday
09:30 - Send Q3 budget to Rina
      - Book a room for the review

Tue, 13 Oct 2026
10:00 Weekly sync notes
```

- **Days:** a date line (`Mon, 12 Oct 2026`) starts each day. Days are oldest first, with one empty line between them.
- **Notes:** each note starts with its 24-hour time and one space. Its further lines are indented by six spaces.
- **Bullets** are written as `- ` and come back as bullets.
- **Left out:** empty lines inside a note, and reminders.
- **Encoding:** the file is UTF-8.

How Import reads a file:
- **Exactness:** every note comes back on its day, at its time, with all of its lines.
- **Duplicates:** a note that is already in jNote (same day, same minute, same text) is skipped. Importing the same file twice adds nothing.
- **Unreadable lines** are counted and listed in the confirmation, never guessed. A note under an impossible date (such as 31 Feb) is left out rather than put on another day.
- **Tolerance:** Windows line ends, a byte order mark, tabs instead of spaces, and a date line without the weekday are all fine.
- **All or nothing:** notes are added in one database transaction, then **Undo** removes exactly the imported notes.
- **Size limit:** files over 20 MB are refused. Three years of heavy use is about 0.5 MB.

### Moving notes to another phone

1. On the old phone, open **Settings > Export all notes** and tap the save icon at the top right. Choose where to keep the file (for example Downloads or Google Drive).
2. Get the file to the new phone: Quick Share, email, or Drive.
3. On the new phone, open **Settings > Import notes**, pick the file, check the count, and tap **Import**.

**Share** sends short exports as plain text for pasting into chats and email. A text message can't be imported, so use the save icon when the notes are going to another phone.

When you set up a brand-new phone, Android's own **Copy apps & data** step also brings jNote's notes across. This needs the old phone to run Android 12 or newer, and jNote installed from Google Play.

## Automatic backup

- **Off until you turn it on.** Without it, your notes never leave the phone unless you export them.
- **Where:** when you turn it on, choose **Google Drive** or **This phone**. Android's save screen opens: for Drive, open its menu and choose Drive; for the phone, it starts in Documents. jNote keeps writing to that one file, `jnote-backup.txt`.
- **When:** after your notes change, the backup is written as you leave the app. Notes added from the widget are backed up the next time you open and leave jNote. **Back up now** writes it at once.
- **What:** every note, in the export format. A backup is never replaced by an empty file.
- **Restore:** **Settings > Import notes**, then pick the backup file. Notes already in jNote are skipped.
- **Google Drive:** needs the Drive app, signed in. jNote hands the file to Drive, and Drive uploads it when the phone is online. jNote itself has no internet permission.
- **Turning it off** stops the backups and releases jNote's access to the file. The last backup file stays where it is.
- **If a backup fails** (the file was deleted or moved, or Drive was signed out), Settings shows **Last backup failed**. Turn backup off and on to choose the file again.

## How reminders work

- **The alarm:** each reminder is an `AlarmManager` alarm, exact when allowed. Nothing runs until it fires.
- **When it fires:** jNote shows a high-priority notification with the note, and a small foreground service plays the sound and vibration of the Reminders category, on the alarm volume. Music pauses while it rings.
- **Why a service:** Android stops a notification's own repeating sound as soon as you pull down the notifications. The service's sound keeps going until you answer the reminder.
- **Ringing:** until you answer it, for up to 10 minutes. Then it stops and stays as a silent notification.
- **Your actions:**
  - **Snooze 10 min** sets a new alarm.
  - **Dismiss**, or swiping the notification away, stops the ringing at once.
  - Tapping the notification stops it too, and opens that note's day.
- **Two at once:** the newer reminder rings, and the earlier one stays as a silent notification.
- **During a call:** it only vibrates.
- **Without exact timing:** Android 12+ doesn't let an app start the ringing service from an inexact alarm. The notification then rings by itself, and pulling down the notifications silences it.
- **If jNote is open:** when a reminder rings, snoozes or is dismissed, the open screens update at once.
- **Notifications turned off later:** if reminders are pending and notifications are off, jNote says so when you open it, with **Turn on** to fix it.
- **Getting reminders back:** pending reminders are set again after a reboot, an app update, a newly granted exact-alarm permission, or a force-stop (on the next app start). Reminders missed while the phone was off show quietly.

## Permissions

| Permission | Why |
|---|---|
| `POST_NOTIFICATIONS` | Shows the reminder. Asked only when you first set a reminder (or tap Notifications in Settings), after a short explanation. |
| `SCHEDULE_EXACT_ALARM` | Rings on the exact minute. Android 14+ denies it by default, so jNote explains why and opens the system page. If you skip it, reminders still work, but Android may ring them up to an hour late. |
| `RECEIVE_BOOT_COMPLETED` | Restores pending reminders after a restart. The receiver is switched off while no reminder is pending. |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SYSTEM_EXEMPTED` | The ringing service. It runs only while a reminder rings, and only after an exact alarm. |
| `VIBRATE` | Vibrates while a reminder rings. |

Package visibility: jNote checks only whether Google Drive (`com.google.android.apps.docs`) is installed, to offer it for backup.

Not used:
- `INTERNET`: only in debug builds, for the Flutter tool.
- `USE_EXACT_ALARM`: Play allows it only for alarm and calendar apps.
- Storage permissions: backup and export use Android's save screen.
- Full-screen intent, overlay and wake locks.

Android 13+ also lists `com.jnote.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. AndroidX adds this internal permission to nearly every app; users never see it.

## Known limits

- **Time zones:** a reminder is a fixed moment in time. If you change time zone, it rings at the same moment, which shows a different clock time.
- **Typing sideways:** with the phone on its side and the keyboard up, the date header and the editor's reminder and bullet buttons step aside to leave room for the text. They come back when the keyboard closes.
- **Force-stop on Android 15+:** after you force-stop jNote, the first tap on a widget wakes the app and the second tap opens the card. This is Android's behavior.
- **Without exact timing:** Android may ring a reminder up to an hour late, and pulling down the notifications silences it.
- **Backup:** it runs when you leave the app, so notes added only from the widget wait until you next open jNote. Google Drive backup needs the Drive app.
- **Turning exact timing off:** Android then cancels jNote's alarms and stops the app. Your reminders are set again, inexactly, the next time you open jNote.
- **Boot receiver:** after the last pending reminder ends, the receiver stays on until the next app start or phone restart, then turns itself off.
- **Splash color:** on Android 13+ the launch screen follows your light or dark theme. On older versions it is always dark, then switches at the first frame.
- **Long exports:** the preview stops after about 40,000 characters (a day boundary); Copy and Share include everything.
