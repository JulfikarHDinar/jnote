import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/note.dart';
import '../data/notes_db.dart';
import '../logic/bullets.dart';
import '../logic/dates.dart';
import '../logic/native.dart';
import '../logic/settings.dart';
import '../theme.dart';

/// "3:45 PM" or "15:45", following the phone's 24-hour setting.
String timeLabel(BuildContext context, int ms) => MaterialLocalizations.of(context).formatTimeOfDay(
  TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(ms)),
  alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
);

/// "Tomorrow, 9:00 AM" or "Wed, 14 Oct, 9:00 AM".
String reminderLabel(BuildContext context, int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${relativeDay(dayKey(d)) ?? dayLabel(d)}, ${timeLabel(context, ms)}';
}

/// A screen's content on tablets and phones on their side: a centred column that stays
/// narrow enough to read comfortably. Phones in portrait are narrower, so nothing changes there.
Widget readable(Widget child) => Center(
  heightFactor: 1,
  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: child),
);

/// True while the keyboard leaves little room (a phone on its side, a short split window):
/// screens then keep only what is needed to see the text being typed.
bool keyboardCramped(BuildContext context) {
  final keyboard = MediaQuery.viewInsetsOf(context).bottom;
  return keyboard > 0 && MediaQuery.sizeOf(context).height - keyboard < 360;
}

void showSnack(
  ScaffoldMessengerState messenger,
  String text, {
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 4),
}) => messenger
  ..hideCurrentSnackBar()
  // Times out even with Undo (Flutter keeps action snackbars by default); stays for TalkBack users.
  ..showSnackBar(
    SnackBar(
      content: Text(text),
      action: action,
      duration: duration,
      persist: MediaQuery.accessibleNavigationOf(messenger.context),
    ),
  );

/// Deletes the note and its alarm, and offers Undo (which restores the same row).
Future<void> deleteWithUndo(ScaffoldMessengerState messenger, Note note) async {
  await NotesDb.delete(note.id!);
  await Native.cancel(note.id!); // always: a snooze may have set a reminder this copy doesn't show
  showSnack(
    messenger,
    'Note deleted',
    action: SnackBarAction(
      label: 'Undo',
      onPressed: () async {
        final at = note.reminderAt;
        final future = at != null && at > DateTime.now().millisecondsSinceEpoch;
        await NotesDb.insert(note.withReminder(future ? at : null));
        if (future) await Native.schedule(note.id!, at);
      },
    ),
  );
}

/// The big date numeral with weekday and month: the header of a day.
class DayHeader extends StatelessWidget {
  const DayHeader({super.key, required this.day, this.leading, this.actions = const []});

