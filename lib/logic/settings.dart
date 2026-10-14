import 'package:flutter/foundation.dart';

import '../data/notes_db.dart';
import '../theme.dart';
import 'native.dart';

/// User settings, saved in the notes database.
class Settings {
  const Settings({required this.palette, required this.weekStart});

  final Palette palette;

  /// DateTime.monday or DateTime.sunday.
  final int weekStart;

  static final current = ValueNotifier(Settings(palette: palettes.first, weekStart: DateTime.monday));

  /// Read once before the first frame, so the chosen theme never flashes.
  static Future<void> load() async {
    try {
      final saved = await NotesDb.prefs();
      current.value = Settings(
        palette: Palette.byId(saved['theme']),
        weekStart: saved['weekStart'] == '${DateTime.sunday}' ? DateTime.sunday : DateTime.monday,
      );
    } catch (_) {
      // Defaults: a settings read problem must never stop the app from opening.
    }
  }

  static Future<void> setPalette(Palette p) async {
    final wasLight = current.value.palette.light;
    current.value = Settings(palette: p, weekStart: current.value.weekStart);
    await NotesDb.setPref('theme', p.id);
    if (p.light != wasLight) await Native.setSplash(light: p.light);
  }

  static Future<void> setWeekStart(int day) async {
    current.value = Settings(palette: current.value.palette, weekStart: day);
    await NotesDb.setPref('weekStart', '$day');
  }
}
