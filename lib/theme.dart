import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A color theme the user can pick in Settings: a calm base with one accent color.
/// Every pair used for text meets WCAG contrast (checked in test/theme_test.dart).
class Palette {
  const Palette(this.id, this.name,
      {this.light = false,
      required this.bg,
      required this.surface,
      required this.raised,
      required this.line,
      required this.text,
      required this.muted,
      required this.accent,
      required this.onAccent});

  final String id;
  final String name;
  final bool light;
  final Color bg;
  final Color surface; // input bar, text boxes
  final Color raised; // dialogs, menus, snackbars
  final Color line; // hairlines and the timeline rule
  final Color text;
  final Color muted; // times, hints, secondary text
  final Color accent;
  final Color onAccent;

  static Palette byId(String? id) => palettes.firstWhere((p) => p.id == id, orElse: () => palettes.first);
}

const palettes = [
  Palette('graphite', 'Graphite',
      bg: Color(0xFF1C1A17),
      surface: Color(0xFF26231F),
      raised: Color(0xFF2F2B26),
      line: Color(0xFF3A352E),
      text: Color(0xFFEEEBE6),
      muted: Color(0xFFA3A09B),
      accent: Color(0xFFF2B24C),
      onAccent: Color(0xFF2A1A00)),
  Palette('midnight', 'Midnight',
      bg: Color(0xFF121B2E),
      surface: Color(0xFF1A2540),
      raised: Color(0xFF22304F),
      line: Color(0xFF2B395B),
      text: Color(0xFFE8EDF7),
      muted: Color(0xFF9DABC7),
      accent: Color(0xFF82B4FF),
      onAccent: Color(0xFF06204A)),
  Palette('forest', 'Forest',
      bg: Color(0xFF13201A),
      surface: Color(0xFF1B2B23),
      raised: Color(0xFF22352B),
      line: Color(0xFF2B4135),
      text: Color(0xFFE6EFE9),
      muted: Color(0xFF9BB3A5),
      accent: Color(0xFF7ED6A4),
      onAccent: Color(0xFF062615)),
  Palette('snow', 'Snow',
      light: true,
      bg: Color(0xFFF6F8FB),
      surface: Color(0xFFEBEFF5),
      raised: Color(0xFFFFFFFF),
      line: Color(0xFFDDE2EA),
      text: Color(0xFF16181D),
      muted: Color(0xFF5C6370),
      accent: Color(0xFF2558D4),
      onAccent: Color(0xFFFFFFFF)),
  Palette('sand', 'Sand',
      light: true,
      bg: Color(0xFFF6F0E4),
      surface: Color(0xFFECE3D1),
      raised: Color(0xFFFFFBF3),
      line: Color(0xFFDFD3BD),
      text: Color(0xFF2A2118),
      muted: Color(0xFF6B5C48),
      accent: Color(0xFF8A4E0D),
      onAccent: Color(0xFFFFFFFF)),
  Palette('lilac', 'Lilac',
      light: true,
      bg: Color(0xFFF4F1FB),
      surface: Color(0xFFE9E4F7),
      raised: Color(0xFFFFFFFF),
      line: Color(0xFFDCD5EF),
      text: Color(0xFF1D1830),
      muted: Color(0xFF605879),
      accent: Color(0xFF6243C6),
      onAccent: Color(0xFFFFFFFF)),
];

/// Digits that line up in columns (times, dates), in the system font.
const tabular = [FontFeature.tabularFigures()];

/// The export preview shows the exact plain text, so it is set in monospace.
const plainText = TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.65);

/// Transparent status and navigation bars, with icons that contrast with the theme.
SystemUiOverlayStyle systemBars(Palette p) {
  final icons = p.light ? Brightness.dark : Brightness.light;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: icons,
    statusBarBrightness: p.light ? Brightness.light : Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: icons,
    // No system scrim: it paints an off-palette band; scrolling lists pad themselves above the bar instead.
    systemNavigationBarContrastEnforced: false,
  );
}

/// Accent tint for the container behind accent text (chips, selected segments).
Color accentContainer(Palette p) => Color.alphaBlend(p.accent.withValues(alpha: p.light ? 0.12 : 0.16), p.bg);

Color errorColor(Palette p) => p.light ? const Color(0xFFB3261E) : const Color(0xFFFF8A80);

/// Snackbars: raised on dark themes, dark ink on light themes (as Material does).
Color snackBackground(Palette p) => p.light ? p.text : p.raised;
Color snackText(Palette p) => p.light ? p.bg : p.text;
Color snackAction(Palette p) => p.light ? Color.lerp(p.accent, Colors.white, 0.45)! : p.accent;

