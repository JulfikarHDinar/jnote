import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'note.dart';

/// The one SQLite file, shared with the native widget and reminder code
/// (android/.../NoteStore.kt). Keep the schema identical in both places.
class NotesDb {
  NotesDb._();

  static const _schema = [
    // AUTOINCREMENT: ids are never reused, so an old alarm can't hit a newer note.
    'CREATE TABLE IF NOT EXISTS notes(id INTEGER PRIMARY KEY AUTOINCREMENT, day INTEGER NOT NULL, '
        'text TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, reminder_at INTEGER)',
    'CREATE INDEX IF NOT EXISTS notes_day ON notes(day)',
  ];

  /// Bumped after every write so open screens can reload.
  static final revision = ValueNotifier<int>(0);

  // Lazy static: the file is opened once, on first use.
  static final Future<Database> _db = _open();

  static Future<Database> _open() async => openDatabase(
        '${await getDatabasesPath()}/jnote.db',
        version: 1,
        onCreate: (db, _) async {
          for (final sql in _schema) {
            await db.execute(sql);
          }
        },
        // Settings live outside the versioned schema so the native side (NoteStore.kt) needs no change.
        onOpen: (db) => db.execute('CREATE TABLE IF NOT EXISTS prefs(key TEXT PRIMARY KEY, value TEXT NOT NULL)'),
      );

  /// Re-reads after a change made outside this Dart code (the widget's quick entry,
  /// or a reminder that rang, snoozed or was dismissed).
  static void externalChange() => revision.value++;

  static Future<List<Note>> notesForDay(int day) async {
    final rows = await (await _db).query('notes', where: 'day = ?', whereArgs: [day], orderBy: 'created_at, id');
    return rows.map(Note.fromMap).toList();
  }

  /// The pending reminder of one note, or null.
  static Future<int?> reminderOf(int id) async {
    final rows = await (await _db).query('notes', columns: ['reminder_at'], where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first['reminder_at'] as int?;
  }

  /// True while some reminder is still to ring.
  static Future<bool> hasPendingReminders() async => (await (await _db).rawQuery(
          'SELECT 1 FROM notes WHERE reminder_at > ? LIMIT 1', [DateTime.now().millisecondsSinceEpoch]))
      .isNotEmpty;

  /// Note count per day between two day keys (inclusive).
  static Future<Map<int, int>> countsBetween(int from, int to) async {
    final rows = await (await _db).rawQuery(
        'SELECT day, COUNT(*) AS c FROM notes WHERE day BETWEEN ? AND ? GROUP BY day', [from, to]);
    return {for (final r in rows) r['day'] as int: r['c'] as int};
  }

  /// Notes from day [from] to day [to], both included, oldest first.
  static Future<List<Note>> notesBetween(int from, int to) async {
    final rows = await (await _db)
        .query('notes', where: 'day BETWEEN ? AND ?', whereArgs: [from, to], orderBy: 'day, created_at, id');
    return rows.map(Note.fromMap).toList();
  }

  static Future<List<Note>> notesForDays(Set<int> days) async {
    if (days.isEmpty) return [];
    final sorted = days.toList()..sort();
    // A range query instead of IN (...): no limit on how many days are selected.
    return (await notesBetween(sorted.first, sorted.last)).where((n) => days.contains(n.day)).toList();
  }

  /// First and last day that have notes, or null when there are none.
  static Future<(int, int)?> daySpan() async {
    final r = (await (await _db).rawQuery('SELECT MIN(day) AS first, MAX(day) AS last FROM notes')).first;
    return r['first'] == null ? null : (r['first'] as int, r['last'] as int);
  }

  /// Every day that has at least one note (for "Export all notes").
  static Future<Set<int>> allDays() async =>
      {for (final r in await (await _db).rawQuery('SELECT DISTINCT day FROM notes')) r['day'] as int};

  static Future<Map<String, String>> prefs() async =>
      {for (final r in await (await _db).query('prefs')) r['key'] as String: r['value'] as String};

  static Future<String?> pref(String key) async => (await prefs())[key];

  /// Saves a setting; an empty value removes it.
  static Future<void> setPref(String key, String value) async {
    final db = await _db;
    if (value.isEmpty) {
      await db.delete('prefs', where: 'key = ?', whereArgs: [key]);
    } else {
      await db.insert('prefs', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Inserts the note (keeping its id when it has one, for undo) and returns the id.
  static Future<int> insert(Note note) => _write((db) => db.insert('notes', note.toMap()));

  /// Saves an edited text. Reminders change only through [setReminder] or natively when
  /// one rings, so a stale copy of the note can never bring an old reminder back.
  static Future<void> update(Note note) => _write((db) => db.update(
      'notes', {'text': note.text, 'updated_at': note.updatedAt}, where: 'id = ?', whereArgs: [note.id]));

  static Future<void> delete(int id) => _write((db) => db.delete('notes', where: 'id = ?', whereArgs: [id]));

  /// Deletes exactly these notes in one transaction (not a day range, so a note
  /// added meanwhile is never removed without a way back).
  static Future<void> deleteAll(List<Note> notes) => _write((db) async {
        final batch = db.batch();
        for (final n in notes) {
          batch.delete('notes', where: 'id = ?', whereArgs: [n.id]);
        }
        await batch.commit(noResult: true);
      });

  /// Inserts notes in one transaction: all or none. Notes with ids keep them (Undo after
  /// a bulk delete). Returns the notes with their ids.
  static Future<List<Note>> insertAll(List<Note> notes) => _write((db) async {
        final batch = db.batch();
        for (final n in notes) {
          batch.insert('notes', n.toMap());
        }
        final ids = await batch.commit();
        return [for (var i = 0; i < notes.length; i++) Note.fromMap({...notes[i].toMap(), 'id': ids[i]})];
      });

  static Future<void> setReminder(int id, int? at) =>
      _write((db) => db.update('notes', {'reminder_at': at}, where: 'id = ?', whereArgs: [id]));

  static Future<T> _write<T>(Future<T> Function(Database db) op) async {
    final result = await op(await _db);
    revision.value++;
    return result;
  }
}
