import 'package:flutter/services.dart';

import '../data/notes_db.dart';

/// Calls into MainActivity.kt: reminders, permissions, share.
class Native {
  Native._();

  static const _ch = MethodChannel('jnote/native');

  /// Sets the reminder alarm. Returns false when it could only be set inexactly.
  static Future<bool> schedule(int id, int at) async =>
      await _ch.invokeMethod<bool>('schedule', {'id': id, 'at': at}) ?? false;

  static Future<void> cancel(int id) => _ch.invokeMethod('cancel', {'id': id});

  /// Re-sets every pending reminder (alarms are lost after a force-stop).
  static Future<void> resync() => _ch.invokeMethod('resync');

  static Future<bool> notificationsEnabled() async =>
      await _ch.invokeMethod<bool>('notificationsEnabled') ?? false;

  /// 'granted', 'denied' (may ask again) or 'blocked' (only Settings can fix it).
  static Future<String> requestNotifications() async =>
      await _ch.invokeMethod<String>('requestNotifications') ?? 'blocked';

  static Future<bool> canExact() async => await _ch.invokeMethod<bool>('canExact') ?? false;

  static Future<void> openExactSettings() => _ch.invokeMethod('openExactSettings');

  static Future<void> openNotificationSettings() => _ch.invokeMethod('openNotificationSettings');

  /// The system page for the reminder channel: sound, vibration, Do Not Disturb.
  static Future<void> openSoundSettings() => _ch.invokeMethod('openSoundSettings');

  /// Asks the launcher to place a widget (the 3x1 bar, or the 2x1 button when [small]).
  /// False when the launcher can't.
  static Future<bool> pinWidget({bool small = false}) async =>
      await _ch.invokeMethod<bool>('pinWidget', {'small': small}) ?? false;

  /// Makes the next launches start with a light or dark splash (Android 13+).
  static Future<void> setSplash({required bool light}) => _ch.invokeMethod('setSplash', {'light': light});

  static Future<String> appVersion() async => await _ch.invokeMethod<String>('appVersion') ?? '';

  static Future<void> share(String text) => _ch.invokeMethod('share', {'text': text});

  /// Android's file picker for a text file: its text, or null when cancelled.
  /// Throws a PlatformException with code 'too_large' for a file over 20 MB.
  static Future<String?> openText() => _ch.invokeMethod<String>('openText');

  /// Android's save dialog for [text] as a file named [name]. False when cancelled.
  static Future<bool> saveText(String name, String text) async =>
      await _ch.invokeMethod<bool>('saveText', {'name': name, 'text': text}) ?? false;

  /// The day to open when the app was started from a reminder notification.
  static Future<int?> takeLaunchDay() => _ch.invokeMethod<int>('takeLaunchDay');

  /// Calls from Android while the app runs: a reminder notification was tapped
  /// ('openDay'), or a reminder rang, snoozed or was dismissed ('changed').
  static void listen({required void Function(int day) openDay}) => _ch.setMethodCallHandler((call) async {
        if (call.method == 'openDay') openDay(call.arguments as int);
        if (call.method == 'changed') NotesDb.externalChange();
      });
}
