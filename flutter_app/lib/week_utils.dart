// Calendar helpers. Dates are local calendar days (no UTC conversion).

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Monday of the week containing [d].
DateTime startOfWeek(DateTime d) {
  final day = dateOnly(d);
  return DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));
}

/// Monday..Sunday for the week containing [d].
/// Uses calendar arithmetic (safe across DST changes).
List<DateTime> weekDays(DateTime d) {
  final s = startOfWeek(d);
  return List.generate(7, (i) => DateTime(s.year, s.month, s.day + i));
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
