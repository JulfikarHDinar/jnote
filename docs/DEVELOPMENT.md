# Developing jNote

How the app is built and tested. Releasing a version is covered in [RELEASING.md](RELEASING.md).

## Setup

You need Flutter 3.47 or newer (stable channel), JDK 17, and the Android SDK with platform 36.

```bash
flutter pub get
flutter run
```

jNote is built for Android 8.0 (API 26) and newer. It targets API 36 (Android 16), which Google Play requires from 31 Aug 2026.

## Packages

| Package | Why |
|---|---|
| `sqflite` | The only runtime package. It uses Android's built-in SQLite, so no native library is bundled, and the widget code can open the same file. |
| `flutter_lints`, `integration_test`, `flutter_driver` | Development only. They are part of the Flutter SDK and add nothing to the app. |

Everything else is built in or a few lines of code:
- State: `StatefulWidget` plus one `ValueNotifier`.
- Date names: a small formatter.
- Calendar: a custom month grid.
- Share: a short Android intent.
- Copy: Flutter's `Clipboard`.
- Fonts: the phone's own (Roboto); no font files are bundled.
- Reminders, widgets and quick entry: plain Kotlin, so no Flutter engine ever starts in the background.

## Project layout

```
lib/
  main.dart                  app start, theme, opening a day from a reminder
  theme.dart                 the six themes (three dark, three light) and Material 3 setup
  data/                      Note model, SQLite access (notes + settings tables)
  logic/                     dates, bullets, plain-text export, settings, native channel
  ui/                        day (home), editor, calendar, export, settings screens
android/app/src/main/kotlin/com/jnote/app/
  MainActivity.kt            channel for reminders, permissions, share, widget pinning
  NoteStore.kt               the same jnote.db opened from Kotlin (keep the schema in sync)
  QuickEntryActivity.kt      the small input card the widgets open
  QuickNoteWidget.kt         the home-screen widget, in two sizes (3x1 and 2x1)
  Reminders.kt               alarms, the ringing notification, snooze, reboot handling
design/                      icon source (icon.svg) and the 512 px Play Store icon
integration_test/            on-device regression and performance tests
```

## Tests

```bash
flutter analyze
flutter test        # dates, week start, bullets, export and import format, color contrast of every theme
```

On an emulator. These tests write notes, and the Flutter tool uninstalls the app when they finish:

```bash
# Every screen in every theme, the reminder rules, import into the real database, drafts,
# and typing on a phone on its side with the largest text:
flutter test integration_test/app_test.dart -d emulator-5554
# Frame timings: a 500-note day and a three-year export, in profile mode:
flutter drive --profile --no-dds --driver=test_driver/perf_driver.dart --target=integration_test/scroll_perf_test.dart
```

## Design changes compared with the original mockups

The original mockups (five dark screens) were the starting point. The look was then made calmer and simpler:
1. **Daybook layout instead of cards.**
   - The home screen header is a large date numeral with the weekday and month.
   - Notes form a timeline: the time in a left column, then a thin line with a dot per note, then the text. A ring instead of a dot marks a note with a reminder.
   - Rows have no card borders or shadows, so the screen is calmer and cheaper to draw.
2. **Many short notes per day** instead of one big daily card. Bullets are the only formatting. Removed:
   - The rich-text toolbar (bold, italic, heading, checklist, quote).
   - The title field, tags, search and profile.
3. **Navigation:** no bottom bar. The home screen is always today. Calendar and Settings are icons in the header. The day-chip row is gone.
4. **Themes:** six complete color themes, three dark and three light, instead of one dark look. Each theme has one accent. Glass and blur effects became solid surfaces, because blur costs frames on low-end phones.
5. **Type:** the phone's own font (Roboto) in a strict size scale. Times use evenly spaced digits so they line up. Monospace appears only in the export preview. No font files are bundled.
6. **Typing bar:** the quick-add "+" became a round tick.
7. **Calendar:**
   - Tapping a day opens it directly; there is no preview card.
   - Export is a button in the top bar.
   - "This week" and "This month" shortcuts were added.
   - Selected days join into one band.
   - The legend was removed.
8. **Export:** one text box with Share, Copy and Save buttons, instead of three copy buttons and a stats strip. The text keeps the brief's layout (`Mon, 12 Oct 2026` headers, oldest day first, `- ` bullets, one blank line between days). Each note now also starts with its time, so that Import can read it back exactly.
9. **Settings:** reduced to what this app needs (see above).
10. **Tablets and phones on their side:** each screen's content stays in a centred column at most 720 dp wide, so lines stay easy to read. App bars keep the full width.
11. **New native screens**, styled to match: the widget in two sizes, the quick-entry card and the reminder permission dialogs. They use neutral colors so they suit every theme.

## Performance report

Measured on an x86_64 Android 14 emulator that draws with a software renderer, which mostly affects startup and drawing times. Real phones with a GPU are faster.

