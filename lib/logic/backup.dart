import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/notes_db.dart';
import 'export_text.dart';
import 'native.dart';

/// Automatic backup, off unless the user turns it on. When the notes have changed, leaving the
/// app writes all of them, in the export format, to the one file the user picked: on Google Drive
/// (the Drive app uploads it, jNote itself has no internet access) or in a folder on the phone.
/// Import notes restores from it.
class Backup {
  Backup._();

  static const fileName = 'jnote-backup.txt';
  static const uriKey = 'backupUri';
  static const atKey = 'backupAt';
  static const failedKey = 'backupFailed';
  static const _markKey = 'backupMark';

  static Future<int?> _queue = Future.value();

  /// Backs up if the notes changed since the last backup, or always when [force].
  /// Returns how many notes were written (0 when nothing was), or null when writing failed.
  static Future<int?> run({bool force = false}) => _queue = _queue.then((_) => _run(force));

  static Future<int?> _run(bool force) async {
    final prefs = await NotesDb.prefs();
    final uri = prefs[uriKey];
    if (uri == null) return 0;
    final mark = await NotesDb.fingerprint();
    if (!force && mark == prefs[_markKey]) return 0;
    final span = await NotesDb.daySpan();
    if (span == null) return 0; // never replace a backup with an empty file
    final notes = await NotesDb.notesBetween(span.$1, span.$2);
    try {
      await Native.writeBackup(uri, await compute(buildExportText, notes));
    } on PlatformException {
      await NotesDb.setPref(failedKey, '1');
      return null;
    }
    await NotesDb.setPref(_markKey, mark);
    await NotesDb.setPref(atKey, '${DateTime.now().millisecondsSinceEpoch}');
    await NotesDb.setPref(failedKey, '');
    return notes.length;
  }

  static Future<void> start(String uri) => NotesDb.setPref(uriKey, uri);

  /// Turns backup off. The backup file itself stays where it is.
  static Future<void> stop() async {
    final uri = await NotesDb.pref(uriKey);
    if (uri != null) await Native.releaseBackup(uri);
    for (final key in [uriKey, atKey, failedKey, _markKey]) {
      await NotesDb.setPref(key, '');
    }
  }

  /// "Google Drive" or "This phone", from where the picked file lives.
  static String place(String uri) =>
      uri.startsWith('content://com.google.android.apps.docs') ? 'Google Drive' : 'This phone';
}
