import 'package:flutter_test/flutter_test.dart';
import 'package:liftline_app/calc.dart';

void main() {
  test('volume and e1RM example: 100x5', () {
    const s = [SetData(100, 5)];
    expect(workingVolume(s), 500);
    expect(e1rm(100, 5), closeTo(116.67, 0.01));
    expect(e1rm(100, 1), 100);
  });

  test('warmup and not completed sets are excluded', () {
    const s = [
      SetData(100, 5, warmup: true),
      SetData(100, 5, completed: false),
    ];
    expect(workingVolume(s), 0);
    expect(sessionE1rm(s), isNull);
  });

  test('e1RM not computed for >10 reps, zero weight, 0 reps', () {
    expect(e1rm(50, 11), isNull);
    expect(e1rm(0, 5), isNull);
    expect(e1rm(50, 0), isNull);
    expect(e1rm(double.nan, 5), isNull);
  });

  test('session e1RM is max of working sets', () {
    const s = [SetData(100, 5), SetData(110, 3), SetData(60, 10, warmup: true)];
    expect(sessionE1rm(s), closeTo(121.0, 0.01));
  });

  test('rest timer uses end time, never negative', () {
    final end = DateTime.utc(2026, 1, 1, 12, 0, 120);
    final t = RestTimer(end);
    expect(t.remaining(DateTime.utc(2026, 1, 1, 12, 0, 0)).inSeconds, 120);
    expect(t.remaining(DateTime.utc(2026, 1, 1, 12, 1, 0)).inSeconds, 60);
    // after app was in background past the end:
    expect(t.remaining(DateTime.utc(2026, 1, 1, 13)), Duration.zero);
    expect(const RestTimer(null).isRunning(DateTime.utc(2026)), isFalse);
  });
}