ThemeData buildTheme(Palette p) {
  final scheme = ColorScheme(
    brightness: p.light ? Brightness.light : Brightness.dark,
    primary: p.accent,
    onPrimary: p.onAccent,
    primaryContainer: accentContainer(p),
    onPrimaryContainer: p.accent,
    secondary: p.accent,
    onSecondary: p.onAccent,
    secondaryContainer: p.raised,
    onSecondaryContainer: p.text,
    tertiary: p.accent,
    onTertiary: p.onAccent,
    error: errorColor(p),
    onError: p.light ? Colors.white : const Color(0xFF3B0A06),
    surface: p.bg,
    onSurface: p.text,
    onSurfaceVariant: p.muted,
    surfaceDim: p.bg,
    surfaceBright: p.raised,
    surfaceContainerLowest: p.bg,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.raised,
    surfaceContainerHighest: p.raised,
    outline: p.muted,
    outlineVariant: p.line,
    inverseSurface: p.text,
    onInverseSurface: p.bg,
    inversePrimary: p.accent,
    surfaceTint: Colors.transparent,
  );

  final typography = Typography.material2021(platform: TargetPlatform.android);
  final base = p.light ? typography.black : typography.white;
  // One family (the system font) on a strict scale: 44 / 20 / 17 / 16 / 14 / 13 / 12 / 11.
  final text = base
      .copyWith(
        displaySmall: const TextStyle(fontSize: 44, height: 1.0, fontWeight: FontWeight.w500, letterSpacing: -1.2),
        titleLarge: const TextStyle(fontSize: 20, height: 1.3, fontWeight: FontWeight.w500, letterSpacing: -0.2),
        titleMedium: const TextStyle(fontSize: 17, height: 1.3, fontWeight: FontWeight.w500, letterSpacing: -0.1),
        titleSmall: const TextStyle(fontSize: 14, height: 1.35, fontWeight: FontWeight.w500),
        labelLarge: const TextStyle(fontSize: 14, height: 1.3, fontWeight: FontWeight.w500, letterSpacing: 0.1),
        labelMedium: const TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w500, letterSpacing: 0.2),
        labelSmall: const TextStyle(fontSize: 11, height: 1.3, fontWeight: FontWeight.w700, letterSpacing: 0.9),
        bodyLarge: base.bodyLarge!.copyWith(fontSize: 16, height: 1.5, letterSpacing: 0),
        bodyMedium: base.bodyMedium!.copyWith(fontSize: 14, height: 1.45, letterSpacing: 0),
        bodySmall: base.bodySmall!.copyWith(fontSize: 13, height: 1.4, letterSpacing: 0),
      )
      .apply(bodyColor: p.text, displayColor: p.text);

  const round12 = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: p.bg,
    // Plain ripple: the default sparkle needs a shader compile on first tap.
    splashFactory: InkRipple.splashFactory,
    dividerColor: p.line,
    iconTheme: IconThemeData(color: p.muted, size: 22),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.text,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleSpacing: 4,
      titleTextStyle: text.titleMedium,
      iconTheme: IconThemeData(color: p.text),
      actionsIconTheme: IconThemeData(color: p.muted),
      systemOverlayStyle: systemBars(p),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: const StadiumBorder(), minimumSize: const Size(48, 44), textStyle: text.labelLarge),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(48, 44),
        side: BorderSide(color: p.line),
        foregroundColor: p.text,
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: const StadiumBorder(), textStyle: text.labelLarge)),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      // Floats above the typing bar, which must never be covered.
      insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      backgroundColor: snackBackground(p),
      contentTextStyle: text.bodyMedium!.copyWith(color: snackText(p)),
      actionTextColor: snackAction(p),
      shape: round12,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.raised,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
      titleTextStyle: text.titleMedium,
      contentTextStyle: text.bodyMedium!.copyWith(color: p.muted),
    ),
    datePickerTheme: DatePickerThemeData(backgroundColor: p.raised, headerBackgroundColor: p.raised),
    timePickerTheme: TimePickerThemeData(backgroundColor: p.raised),
    chipTheme: ChipThemeData(
      backgroundColor: p.bg,
      side: BorderSide(color: p.line),
      shape: const StadiumBorder(),
      labelStyle: text.labelMedium!.copyWith(color: p.text),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        side: BorderSide(color: p.line),
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: p.accent,
        foregroundColor: p.muted,
      ),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      iconColor: p.muted,
      titleTextStyle: text.bodyLarge,
      subtitleTextStyle: text.bodySmall!.copyWith(color: p.muted),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onAccent : p.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : p.surface),
      trackOutlineColor: WidgetStateProperty.all(p.line),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accent,
      selectionColor: p.accent.withValues(alpha: 0.3),
      selectionHandleColor: p.accent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      hintStyle: text.bodyLarge!.copyWith(color: p.muted),
      border: InputBorder.none,
    ),
  );
}
