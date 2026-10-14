import 'dart:async';

import 'package:flutter/material.dart';

import '../data/note.dart';
import '../data/notes_db.dart';
import '../logic/dates.dart';
import 'calendar_screen.dart';
import 'note_editor_screen.dart';
import 'settings_screen.dart';
import 'widgets.dart';

/// The notes of one day with the typing bar. With no [day] it is the home
/// screen and always shows today, also after midnight.
class DayScreen extends StatefulWidget {
  const DayScreen({super.key, this.day});

  final int? day;

  @override
  State<DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends State<DayScreen> {
  late int _day = widget.day ?? todayKey();
  List<Note>? _notes;
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    NotesDb.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    NotesDb.revision.removeListener(_load);
    _midnight?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final day = widget.day ?? todayKey();
    final notes = await NotesDb.notesForDay(day);
    if (!mounted) return;
    setState(() {
      _day = day;
      _notes = notes;
    });
    if (widget.day == null) {
      // The home screen turns to the new day at midnight, also while it stays open.
      final now = DateTime.now();
      _midnight?.cancel();
      _midnight = Timer(DateTime(now.year, now.month, now.day + 1).difference(now) + const Duration(seconds: 1), _load);
    }
  }

  Future<void> _add(String text) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await NotesDb.insert(Note(day: widget.day ?? todayKey(), text: text, createdAt: now, updatedAt: now));
  }

  void _open(Widget screen) {
    // Otherwise the typing bar grabs the keyboard again on return.
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final notes = _notes;
    final cramped = keyboardCramped(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: readable(
          LayoutBuilder(
            builder: (context, box) => Column(
              children: [
                if (!cramped)
                  DayHeader(
                    day: _day,
                    leading: widget.day == null ? null : const BackButton(),
                    actions: [
                      if (widget.day == null) ...[
                        IconButton(
                          icon: const Icon(Icons.calendar_month_outlined),
                          tooltip: 'Calendar',
                          onPressed: () => _open(const CalendarScreen()),
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings_outlined),
                          tooltip: 'Settings',
                          onPressed: () => _open(const SettingsScreen()),
                        ),
                      ],
                    ],
                  ),
                Expanded(
                  child: notes == null
                      ? const SizedBox.shrink() // no "empty" flash before the first load
                      : notes.isEmpty
                      ? (cramped ? const SizedBox.shrink() : const _EmptyHint())
                      : Align(
                          alignment: Alignment.topCenter,
                          child: ListView.builder(
                            reverse: true, // newest note sits next to the typing bar
                            // A short day starts under the header; a long one fills the screen.
                            // (shrinkWrap only while it is cheap: it lays out every row.)
                            shrinkWrap: notes.length < 40,
                            padding: const EdgeInsets.only(top: 12, bottom: 4),
                            itemCount: notes.length,
                            itemBuilder: (context, i) {
                              final n = notes[notes.length - 1 - i];
                              return Dismissible(
                                key: ValueKey(n.id),
                                background: const _DeleteHint(Alignment.centerLeft),
                                secondaryBackground: const _DeleteHint(Alignment.centerRight),
                                onDismissed: (_) {
                                  setState(() => notes.remove(n));
                                  deleteWithUndo(ScaffoldMessenger.of(context), n);
                                },
                                child: NoteRow(
                                  note: n,
                                  onTap: () => _open(NoteEditorScreen(note: n)),
                                ),
                              );
                            },
                          ),
                        ),
                ),
                // Never taller than the room it has: a long draft scrolls inside the bar instead.
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: cramped ? box.maxHeight : box.maxHeight / 2),
                  child: InputBar(onSubmit: _add, draftKey: widget.day == null ? 'draft' : 'draft.${widget.day}'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Align(
      alignment: const Alignment(0, 0.6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('No notes yet', style: tt.titleMedium!.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text(
            'Write below and tap the tick to save. Tap a note\nto edit it, swipe it away to delete.',
            textAlign: TextAlign.center,
            style: tt.bodySmall!.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DeleteHint extends StatelessWidget {
  const _DeleteHint(this.alignment);

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Icon(Icons.delete_outline, color: color, semanticLabel: 'Delete'),
    );
  }
}
