import 'package:flutter/material.dart';

import '../logic/native.dart';

bool _askedExact = false;

/// Makes sure reminders can show, asking the friendly way: a short explanation,
/// then Android's own Allow prompt. When Android won't ask again (or only the
/// Reminders category is off), offers to open the right Settings page.
Future<bool> ensureNotifications(BuildContext context) async {
  if (await Native.notificationsEnabled()) return true;
  if (!context.mounted ||
      !await _explain(context, 'Allow notifications?',
          'jNote shows your reminder as a notification and rings when it is due. '
              'It only notifies you about reminders you set.',
          'Continue')) {
    return false;
  }
  final result = await Native.requestNotifications();
  if (result == 'blocked' &&
      context.mounted &&
      await _explain(context, 'Notifications are off',
          'Turn on notifications for jNote in Settings so your reminders can ring.', 'Open Settings')) {
    await Native.openNotificationSettings();
  }
  return result == 'granted';
}

/// Everything a reminder needs. Returns false when notifications can't be shown,
/// so no reminder is set. Exact alarms are optional: without them the reminder is
/// set a little inexactly.
Future<bool> ensureReminderPermissions(BuildContext context) async {
  if (!await ensureNotifications(context)) return false;
  // Asked once per app run: saying "Not now" should not nag on every reminder.
  if (!_askedExact && !await Native.canExact() && context.mounted) {
    _askedExact = true;
    if (await _explain(context, 'Ring on the exact minute?',
        'On the next screen, allow jNote under "Alarms & reminders". '
            'Without it, Android may ring reminders up to an hour late.',
        'Allow')) {
      await Native.openExactSettings();
    }
  }
  return true;
}

Future<bool> _explain(BuildContext context, String title, String body, String ok) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
        ],
      ),
    ) ??
    false;