  final int day;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final d = dayDate(day);
    final rel = relativeDay(day);
    return Padding(
      padding: EdgeInsets.fromLTRB(leading == null ? 20 : 4, 8, 8, 12),
      child: Row(
        children: [
          ?leading,
          Expanded(
            // One stop for TalkBack: "14 Wednesday October 2026 · Today".
            child: MergeSemantics(
              child: Row(
                children: [
                  Text('${d.day}', style: tt.displaySmall!.copyWith(color: rel == 'Today' ? cs.primary : cs.onSurface)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          weekdayLong[d.weekday - 1],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.titleMedium,
                        ),
                        Text(
                          ['${monthLong[d.month - 1]} ${d.year}', ?rel].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall!.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// One note in the day's timeline: time in the gutter, a dot on the rule, the text.
class NoteRow extends StatelessWidget {
  const NoteRow({super.key, required this.note, required this.onTap});

  final Note note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final at = note.reminderAt;
    final double dot = at != null ? 11 : 7;
    final timeStyle = tt.bodySmall!.copyWith(color: cs.onSurfaceVariant, fontFeatures: tabular);
    final size = timeStyle.fontSize!;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              // Grows with the time's own text size (Android enlarges small text the most), so
              // "12:45 PM" never wraps.
              width: (70 * MediaQuery.textScalerOf(context).scale(size) / size).clamp(70, 150),
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(timeLabel(context, note.createdAt), style: timeStyle),
              ),
            ),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: cs.outlineVariant)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 0, 22),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Centred on the 1px rule, level with the first line of text. A note with a
                      // reminder gets a ring instead of a dot, so the state doesn't rely on colour alone.
                      Positioned(
                        left: -17.5 - dot / 2,
                        top: 12 - dot / 2,
                        child: Container(
                          width: dot,
                          height: dot,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: at != null ? cs.surface : cs.onSurfaceVariant,
                            border: at != null ? Border.all(color: cs.primary, width: 2) : null,
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(note.text, style: tt.bodyLarge),
                          if (at != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.notifications_none,
                                    size: 15,
                                    color: cs.primary,
                                    semanticLabel: 'Reminder',
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      reminderLabel(context, at),
                                      style: tt.bodySmall!.copyWith(
                                        color: cs.primary,
                                        fontWeight: FontWeight.w500,
                                        fontFeatures: tabular,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The chat-style typing bar: a pill with the bullet button and field, and a round tick.
class InputBar extends StatefulWidget {
  const InputBar({super.key, required this.onSubmit, required this.draftKey});

  final Future<void> Function(String text) onSubmit;

  /// Where unsent text is kept, so leaving the screen or the app never loses it.
  final String draftKey;

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final _c = TextEditingController();
  final _focus = FocusNode();
  late final AppLifecycleListener _lifecycle;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onPause: _keepDraft);
    NotesDb.pref(widget.draftKey).then((draft) {
      if (draft != null && mounted && _c.text.isEmpty) _c.text = draft;
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _keepDraft();
    _lifecycle.dispose();
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  // Best effort: a draft that can't be kept must never get in the way of typing.
  void _keepDraft() => NotesDb.setPref(widget.draftKey, isBlankNote(_c.text) ? '' : _c.text).ignore();

  Future<void> _submit() async {
    final text = _c.text.trim();
    if (_saving || isBlankNote(text)) return;
    setState(() => _saving = true);
    try {
      await widget.onSubmit(text);
      _c.clear(); // only after the save succeeded, so a failed save keeps the text
      _keepDraft();
    } catch (_) {
      if (mounted) showSnack(ScaffoldMessenger.of(context), "Couldn't save the note. Please try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        // The bullet and save buttons count as part of the field, so the keyboard stays up for them.
        child: TextFieldTapRegion(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: const BorderRadius.all(Radius.circular(24)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.format_list_bulleted),
                        color: cs.onSurfaceVariant,
                        tooltip: 'Bullet',
                        onPressed: () {
                          _c.value = toggleBullet(_c.value);
                          _focus.requestFocus();
                        },
                      ),
                      Expanded(
                        child: TextField(
                          controller: _c,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 5,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          inputFormatters: [BulletFormatter()],
                          onTapOutside: (_) => _focus.unfocus(),
                          style: Theme.of(context).textTheme.bodyLarge,
                          decoration: const InputDecoration(
                            hintText: 'Write a note…',
                            isDense: true,
                            contentPadding: EdgeInsets.fromLTRB(0, 12, 16, 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _c,
                builder: (context, value, _) => IconButton.filled(
                  onPressed: isBlankNote(value.text) || _saving ? null : _submit,
                  icon: const Icon(Icons.check),
                  tooltip: 'Save note',
                  style: IconButton.styleFrom(
                    fixedSize: const Size(48, 48),
                    // Both states set explicitly: a style with only disabled colours leaves the enabled
                    // icon to the theme's muted icon colour.
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    disabledBackgroundColor: cs.surfaceContainerLow,
                    disabledForegroundColor: cs.onSurfaceVariant,
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

/// Date pickers start the week on the day chosen in Settings, like the calendar does.
Widget weekStartPicker(BuildContext context, Widget? child) => Localizations.override(
  context: context,
  delegates: [_WeekStartDelegate(Settings.current.value.weekStart)],
  child: child!,
);

class _WeekStartLocalizations extends DefaultMaterialLocalizations {
  const _WeekStartLocalizations(this.weekStart);

  final int weekStart;

  // Material counts 0 as Sunday; DateTime uses 7.
  @override
  int get firstDayOfWeekIndex => weekStart % 7;
}

class _WeekStartDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _WeekStartDelegate(this.weekStart);

  final int weekStart;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) => SynchronousFuture(_WeekStartLocalizations(weekStart));

  @override
  bool shouldReload(_WeekStartDelegate old) => old.weekStart != weekStart;
}
