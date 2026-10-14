import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/note.dart';
import '../data/notes_db.dart';
import '../logic/dates.dart';
import '../logic/export_text.dart';
import '../logic/native.dart';
import '../logic/settings.dart';
import '../theme.dart';
import 'export_screen.dart';
import 'reminder_permissions.dart';
import 'widgets.dart';

const _privacy =
    'jNote works fully offline. Your notes are stored only on this phone, in the app\'s '
    'private storage. There is no account, no ads, no analytics and no internet access, so nothing '
    'is ever sent anywhere.\n\n'
    'When you set up a new phone, Android can copy your notes across in a phone-to-phone transfer. '
    'jNote never uploads them to a cloud backup.\n\n'
    'jNote writes to the clipboard only when you tap Copy, and never reads it.';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _notifications;
  bool? _exact;
  String _version = '';
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Permission states can change in system Settings, so re-check on return.
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    _refresh();
    Native.appVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final notifications = await Native.notificationsEnabled();
    final exact = await Native.canExact();
    if (mounted) {
      setState(() {
        _notifications = notifications;
        _exact = exact;
      });
    }
  }

  /// Off: show Android's Allow prompt (or the right Settings page). On: let the user manage them.
  Future<void> _notificationsTap() async {
    if (_notifications == true) return Native.openNotificationSettings();
    await ensureNotifications(context);
    await _refresh();
  }

  // The sound page only works once notifications are allowed, so ask for that first.
  Future<void> _soundTap() async {
    if (await ensureNotifications(context)) await Native.openSoundSettings();
    await _refresh();
  }

  Future<void> _addWidget({required bool small}) async {
    if (await Native.pinWidget(small: small) || !mounted) return;
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add the widget'),
        content: const Text(
          'Touch and hold an empty spot on your home screen, tap Widgets, '
          'then drag a jNote widget onto your home screen.',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _exportAll() async {
    final days = await NotesDb.allDays();
    if (!mounted) return;
    if (days.isEmpty) {
      showSnack(ScaffoldMessenger.of(context), 'No notes to export yet.');
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => ExportScreen(days: days)));
  }

  /// Pick a date range, see exactly how many notes it holds, confirm, and still get Undo.
  Future<void> _deleteRange() async {
    final messenger = ScaffoldMessenger.of(context);
    final span = await NotesDb.daySpan();
    if (!mounted) return;
    if (span == null) {
      showSnack(messenger, 'There are no notes to delete.');
      return;
    }
    final today = todayKey();
    final range = await showDateRangePicker(
      context: context,
      builder: weekStartPicker,
      firstDate: dayDate(span.$1 < today ? span.$1 : today),
      lastDate: dayDate(span.$2 > today ? span.$2 : today),
      helpText: 'Days to delete',
      saveText: 'Next',
    );
    if (range == null || !mounted) return;
    final notes = await NotesDb.notesBetween(dayKey(range.start), dayKey(range.end));
    if (!mounted) return;
    if (notes.isEmpty) {
      showSnack(messenger, 'There are no notes on those days.');
      return;
    }
    final count = _notes(notes.length);
    final days = _range(dayKey(range.start), dayKey(range.end));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) {
        final cs = Theme.of(c).colorScheme;
        return AlertDialog(
          title: Text('Delete $count?'),
          content: Text('$days\n\nYou can undo this right after.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await NotesDb.deleteAll(notes);
    for (final n in notes) {
      if (n.reminderAt != null) await Native.cancel(n.id!);
    }
    showSnack(
      messenger,
      '$count deleted',
      duration: const Duration(seconds: 8),
      action: SnackBarAction(label: 'Undo', onPressed: () => _restore(notes)),
    );
  }

  /// Reads a jNote text file, shows what it holds, and adds only the notes not here yet.
  Future<void> _import() async {
    final messenger = ScaffoldMessenger.of(context);
    final String? text;
    try {
      text = await Native.openText();
    } on PlatformException catch (e) {
      showSnack(
        messenger,
        e.code == 'too_large' ? 'That file is too big for a jNote export.' : "Couldn't read that file.",
      );
      return;
    }
    if (text == null) return;
    final parsed = await compute(parseNotesText, text);
    if (parsed.notes.isEmpty) {
      showSnack(messenger, 'No notes found. Choose a text file exported from jNote.');
      return;
    }
    final days = [for (final n in parsed.notes) n.day]..sort();
    final fresh = notesToAdd(parsed.notes, await NotesDb.notesBetween(days.first, days.last));
    if (!mounted) return;
    if (fresh.isEmpty) {
      showSnack(messenger, 'Nothing new: every note in this file is already in jNote.');
      return;
    }
    final known = parsed.notes.length - fresh.length;
    final bad = parsed.skipped;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Import ${_notes(fresh.length)}?'),
        content: Text(
          [
            _range(days.first, days.last),
            if (known > 0) '${_notes(known)} already in jNote will be skipped.',
            if (bad > 0) "$bad ${bad == 1 ? 'line' : 'lines'} couldn't be read and will be left out.",
            'You can undo this right after.',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Import')),
        ],
      ),
    );
    if (confirmed != true) return;
    final added = await NotesDb.insertAll(fresh);
    showSnack(
      messenger,
      '${_notes(added.length)} imported',
      duration: const Duration(seconds: 8),
      action: SnackBarAction(label: 'Undo', onPressed: () => NotesDb.deleteAll(added)),
    );
  }

  static Future<void> _restore(List<Note> notes) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final restored = [for (final n in notes) (n.reminderAt ?? 0) > now ? n : n.withReminder(null)];
    await NotesDb.insertAll(restored);
    for (final n in restored) {
      if (n.reminderAt != null) await Native.schedule(n.id!, n.reminderAt!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Settings>(
      valueListenable: Settings.current,
      builder: (context, settings, _) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        // Runs under the navigation bar, padded so the last row ends above it.
        body: readable(
          ListView(
            padding: EdgeInsets.only(bottom: 24 + MediaQuery.viewPaddingOf(context).bottom),
            children: [
              const _Section('Theme'),
              for (final light in [false, true]) ...[
                Padding(
                  padding: EdgeInsets.fromLTRB(20, light ? 20 : 8, 20, 6),
                  child: Text(
                    light ? 'Light' : 'Dark',
                    style: Theme.of(context).textTheme.labelMedium!
                        .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      for (final p in palettes.where((p) => p.light == light))
                        Expanded(
                          child: _Swatch(
                            palette: p,
                            selected: p.id == settings.palette.id,
                            onTap: () => Settings.setPalette(p),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const _Section('Calendar'),
              ListTile(
                title: const Text('Week starts on'),
                trailing: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: DateTime.monday, label: Text('Mon')),
                    ButtonSegment(value: DateTime.sunday, label: Text('Sun')),
                  ],
                  selected: {settings.weekStart},
                  onSelectionChanged: (v) => Settings.setWeekStart(v.first),
                ),
              ),
              const _Section('Reminders'),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Notifications'),
                subtitle: Text(_notifications == false ? 'Off. Tap to allow, so reminders can ring.' : 'On'),
                onTap: _notificationsTap,
              ),
              ListTile(
                leading: const Icon(Icons.alarm),
                title: const Text('Exact timing'),
                subtitle: Text(
                  _exact == false
                      ? 'Off. Reminders may ring up to an hour late. Tap to allow.'
                      : 'On. Reminders ring on the minute.',
                ),
                onTap: _exact == false ? Native.openExactSettings : null,
              ),
              ListTile(
                leading: const Icon(Icons.volume_up_outlined),
                title: const Text('Sound and vibration'),
                subtitle: const Text('Choose the reminder sound'),
                onTap: _soundTap,
              ),
              const _Section('Widgets'),
              ListTile(
                leading: const Icon(Icons.short_text),
                title: const Text('Add note bar'),
                subtitle: const Text('3 × 1 · type a note from your home screen'),
                onTap: () => _addWidget(small: false),
              ),
              ListTile(
                leading: const Icon(Icons.short_text),
                title: const Text('Add small note bar'),
                subtitle: const Text('2 × 1 · the same bar for a tighter space'),
                onTap: () => _addWidget(small: true),
              ),
              const _Section('Notes'),
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('Export all notes'),
                subtitle: const Text('Copy, share or save every note as plain text'),
                onTap: _exportAll,
              ),
              ListTile(
                leading: const Icon(Icons.file_open_outlined),
                title: const Text('Import notes'),
                subtitle: const Text('Add notes from a text file exported from jNote'),
                onTap: _import,
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('Delete notes'),
                subtitle: const Text('Choose a date range; you can undo right after'),
                onTap: _deleteRange,
              ),
              const _Section('About'),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Privacy'),
                subtitle: const Text('Offline. No account, ads or tracking.'),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Privacy'),
                    content: const SingleChildScrollView(child: Text(_privacy)),
                    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Open-source licenses'),
                onTap: () => showLicensePage(context: context, applicationName: 'jNote', applicationVersion: _version),
              ),
              ListTile(leading: const Icon(Icons.info_outline), title: const Text('Version'), subtitle: Text(_version)),
            ],
          ),
        ),
      ),
    );
  }
}

String _notes(int n) => '$n ${n == 1 ? 'note' : 'notes'}';

String _range(int from, int to) =>
    from == to ? longDay(dayDate(from)) : '${longDay(dayDate(from))} to ${longDay(dayDate(to))}';

/// A Material list subheader: sentence case, in the theme's accent.
class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall!.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

/// A theme preview in miniature: its ground with timeline rows in its own text, muted and accent tones.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.palette, required this.selected, required this.onTap});

  final Palette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget bar(Color c, double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(h / 2)),
    );
    Widget row(Color dot, double textWidth) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        bar(palette.muted, 10, 4),
        const SizedBox(width: 5),
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
        ),
        const SizedBox(width: 5),
        bar(palette.text, textWidth, 5),
      ],
    );
    return Semantics(
      button: true,
      selected: selected,
      label: '${palette.name} theme',
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Container(
                width: 84,
                height: 60,
                padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
                decoration: BoxDecoration(
                  color: palette.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 2.5 : 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [row(palette.accent, 30), row(palette.muted, 22)],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                palette.name,
                style: Theme.of(context).textTheme.labelMedium!
                    .copyWith(color: selected ? cs.onSurface : cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
