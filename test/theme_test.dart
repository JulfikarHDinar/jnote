import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jnote/theme.dart';

/// WCAG contrast ratio between two opaque colors.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  test('palette ids are unique', () {
    expect(palettes.map((p) => p.id).toSet().length, palettes.length);
  });

  for (final p in palettes) {
    test('${p.name}: every text color is readable', () {
      final checks = {
        // Body text: WCAG AAA.
        'text on background': (contrast(p.text, p.bg), 7.0),
        'text on surface': (contrast(p.text, p.surface), 7.0),
        'text on dialogs': (contrast(p.text, p.raised), 7.0),
        // Secondary text, hints and accent-colored labels: WCAG AA.
        'muted on background': (contrast(p.muted, p.bg), 4.5),
        'muted on surface': (contrast(p.muted, p.surface), 4.5),
        'muted on dialogs': (contrast(p.muted, p.raised), 4.5),
        'accent on background': (contrast(p.accent, p.bg), 4.5),
        'accent on surface': (contrast(p.accent, p.surface), 4.5),
        'accent on its tint': (contrast(p.accent, accentContainer(p)), 4.5),
        'text on accent buttons': (contrast(p.onAccent, p.accent), 4.5),
        'error on background': (contrast(errorColor(p), p.bg), 4.5),
        'snackbar text': (contrast(snackText(p), snackBackground(p)), 7.0),
        'snackbar action': (contrast(snackAction(p), snackBackground(p)), 4.5),
        // Hairlines stay subtle but visible.
        'lines on background': (contrast(p.line, p.bg), 1.15),
      };
      for (final MapEntry(key: name, value: (ratio, min)) in checks.entries) {
        expect(ratio, greaterThanOrEqualTo(min), reason: '${p.name}: $name is ${ratio.toStringAsFixed(2)}');
      }
    });
  }
}
