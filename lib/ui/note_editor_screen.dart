import 'package:flutter/material.dart';

import '../data/note.dart';
import '../data/notes_db.dart';
import '../logic/bullets.dart';
import '../logic/dates.dart';
import '../logic/native.dart';
import 'reminder_permissions.dart';
import 'widgets.dart';

class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, required this.note});

  final Note note;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> with WidgetsBindingObserver {
  late Note _note = widget.note;
  late final _text = TextEditingController(text: widget.note.text);
  late ScaffoldMessengerState _messenger;
  bool _deleted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotesDb.revision.addListener(_syncReminder);
  }

  // The reminder can ring, snooze or be dismissed from its notification while this screen is open.
  Future<void> _syncReminder() async {
    final at = await NotesDb.reminderOf(_note.id!);
    if (mounted && at != _note.reminderAt) setState(() => _note = _note.withReminder(at));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.of(context); // kept for the Undo snackbar after this screen closes
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotesDb.revision.removeListener(_syncReminder);
    _text.dispose();
    super.dispose();
  }

  // Save when the app goes to the background too, so a killed app loses nothing.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _save(leaving: false);
  }

  Future<void> _save({required bool leaving}) async {
    final text = _text.text.trim();
    if (_deleted || text == _note.text) return;
    if (isBlankNote(text)) {
      // An emptied note is deleted on leave (with Undo), never mid-edit.
      if (leaving) {
        _deleted = true;
        await deleteWithUndo(_messenger, _note);
      }
      return;
    }
    _note = _note.copyWith(text: text, updatedAt: DateTime.now().millisecondsSinceEpoch);
    await NotesDb.update(_note);
  }

  Future<void> _delete() async {
    _deleted = true;
    Navigator.pop(context);
    await deleteWithUndo(_messenger, _note);
  }

  Future<void> _pickReminder() async {
    final now = DateTime.now();
    final noteDay = dayDate(_note.day);
    final current = _note.reminderAt;
    final initial = current != null
        ? DateTime.fromMillisecondsSinceEpoch(current)
        : noteDay.isAfter(now)
        ? noteDay.add(const Duration(hours: 9))
        : DateTime(now.year, now.month, now.day, now.hour + 1);
    final start = initial.isBefore(now) ? now : initial;
    final date = await showDatePicker(
      context: context,
      builder: weekStartPicker,
      initialDate: start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(start.year + 5), // a note far ahead (from the calendar) still fits
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null || !mounted) return;
    final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!at.isAfter(DateTime.now())) {
      showSnack(_messenger, 'Pick a time in the future.');
      return;
    }
    if (!await ensureReminderPermissions(context)) {
      showSnack(_messenger, 'Reminder not set: jNote needs notifications to ring it.');
      return;
    }
    final ms = at.millisecondsSinceEpoch;
    await NotesDb.setReminder(_note.id!, ms);
    if (!mounted) return;
    setState(() => _note = _note.withReminder(ms));
    final exact = await Native.schedule(_note.id!, ms);
    if (!mounted) return;
    showSnack(
      _messenger,
      exact
          ? 'Reminder set for ${reminderLabel(context, ms)}.'
          : 'Reminder set. It may ring up to an hour late until jNote is allowed under "Alarms & reminders".',
    );
  }

  Future<void> _clearReminder() async {
    await NotesDb.setReminder(_note.id!, null);
    await Native.cancel(_note.id!);
    if (mounted) setState(() => _note = _note.withReminder(null));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final at = _note.reminderAt;
    final cramped = keyboardCramped(context); // only the text keeps the little room left
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _save(leaving: true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${dayLabel(dayDate(_note.day))} · ${timeLabel(context, _note.createdAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.titleSmall!.copyWith(color: cs.onSurfaceVariant),
          ),
          actions: [
            IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete note', onPressed: _delete),
            TextButton(onPressed: () => Navigator.maybePop(context), child: const Text('Done')),
            const SizedBox(width: 8),
          ],
        ),
        body: readable(
          Column(
            children: [
              if (!cramped)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: at == null
                        ? ActionChip(
                            avatar: Icon(Icons.notifications_none, size: 18, color: cs.onSurfaceVariant),
                            label: const Text('Add reminder'),
                            onPressed: _pickReminder,
                          )
                        : InputChip(
                            avatar: Icon(Icons.notifications_active_outlined, size: 18, color: cs.primary),
                            label: Text(reminderLabel(context, at)),
                            labelStyle: tt.labelMedium!.copyWith(color: cs.primary),
                            backgroundColor: cs.primaryContainer,
                            side: BorderSide.none,
                            onPressed: _pickReminder,
                            onDeleted: _clearReminder,
                            deleteIcon: const Icon(Icons.close, size: 16),
                            deleteButtonTooltipMessage: 'Remove reminder',
                          ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: _text,
                    autofocus: true,
                    expands: true,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    textAlignVertical: TextAlignVertical.top,
                    inputFormatters: [BulletFormatter()],
                    onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                    style: tt.bodyLarge!.copyWith(fontSize: 17, height: 1.55),
                    decoration: const InputDecoration(hintText: 'Write your note…'),
                  ),
                ),
              ),
              if (!cramped)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                    child: Row(
                      children: [
                        TextFieldTapRegion(
                          child: IconButton(
                            icon: const Icon(Icons.format_list_bulleted),
                            tooltip: 'Bullet',
                            onPressed: () => _text.value = toggleBullet(_text.value),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
