/// A day is stored as a local-date int `yyyymmdd` (e.g. 20261013).
/// The native widget code (NoteStore.kt) writes the same format.
int dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

DateTime dayDate(int key) => DateTime(key ~/ 10000, key ~/ 100 % 100, key % 100);

int todayKey() => dayKey(DateTime.now());

const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const weekdayLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const monthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const monthLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// "Tue, 13 Oct"
String shortDay(DateTime d) => '${weekdayShort[d.weekday - 1]}, ${d.day} ${monthShort[d.month - 1]}';

/// "Tue, 13 Oct 2026" (the export header format).
String longDay(DateTime d) => '${shortDay(d)} ${d.year}';

/// "Tue, 13 Oct" this year, "Tue, 13 Oct 2031" in any other.
String dayLabel(DateTime d) => d.year == DateTime.now().year ? shortDay(d) : longDay(d);

/// "Today", "Yesterday", "Tomorrow" or null.
String? relativeDay(int key) {
  // Rounded hours, so a daylight-saving day of 23 or 25 hours still counts as one day.
  final diff = (dayDate(key).difference(dayDate(todayKey())).inHours / 24).round();
  return const {0: 'Today', -1: 'Yesterday', 1: 'Tomorrow'}[diff];
}

/// First day of the week holding [d]; [weekStart] is DateTime.monday or DateTime.sunday.
DateTime startOfWeek(DateTime d, int weekStart) => DateTime(d.year, d.month, d.day - (d.weekday - weekStart) % 7);

/// Weekday names in calendar order for [weekStart].
List<String> weekdaysFrom(int weekStart) => [for (var i = 0; i < 7; i++) weekdayShort[(weekStart - 1 + i) % 7]];
