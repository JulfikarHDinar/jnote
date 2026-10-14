import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jnote/data/note.dart';
import 'package:jnote/theme.dart';
import 'package:jnote/ui/note_editor_screen.dart';
import 'package:jnote/ui/widgets.dart';

void main() {
  testWidgets('an Undo snackbar still goes away by itself', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () => showSnack(ScaffoldMessenger.of(c), '641 notes imported',
                action: SnackBarAction(label: 'Undo', onPressed: () {}), duration: const Duration(seconds: 8)),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('641 notes imported'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.text('641 notes imported'), findsNothing);
  });

  testWidgets('on a phone on its side with the largest text, the keyboard leaves the text in view', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(1440, 720); // 720 x 360 dp
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    const note = Note(id: 1, day: 20261014, text: 'Standup: API freeze moved to Thursday', createdAt: 0, updatedAt: 0);
    await tester.pumpWidget(const MaterialApp(home: NoteEditorScreen(note: note)));
    expect(find.text('Add reminder'), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 400); // the keyboard opens
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Add reminder'), findsNothing);
    expect(tester.getSize(find.byType(TextField)).height, greaterThan(48));

    tester.view.viewInsets = FakeViewPadding.zero; // and closes again
    await tester.pumpAndSettle();
    expect(find.text('Add reminder'), findsOneWidget);
  });

  testWidgets('on a tablet the editor keeps a readable, centred column', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(2560, 1600); // 1280 x 800 dp
    addTearDown(tester.view.reset);
    const note = Note(id: 1, day: 20261014, text: 'Standup', createdAt: 0, updatedAt: 0);
    await tester.pumpWidget(const MaterialApp(home: NoteEditorScreen(note: note)));
    final field = tester.getRect(find.byType(TextField));
    expect(field.width, lessThanOrEqualTo(720));
    expect(field.center.dx, closeTo(640, 1));
  });

  testWidgets('the time column grows with Android\'s largest, uneven text scaling', (tester) async {
    final at = DateTime(2026, 10, 14, 12, 45).millisecondsSinceEpoch;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(palettes.first),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(360, 720), textScaler: _AndroidLargest()),
        child: Scaffold(
          body: NoteRow(note: Note(id: 1, day: 20261014, text: 'Call Rina', createdAt: at, updatedAt: at), onTap: () {}),
        ),
      ),
    ));
    final time = find.text('12:45 PM');
    final size = tester.widget<Text>(time).style!.fontSize!;
    final gutter = tester.getSize(find.ancestor(of: time, matching: find.byType(SizedBox)).first).width;
    // 70 dp holds "12:45 PM" at normal size; the gutter must grow as much as the time's text does.
    expect(gutter, greaterThanOrEqualTo(70 * const _AndroidLargest().scale(size) / size));
  });

  testWidgets('a tap outside the typing bar hides the keyboard; its own buttons keep it', (tester) async {
    final saved = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          const Expanded(child: SizedBox.expand(key: Key('list'))),
          InputBar(onSubmit: (t) async => saved.add(t), draftKey: 'draft'),
        ]),
      ),
    ));
    bool focused() => tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focused(), isTrue);

    await tester.tap(find.byTooltip('Bullet'));
    await tester.enterText(find.byType(TextField), 'First');
    await tester.pump();
    await tester.tap(find.byTooltip('Save note'));
    await tester.pumpAndSettle();
    expect(saved, ['First']);
    expect(focused(), isTrue, reason: 'ready for the next note');

    await tester.tapAt(tester.getCenter(find.byKey(const Key('list'))));
    await tester.pump();
    expect(focused(), isFalse);
  });
}

/// Android 14+ at its largest text size: small text doubles, large text grows much less.
class _AndroidLargest extends TextScaler {
  const _AndroidLargest();

  @override
  double scale(double fontSize) => fontSize <= 14 ? fontSize * 2 : 28 + (fontSize - 14) * 0.7;

  @override
  double get textScaleFactor => 2;

  @override
  TextScaler clamp({double minScaleFactor = 0, double maxScaleFactor = double.infinity}) => this;
}