| What | Result |
|---|---|
| Cold start, release, `am start -W` | 0.94–1.07 s. Most of it is the software renderer: the startup trace shows the app ready at about 0.18 s, but the window surface only arrives at 0.44 s. An earlier build measured 0.55–0.60 s on this emulator with host GPU rendering. |
| First frame, profile startup trace | 477 ms. Framework start takes 77 ms; most of the rest is waiting for the window surface. |
| Quick entry from a widget | 356 ms to the card on screen (release, app process already in memory). An earlier build measured 99–164 ms (process in memory) and 291 ms (cold process) with host GPU rendering. |
| Scrolling a 500-note day, profile | 448 frames. Building a frame takes 0.74 ms on average (worst 6.1 ms); no frame missed its build budget. Drawing averages 16 ms here because of the software renderer; with host GPU rendering an earlier run averaged 3.1 ms with no missed frames. |
| Export all, three years of notes (783 days, 441,000 characters), profile | Opens in 0.43 s, of which 0.24 s is reading the notes. Building a frame while scrolling takes 0.28 ms on average. The preview shows the first 40,000 characters or so; Copy and Share always include everything. |
| Copy and Share of the three-year export | Copy works. Share sends a text file (`jnote-notes.txt`), because an Intent can only carry about 1 MB. |
| Play download size, release | 7.3 MB on arm64, 6.8 MB on 32-bit ARM (`apkanalyzer` estimate). |
| Background use with no reminders | No alarms, jobs, services or wake locks, and the boot receiver is off. Checked with `dumpsys`. |
| A reminder that rang | 1 wakeup and 15 ms of app run time, from `dumpsys alarm`. |

How it is kept light:
- Only today's notes load at startup. Calendar months load when shown.
- One runtime package, no bundled fonts, and vector icons only (minSdk 26 needs no PNG sizes).
- R8 shrinking, `--obfuscate` and `--split-debug-info` make the app smaller.
- No background Flutter engine. The widget's quick entry is plain Android and opens without starting Flutter.
- Lists use `ListView.builder` and `const` widgets. There is no blur, and timeline rows have no shadows or borders.

Verified on the final build (Android 14 emulator):
- **Reminders:**
  - The notification prompt appears from the editor and from Settings.
  - The exact-timing page returns to the reminder, which is then set exactly.
  - A reminder rings on the minute.
  - Snooze, Dismiss, the one-minute auto-silence, and tapping to open the day all work.
  - Reminders survive an app update and a reboot.
  - Turning off exact timing re-sets reminders inexactly on the next app start.
- **Widgets:** both sizes can be added from Settings, and both save notes to today.
- **Export:** a three-year export opens, and Copy and Share work at full size.
- **Import:** a file saved with the save icon, imported after wiping the app's data, brings back every note with its time. Importing the same file again adds nothing.
  - A three-year file (6,256 notes, with Windows line ends and one damaged line) imports in a second or two. Exported again, it matches the original file byte for byte.
  - Undo removes all 6,256 notes.
  - A non-jNote file, a file over 20 MB, and cancelling the picker are all handled.
- **Settings:** the week-start choice applies in every date picker. Deleting a date range, then Undo, restores every note.
- **Drafts:** unsent text in the typing bar and in the widget's card survives leaving the screen, pressing Home and the app being stopped.
- **Large text, sideways:** at the largest font size with the phone on its side and the keyboard up, the typing field stays in view.
- **Tablet:** with a 10-inch tablet screen (1280 × 800 dp), every screen keeps a centred, readable column, and the integration test passes at that size too.
- **Midnight:** with the app open across midnight, the home screen turns to the new day.
- **Integration test:** passes on Android 13, 14 and 16. It covers every screen in all six themes.

## Publishing on Google Play

### Play Console: Data safety answers

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **No** |
| Is all of the user data collected by your app encrypted in transit? | Not applicable (no data is collected) |
| Do you provide a way for users to request that their data is deleted? | Not applicable (no data is collected); notes can be deleted in the app or by uninstalling |

Why "No" is correct:
- Google defines "collect" as sending data off the device. jNote never does that. Data processed only on the device is out of scope.
- Share is a user-initiated transfer to an app the user picks. Google's rules exempt that from "sharing".
- Cloud backup is switched off for jNote's data.

### Play Console: other declarations

- **Ads:** No.
- **App access:** all features are available without login.
- **Target API level:** 36 (Android 16).
- **Sensitive permissions:** no declaration needed.
  - `SCHEDULE_EXACT_ALARM` is user-granted, and Play does not restrict it.
  - jNote does not use `USE_EXACT_ALARM` or the full-screen intent permission.
- **Foreground services:** none.
- **Category suggestion:** Productivity.

You must host this policy at a public URL (for example GitHub Pages or Google Sites) and enter that URL in Play Console under App content > Privacy policy.
