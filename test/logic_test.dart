import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jnote/data/note.dart';
import 'package:jnote/logic/bullets.dart';
import 'package:jnote/logic/dates.dart';
import 'package:jnote/logic/export_text.dart';

/// A note written at [time] ("HH:MM") on [day], local time like the app.
Note at(int day, String time, String text) {
  final ms = dayDate(day).add(Duration(hours: int.parse(time.substring(0, 2)), minutes: int.parse(time.substring(3))));
  return Note(day: day, text: text, createdAt: ms.millisecondsSinceEpoch, updatedAt: ms.millisecondsSinceEpoch);
}

TextEditingValue typed(String before, String char) {
  final old = TextEditingValue(text: before, selection: TextSelection.collapsed(offset: before.length));
  final now = TextEditingValue(
      text: before + char, selection: TextSelection.collapsed(offset: before.length + char.length));
  return BulletFormatter().formatEditUpdate(old, now);
}

void main() {
  group('dates', () {
    test('day key round trip', () {
      expect(dayKey(DateTime(2026, 10, 13, 23, 59)), 20261013);
      expect(dayDate(20261013), DateTime(2026, 10, 13));
    });
    test('long day format', () {
      expect(longDay(DateTime(2026, 10, 12)), 'Mon, 12 Oct 2026');
      expect(longDay(DateTime(2026, 3, 29)), 'Sun, 29 Mar 2026');
    });
    test('day label shows the year only for other years', () {
      final now = DateTime.now();
      expect(dayLabel(now), shortDay(now));
      expect(dayLabel(DateTime(now.year + 5, 4, 15)), longDay(DateTime(now.year + 5, 4, 15)));
    });
    test('week start, Monday or Sunday', () {
      final tue = DateTime(2026, 10, 13);
      expect(startOfWeek(tue, DateTime.monday), DateTime(2026, 10, 12));
      expect(startOfWeek(tue, DateTime.sunday), DateTime(2026, 10, 11));
      expect(startOfWeek(DateTime(2026, 10, 11), DateTime.monday), DateTime(2026, 10, 5)); // a Sunday
      expect(startOfWeek(DateTime(2026, 10, 11), DateTime.sunday), DateTime(2026, 10, 11));
      expect(weekdaysFrom(DateTime.sunday).first, 'Sun');
      expect(weekdaysFrom(DateTime.monday).last, 'Sun');
    });
    test('relative day', () {
      final today = DateTime.now();
      expect(relativeDay(todayKey()), 'Today');
      expect(relativeDay(dayKey(DateTime(today.year, today.month, today.day - 1))), 'Yesterday');
      expect(relativeDay(dayKey(DateTime(today.year, today.month, today.day + 5))), isNull);
    });
  });

  group('export', () {
    test('matches the format, oldest day first', () {
      final text = buildExportText([
        at(20261013, '15:00', 'Meeting with team at 3 pm'),
        at(20261012, '09:05', '• Call the supplier'),
        at(20261013, '16:30', '• Send report\n• Book the room'),
        at(20261012, '11:40', '• Fix login bug'),
      ]);
      expect(
          text,
          'Mon, 12 Oct 2026\n09:05 - Call the supplier\n11:40 - Fix login bug\n\n'
          'Tue, 13 Oct 2026\n15:00 Meeting with team at 3 pm\n16:30 - Send report\n      - Book the room');
    });
    test('multi-line note, other bullet marks, blank lines dropped', () {
      final text = buildExportText([at(20261013, '08:00', 'Groceries\n\n  * milk\n– bread \n◦ eggs\n•\n-5 degrees')]);
      expect(text, 'Tue, 13 Oct 2026\n08:00 Groceries\n      - milk\n      - bread\n      - eggs\n      -5 degrees');
    });
    test('no notes gives empty text', () => expect(buildExportText([]), ''));
  });

  group('import', () {
    String show(List<Note> notes) =>
        [for (final n in notes) '${n.day} ${DateTime.fromMillisecondsSinceEpoch(n.createdAt)} ${n.text}'].join('|');

    test('reads back exactly what export writes', () {
      final notes = [
        at(20261012, '09:05', '• Call the supplier'),
        at(20261012, '09:05', 'Same minute, kept in order'),
        at(20261013, '00:00', 'Midnight\n• one\n• two\nplain line'),
        at(20261231, '23:59', 'Ünïcödé ✓ emoji 🎉, tabs\tinside'),
      ];
      final parsed = parseNotesText(buildExportText(notes));
      expect(parsed.skipped, 0);
      expect(show(parsed.notes), show(notes));
    });
    test('takes Windows line ends, a byte order mark, tabs and no weekday', () {
      final parsed = parseNotesText('﻿12 Oct 2026  \r\n08:42 First\r\n\tsecond line\r\n\r\nTue, 13 Oct 2026\r\n9:07 Next\r\n');
      expect(show(parsed.notes), show([at(20261012, '08:42', 'First\nsecond line'), at(20261013, '09:07', 'Next')]));
      expect(parsed.skipped, 0);
    });
    test('indented lines that look like dates or times stay in their note', () {
      final parsed = parseNotesText('Mon, 12 Oct 2026\n10:00 Plan\n      Tue, 13 Oct 2026\n      11:30 call Rina');
      expect(show(parsed.notes), show([at(20261012, '10:00', 'Plan\nTue, 13 Oct 2026\n11:30 call Rina')]));
    });
    test('counts the lines it cannot read and never guesses their day', () {
      final parsed = parseNotesText([
        'My notes', // before any date
        '08:00 Orphan', // a note with no date
        'Mon, 12 Oct 2026',
        '24:10 Bad time',
        '      bad time, so no note to continue',
        '10:15 Good',
        'Wed, 31 Feb 2026', // not a real date
        '11:00 Lost with its date',
        'Thu, 15 Oct 2026',
        'random line',
        '12:00 Also good',
      ].join('\n'));
      expect(show(parsed.notes), show([at(20261012, '10:15', 'Good'), at(20261015, '12:00', 'Also good')]));
      expect(parsed.skipped, 7);
    });
    test('text that is not a jNote export gives no notes', () {
      expect(parseNotesText('').notes, isEmpty);
      expect(parseNotesText('Shopping list\n- milk\n10:00 call').notes, isEmpty);
    });
    test('notes already here are skipped, each one once', () {
      final existing = [at(20261012, '09:05', '• Call the supplier\n\n'), at(20261012, '10:00', 'Twice')];
      final incoming = parseNotesText('Mon, 12 Oct 2026\n09:05 - Call the supplier\n10:00 Twice\n10:00 Twice\n'
              '10:01 Twice\n\nTue, 13 Oct 2026\n09:05 - Call the supplier')
          .notes;
      expect(show(notesToAdd(incoming, existing)),
          show([at(20261012, '10:00', 'Twice'), at(20261012, '10:01', 'Twice'), at(20261013, '09:05', '• Call the supplier')]));
    });
  });

  group('bullets', () {
    test('"- " at line start becomes a bullet', () {
      expect(typed('a\n-', ' ').text, 'a\n• ');
      expect(typed('x -', ' ').text, 'x - ');
    });
    test('Enter continues a bullet list', () {
      final v = typed('• one', '\n');
      expect(v.text, '• one\n• ');
      expect(v.selection.baseOffset, v.text.length);
    });
    test('Enter on an empty bullet ends the list', () {
      expect(typed('• one\n• ', '\n').text, '• one\n');
    });
    test('toggle adds and removes on the cursor line', () {
      const v = TextEditingValue(text: 'a\nb', selection: TextSelection.collapsed(offset: 3));
      final on = toggleBullet(v);
      expect(on.text, 'a\n• b');
      expect(toggleBullet(on).text, 'a\nb');
    });
  });
}
