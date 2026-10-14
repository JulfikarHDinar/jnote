import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/notes_db.dart';
import 'logic/dates.dart';
import 'logic/native.dart';
import 'logic/settings.dart';
import 'theme.dart';
import 'ui/day_screen.dart';
import 'ui/reminder_permissions.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await Settings.load(); // the saved theme must be known before the first frame
  runApp(const JNoteApp());
}

class JNoteApp extends StatefulWidget {
  const JNoteApp({super.key});

  @override
  State<JNoteApp> createState() => _JNoteAppState();
}

class _JNoteAppState extends State<JNoteApp> with WidgetsBindingObserver {
  final _nav = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  bool _warned = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Nothing but today's notes before the first frame; the rest waits until after it.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      Native.listen(openDay: _openDay);
      final day = await Native.takeLaunchDay();
      if (day != null) _openDay(day);
      await Native.resync();
      _warnIfRemindersMuted();
    });
  }

  // A reminder that can't show is worse than none: say so once per run, with the fix a tap away.
  Future<void> _warnIfRemindersMuted() async {
    if (_warned || await Native.notificationsEnabled() || !await NotesDb.hasPendingReminders()) return;
    final messenger = _messenger.currentState;
    if (messenger == null || _warned) return;
    _warned = true;
    showSnack(
      messenger,
      "Notifications are off, so your reminders can't ring.",
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: 'Turn on',
        onPressed: () {
          final context = _nav.currentContext;
          if (context != null) ensureNotifications(context);
        },
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Notes saved from the home-screen widget land in the same file while the app is away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    NotesDb.externalChange();
    _warnIfRemindersMuted(); // notifications may have been turned off meanwhile
  }

  /// Opens a day from a tapped reminder notification.
  void _openDay(int day) {
    final nav = _nav.currentState;
    if (nav == null) return;
    nav.popUntil((route) => route.isFirst);
    if (day != todayKey()) nav.push(MaterialPageRoute(builder: (_) => DayScreen(day: day)));
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Settings>(
        valueListenable: Settings.current,
        builder: (context, settings, _) => MaterialApp(
          title: 'jNote',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(settings.palette),
          navigatorKey: _nav,
          scaffoldMessengerKey: _messenger,
          // See-through system bars on every screen, including those without an app bar.
          builder: (context, child) => AnnotatedRegion(value: systemBars(settings.palette), child: child!),
          home: const DayScreen(),
        ),
      );
}
