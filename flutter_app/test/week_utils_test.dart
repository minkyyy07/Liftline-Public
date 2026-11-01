import 'package:flutter_test/flutter_test.dart';
import 'package:liftline_app/week_utils.dart';

void main() {
  test('week is Monday..Sunday', () {
    // 2026-11-01 is Sunday
    final days = weekDays(DateTime(2026, 11, 1));
    expect(days.first, DateTime(2026, 10, 26));
    expect(days.first.weekday, DateTime.monday);
    expect(days.last, DateTime(2026, 11, 1));
    expect(days.length, 7);
  });

  test('week across DST change keeps 7 distinct calendar days', () {
    final days = weekDays(DateTime(2026, 3, 29));
    expect(days.map(dateKey).toSet().length, 7);
    expect(days.first.weekday, DateTime.monday);
  });

  test('dateKey format and isSameDay', () {
    expect(dateKey(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
    expect(isSameDay(DateTime(2026, 1, 5, 1), DateTime(2026, 1, 5, 23)), isTrue);
    expect(isSameDay(DateTime(2026, 1, 5), DateTime(2026, 1, 6)), isFalse);
  });
}
