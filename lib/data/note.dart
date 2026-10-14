class Note {
  const Note({
    this.id,
    required this.day,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.reminderAt,
  });

  final int? id;

  /// Local date as yyyymmdd, see logic/dates.dart.
  final int day;
  final String text;

  /// Epoch milliseconds.
  final int createdAt;
  final int updatedAt;

  /// Epoch milliseconds; null means no pending reminder.
  final int? reminderAt;

  Note copyWith({String? text, int? updatedAt}) => Note(
        id: id,
        day: day,
        text: text ?? this.text,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        reminderAt: reminderAt,
      );

  Note withReminder(int? at) =>
      Note(id: id, day: day, text: text, createdAt: createdAt, updatedAt: updatedAt, reminderAt: at);

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'day': day,
        'text': text,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'reminder_at': reminderAt,
      };

  factory Note.fromMap(Map<String, Object?> m) => Note(
        id: m['id'] as int,
        day: m['day'] as int,
        text: m['text'] as String,
        createdAt: m['created_at'] as int,
        updatedAt: m['updated_at'] as int,
        reminderAt: m['reminder_at'] as int?,
      );
}
