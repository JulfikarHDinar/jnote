import 'package:flutter/services.dart';

/// Bullets are stored as "• " at the start of a line.
const bullet = '• ';

/// True when the text has nothing but bullets and spaces (such a note is not saved).
bool isBlankNote(String text) => text.replaceAll('•', '').trim().isEmpty;

/// Any common bullet at the start of a line, with its leading spaces.
final _anyBullet = RegExp(r'^\s*[•◦▪*\-–]\s+');

/// Export form of one line: any bullet becomes "- ".
String plainLine(String line) =>
    _anyBullet.hasMatch(line) ? '- ${line.replaceFirst(_anyBullet, '')}'.trimRight() : line.trimRight();

/// Stored form of an imported line, the reverse of [plainLine]: any bullet becomes "• ".
String storedLine(String line) => _anyBullet.hasMatch(line) ? '$bullet${line.replaceFirst(_anyBullet, '')}' : line;

/// Adds or removes the bullet on the line that holds the cursor.
TextEditingValue toggleBullet(TextEditingValue v) {
  final text = v.text;
  final cursor = v.selection.isValid ? v.selection.baseOffset : text.length;
  final start = cursor == 0 ? 0 : text.lastIndexOf('\n', cursor - 1) + 1;
  if (text.startsWith(bullet, start)) {
    return TextEditingValue(
      text: text.replaceRange(start, start + bullet.length, ''),
      selection: TextSelection.collapsed(offset: (cursor - bullet.length).clamp(start, text.length)),
    );
  }
  return TextEditingValue(
    text: text.replaceRange(start, start, bullet),
    selection: TextSelection.collapsed(offset: cursor + bullet.length),
  );
}

/// Typing "- " or "* " at a line start makes a bullet; Enter on a bullet line
/// continues the list; Enter on an empty bullet ends it.
class BulletFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    final cursor = newValue.selection.baseOffset;
    if (text.length != oldValue.text.length + 1 || !newValue.selection.isCollapsed || cursor < 1) {
      return newValue;
    }
    final typed = text[cursor - 1];
    if (typed == ' ') {
      final start = cursor < 2 ? 0 : text.lastIndexOf('\n', cursor - 2) + 1;
      final head = text.substring(start, cursor);
      if (head == '- ' || head == '* ') {
        return TextEditingValue(
          text: text.replaceRange(start, cursor, bullet),
          selection: TextSelection.collapsed(offset: start + bullet.length),
        );
      }
    } else if (typed == '\n') {
      final start = cursor < 2 ? 0 : text.lastIndexOf('\n', cursor - 2) + 1;
      final line = text.substring(start, cursor - 1);
      if (line == bullet) {
        // Empty bullet: drop it and the new line, ending the list.
        return TextEditingValue(
          text: text.replaceRange(start, cursor, ''),
          selection: TextSelection.collapsed(offset: start),
        );
      }
      if (line.startsWith(bullet)) {
        return TextEditingValue(
          text: text.replaceRange(cursor, cursor, bullet),
          selection: TextSelection.collapsed(offset: cursor + bullet.length),
        );
      }
    }
    return newValue;
  }
}
