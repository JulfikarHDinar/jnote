import '../data/note.dart';
import 'bullets.dart';
import 'dates.dart';

// The jNote text format, written by Export and read back by Import:
//
//   Mon, 12 Oct 2026
//   08:42 Standup: API freeze moved to Thursday
//   09:30 - Send Q3 budget to Rina
//         - Book a room for the review
//
//   Tue, 13 Oct 2026
//   10:00 Weekly sync notes
//
// - A date line starts each day. Days are oldest first, with one empty line between them.
// - A note starts with its 24-hour time and one space. Its further lines are indented
//   by six spaces. Bullets are written as "- ". Empty lines inside a note are left out.
// - Reminders are not part of the text.

const _indent = '      ';

final _dayLine = RegExp(r'^(?:[A-Za-z]{3},? )?(\d{1,2}) ([A-Za-z]{3}) (\d{4})$');
final _noteStart = RegExp(r'^(\d{1,2}):(\d{2}) (.+)$');

/// The text for the export screen, in the format above.
String buildExportText(List<Note> notes) {
  // Same order as the app shows; the id settles notes written in the same minute (imported ones).
  final sorted = [...notes]
    ..sort((a, b) => a.day != b.day
        ? a.day.compareTo(b.day)
        : a.createdAt != b.createdAt
            ? a.createdAt.compareTo(b.createdAt)
            : (a.id ?? 0).compareTo(b.id ?? 0));
  final out = StringBuffer();
  int? day;
  for (final n in sorted) {
    final lines = _lines(n.text);
    if (lines.isEmpty) continue;
    if (n.day != day) {
      if (day != null) out.writeln();
      out.writeln(longDay(dayDate(n.day)));
      day = n.day;
    }
    out.writeln('${_clock(n.createdAt)} ${lines.first}');
    for (final line in lines.skip(1)) {
      out.writeln('$_indent$line');
    }
  }
  return out.toString().trimRight();
}

/// Reads text in the format above: the notes it holds (without ids or reminders),
/// and how many non-empty lines could not be read.
({List<Note> notes, int skipped}) parseNotesText(String text) {
  final notes = <Note>[];
  var skipped = 0;
  DateTime? date; // the day being read; null before the first date line or after a bad one
  var at = 0; // start of the note being read
  final lines = <String>[];
  void flush() {
    if (lines.isNotEmpty) notes.add(Note(day: dayKey(date!), text: lines.join('\n'), createdAt: at, updatedAt: at));
    lines.clear();
  }

  for (final raw in (text.startsWith('﻿') ? text.substring(1) : text).split('\n')) {
    final line = raw.trimRight(); // also drops the \r of Windows line ends
    if (line.isEmpty) continue;
    final d = _dayLine.firstMatch(line);
    if (d != null) {
      flush();
      date = _date(d);
      if (date == null) skipped++;
      continue;
    }
    final n = _noteStart.firstMatch(line);
    final day = date;
    if (n != null && day != null && int.parse(n[1]!) < 24 && int.parse(n[2]!) < 60) {
      flush();
      at = DateTime(day.year, day.month, day.day, int.parse(n[1]!), int.parse(n[2]!)).millisecondsSinceEpoch;
      lines.add(storedLine(n[3]!.trim()));
      continue;
    }
    if (lines.isNotEmpty && (line.startsWith(' ') || line.startsWith('\t'))) {
      lines.add(storedLine(line.trim()));
      continue;
    }
    skipped++;
  }
  flush();
  return (notes: notes, skipped: skipped);
}

/// The notes in [incoming] that [existing] doesn't hold yet: same day, same minute and
/// the same text as the export writes it. Each existing note stands in for one incoming note.
List<Note> notesToAdd(List<Note> incoming, List<Note> existing) {
  final have = <String, int>{};
  for (final n in existing) {
    have.update(_key(n), (c) => c + 1, ifAbsent: () => 1);
  }
  final fresh = <Note>[];
  for (final n in incoming) {
    final key = _key(n);
    final left = have[key] ?? 0;
    if (left > 0) {
      have[key] = left - 1;
    } else {
      fresh.add(n);
    }
  }
  return fresh;
}

String _key(Note n) => '${n.day} ${_clock(n.createdAt)} ${_lines(n.text).join('\n')}';

/// A note's lines as exported: blank ones left out, bullets as "- ", no outer spaces.
List<String> _lines(String text) => [
      for (final line in text.split('\n'))
        if (!isBlankNote(line)) plainLine(line.trim()),
    ];

String _clock(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// The date of a date line, or null when it isn't a real date (such as 31 Feb).
DateTime? _date(RegExpMatch m) {
  final day = int.parse(m[1]!), year = int.parse(m[3]!);
  final month = monthShort.indexWhere((s) => s.toLowerCase() == m[2]!.toLowerCase()) + 1;
  if (month == 0) return null;
  final date = DateTime(year, month, day);
  return date.month == month && date.day == day ? date : null;
}
