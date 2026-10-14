// Regression test of the in-app flows. Run on an emulator (it writes notes):
// flutter test integration_test/app_test.dart -d emulator-5554
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jnote/data/note.dart';
import 'package:jnote/data/notes_db.dart';
import 'package:jnote/logic/dates.dart';
import 'package:jnote/logic/export_text.dart';
import 'package:jnote/logic/settings.dart';
import 'package:jnote/main.dart' as app;
import 'package:jnote/theme.dart';
import 'package:jnote/ui/day_screen.dart';
import 'package:jnote/ui/widgets.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder input() => find.descendant(of: find.byType(InputBar), matching: find.byType(TextField));

  // pumpAndSettle doesn't wait for database calls, so give them real time first.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();
  }

  Future<void> addNote(WidgetTester tester, String text) async {
    await tester.enterText(input(), text);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save note'));
    await settle(tester);
  }

  // The Android Back button or gesture, so PopScope handling is exercised too.
  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await settle(tester);
  }

  testWidgets('notes, calendar, export and settings work in every theme', (tester) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await settle(tester);
    // A phone with reminders and notifications off gets a warning that would cover the list.
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

    // Add: empty input can't be saved; "- " becomes a bullet.
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.check)).onPressed, isNull);
    await addNote(tester, 'Call the supplier');
    await tester.enterText(input(), '-');
    await tester.enterText(input(), '- ');
    await tester.pump();
    expect(tester.widget<TextField>(input()).controller!.text, '• ');
    await tester.enterText(input(), '• Fix login bug');
    await tester.pump();
    await tester.tap(find.byTooltip('Save note'));
    await settle(tester);
    expect(find.text('Call the supplier'), findsOneWidget);
    expect(find.text('• Fix login bug'), findsOneWidget);
    expect(tester.widget<TextField>(input()).controller!.text, isEmpty);

    // Edit in the editor, save with Done.
    await tester.tap(find.text('Call the supplier'));
    await tester.pumpAndSettle();
    expect(find.text('Add reminder'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Call the supplier at 10');
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(find.text('Call the supplier at 10'), findsOneWidget);

    // Swipe to delete, then Undo brings it back.
    await tester.drag(find.text('• Fix login bug'), const Offset(-600, 0));
    await settle(tester);
    expect(find.text('• Fix login bug'), findsNothing);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(find.text('• Fix login bug'), findsOneWidget);

    // Delete from the editor, then Undo.
    await tester.tap(find.text('• Fix login bug'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete note'));
    await settle(tester);
    expect(find.text('• Fix login bug'), findsNothing);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(find.text('• Fix login bug'), findsOneWidget);

    // Calendar: months, Today, select this week, export, copy.
    await tester.tap(find.byTooltip('Calendar'));
    await settle(tester);
    expect(find.bySemanticsLabel(RegExp(r', has notes$')), findsWidgets);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsNothing); // only shown away from this month
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This week'));
    await tester.pumpAndSettle();
    expect(find.text('7 days selected'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await settle(tester);
    final export = tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(export, matches(RegExp(r'\d\d:\d\d Call the supplier at 10\n\d\d:\d\d - Fix login bug')));
    await tester.tap(find.text('Copy'));
    await settle(tester);
    expect(find.text('Copied'), findsOneWidget);
    await back(tester); // export
    await back(tester); // leaves selection mode first
    expect(find.text('Calendar'), findsOneWidget);
    await back(tester);

    // Settings: week start, then every theme on every screen.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sun'));
    await tester.pumpAndSettle();
    expect(Settings.current.value.weekStart, DateTime.sunday);
    await tester.tap(find.text('Mon'));
    await tester.pumpAndSettle();
    for (final p in palettes) {
      await tester.tap(find.bySemanticsLabel('${p.name} theme'));
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.primary, p.accent);
      await tester.scrollUntilVisible(find.text('Version'), 300);
      await tester.pumpAndSettle();
      await back(tester); // home
      await tester.tap(find.text('Call the supplier at 10'));
      await tester.pumpAndSettle();
      await back(tester); // editor
      await tester.tap(find.byTooltip('Calendar'));
      await tester.pumpAndSettle();
      await back(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.bySemanticsLabel('${p.name} theme'), -300);
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(find.bySemanticsLabel('Graphite theme'), -300);
    await tester.tap(find.bySemanticsLabel('Graphite theme'));
    await settle(tester);
    expect(Settings.current.value.palette.id, 'graphite');
  });

  testWidgets('a reminder that rings while its note is open never comes back', (tester) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 1));
    final now = DateTime.now().millisecondsSinceEpoch;
    final at = now + const Duration(days: 1).inMilliseconds;
    final id = await NotesDb.insert(Note(day: todayKey(), text: 'Ring test', createdAt: now, updatedAt: now, reminderAt: at));
    await settle(tester);
    await tester.tap(find.text('Ring test'));
    await settle(tester);
    expect(find.text('Add reminder'), findsNothing);

    // It rings: the native side clears it, and the open editor follows.
    await NotesDb.setReminder(id, null);
    await settle(tester);
    expect(find.text('Add reminder'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Ring test, edited');
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(await NotesDb.reminderOf(id), isNull);

    // Even a save from an old copy of the note leaves the reminder alone.
    await NotesDb.update(Note(id: id, day: todayKey(), text: 'Ring test', createdAt: now, updatedAt: now, reminderAt: at));
    expect(await NotesDb.reminderOf(id), isNull);
    await NotesDb.delete(id);
  });

  testWidgets('imported notes land exactly once and Undo takes them out', (tester) async {
    final file = 'Sun, 4 Jan 2026\n08:30 Imported plan\n      - first step\n09:15 Second note\n\n'
        'Mon, 5 Jan 2026\n10:00 Next day';
    final before = await NotesDb.notesBetween(20260104, 20260105); // the phone may already have notes then
    final added = await NotesDb.insertAll(notesToAdd(parseNotesText(file).notes, before));
    expect(added.map((n) => n.id), everyElement(isNotNull));
    final stored = await NotesDb.notesBetween(20260104, 20260105);
    expect(buildExportText([for (final n in stored) if (added.any((a) => a.id == n.id)) n]), file);
    expect(added.first.text, 'Imported plan\n• first step');

    // The same file again adds nothing.
    expect(notesToAdd(parseNotesText(file).notes, stored), isEmpty);

    await NotesDb.deleteAll(added); // Undo
    expect((await NotesDb.notesBetween(20260104, 20260105)).map((n) => n.id), before.map((n) => n.id));
  });

  testWidgets('unsent text in a typing bar is kept until the note is saved', (tester) async {
    Future<void> openDay() async {
      await tester.pumpWidget(MaterialApp(theme: buildTheme(palettes.first), home: const DayScreen(day: 20260106)));
      await settle(tester);
    }

    await openDay();
    await tester.enterText(input(), 'Half a thought');
    await tester.pumpWidget(const SizedBox()); // leave the day
    await settle(tester);
    await openDay();
    expect(tester.widget<TextField>(input()).controller!.text, 'Half a thought');

    await tester.tap(find.byTooltip('Save note'));
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    expect(await NotesDb.pref('draft.20260106'), isNull);
    await NotesDb.deleteAll(await NotesDb.notesForDay(20260106));
  });

  testWidgets('on a tablet the day stays in a readable, centred column', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(2560, 1600); // 1280 x 800 dp
    tester.view.padding = tester.view.viewPadding = const FakeViewPadding(top: 48, bottom: 96);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(palettes.first), home: const DayScreen()));
    await settle(tester);
    for (final part in [find.byType(DayHeader), find.byType(InputBar)]) {
      expect(tester.getRect(part).width, lessThanOrEqualTo(720));
      expect(tester.getRect(part).center.dx, closeTo(640, 1));
    }
  });

  testWidgets('on a phone on its side with the largest text, typing stays in view', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(1440, 720); // 720 x 360 dp
    tester.view.padding = tester.view.viewPadding = const FakeViewPadding(top: 48, right: 96); // status and nav bars
    tester.view.viewInsets = const FakeViewPadding(bottom: 400); // the keyboard is up
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(palettes.first), home: const DayScreen()));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(DayHeader), findsNothing);
    expect(tester.getRect(find.byType(InputBar)).bottom, lessThanOrEqualTo(360 - 200));

    // A long draft scrolls inside the bar instead of pushing it under the keyboard.
    await tester.enterText(input(), 'one\ntwo\nthree\nfour\nfive');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byType(InputBar)).bottom, lessThanOrEqualTo(360 - 200));
    await tester.enterText(input(), '');
    await tester.pumpWidget(const SizedBox()); // leave no draft behind
    await settle(tester);
  });
}
