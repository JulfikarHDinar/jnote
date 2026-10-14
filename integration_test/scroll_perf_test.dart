// Frame timings while flinging a 500-note day and a three-year export. Run on an
// emulator or test phone (it adds notes), in profile mode:
// flutter drive --profile --no-dds --driver=test_driver/perf_driver.dart --target=integration_test/scroll_perf_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jnote/data/note.dart';
import 'package:jnote/data/notes_db.dart';
import 'package:jnote/logic/dates.dart';
import 'package:jnote/logic/export_text.dart';
import 'package:jnote/main.dart' as app;
import 'package:jnote/theme.dart';
import 'package:jnote/ui/export_screen.dart';
import 'package:jnote/ui/widgets.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scrolling a 500-note day stays smooth', (tester) async {
    final today = todayKey();
    final existing = (await NotesDb.notesForDay(today)).length;
    final start = DateTime.now().millisecondsSinceEpoch;
    for (var i = existing; i < 500; i++) {
      final text = i.isEven ? 'Note $i about the release plan and the team' : '• Item $i\n• Follow up on $i';
      await NotesDb.insert(Note(day: today, text: text, createdAt: start + i, updatedAt: start + i));
    }

    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byType(NoteRow), findsWidgets);
    final list = find.byType(ListView);
    await binding.watchPerformance(() async {
      for (var i = 0; i < 5; i++) {
        await tester.fling(list, const Offset(0, 1500), 4000);
        await tester.pumpAndSettle();
        await tester.fling(list, const Offset(0, -1500), 4000);
        await tester.pumpAndSettle();
      }
    }, reportKey: 'scroll');
  });

  testWidgets('a three-year export opens fast and scrolls smoothly', (tester) async {
    // Heavy use for three years: 8 notes on every weekday, about 400k characters.
    if ((await NotesDb.allDays()).length < 700) {
      final now = DateTime.now();
      final notes = <Note>[];
      for (var back = 1; back <= 365 * 3; back++) {
        final d = DateTime(now.year, now.month, now.day - back);
        if (d.weekday > DateTime.friday) continue;
        for (var i = 0; i < 8; i++) {
          final t = d.add(Duration(hours: 8 + i)).millisecondsSinceEpoch;
          final text = i % 3 == 0
              ? '• Review the budget with the team\n• Follow up on item $i'
              : 'Call the client about the contract renewal and the hiring plan, item $i';
          notes.add(Note(day: dayKey(d), text: text, createdAt: t, updatedAt: t));
        }
      }
      await NotesDb.insertAll(notes);
    }
    final days = await NotesDb.allDays();
    final query = Stopwatch()..start();
    final chars = buildExportText(await NotesDb.notesForDays(days)).length;
    query.stop();

    final open = Stopwatch()..start();
    await tester.pumpWidget(MaterialApp(theme: buildTheme(palettes.first), home: ExportScreen(days: days)));
    for (var i = 0; i < 600 && find.byType(SelectableText).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    open.stop();
    expect(find.byType(SelectableText), findsOneWidget);

    final text = find.byType(SingleChildScrollView);
    await binding.watchPerformance(() async {
      for (var i = 0; i < 5; i++) {
        await tester.fling(text, const Offset(0, -2000), 6000);
        await tester.pumpAndSettle();
      }
      await tester.fling(text, const Offset(0, 4000), 8000);
      await tester.pumpAndSettle();
    }, reportKey: 'export');
    binding.reportData!['export_open_ms'] = open.elapsedMilliseconds;
    binding.reportData!['export_days'] = days.length;
    binding.reportData!['export_chars'] = chars;
    binding.reportData!['export_query_and_text_ms'] = query.elapsedMilliseconds;
  });
}
