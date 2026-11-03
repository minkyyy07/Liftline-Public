// Pure progress formulas (Liftline's own rules, not those of other apps).
import 'calc.dart';
import 'week_utils.dart';

class WeightPoint {
  final DateTime date;
  final double kg;
  const WeightPoint(this.date, this.kg);
}

const kPeriods = ['1Н', '1М', '3М', '6М', '1Г', 'Всё'];

/// Fixed-length windows in days (months are 30-day windows). null = all time.
int? periodDays(String p) => switch (p) {
  '1Н' => 7,
  '1М' => 30,
  '3М' => 90,
  '6М' => 180,
  '1Г' => 365,
  _ => null,
};

/// Window [end-(N-1), end], inclusive; null start = unbounded.
DateTime? periodStart(String p, DateTime end) {
  final n = periodDays(p);
  if (n == null) return null;
  final e = dateOnly(end);
  return DateTime(e.year, e.month, e.day - (n - 1));
}

bool inWindow(DateTime d, DateTime? start, DateTime end) {
  final x = dateOnly(d);
  return (start == null || !x.isBefore(start)) && !x.isAfter(dateOnly(end));
}

/// Simple 7-calendar-day average over [D-6, D]; needs >= 3 distinct days.
({double avg, int n})? movingAverage(List<WeightPoint> pts, DateTime d) {
  final end = dateOnly(d);
  final start = DateTime(end.year, end.month, end.day - 6);
  final byDay = <String, double>{};
  for (final p in pts) {
    if (inWindow(p.date, start, end)) byDay[dateKey(p.date)] = p.kg;
  }
  if (byDay.length < 3) return null;
  final sum = byDay.values.fold(0.0, (a, b) => a + b);
  return (avg: sum / byDay.length, n: byDay.length);
}

/// T(D) - T(D-7); both windows need >= 3 measurements.
/// Difference of window averages, not a normalised rate.
({double delta, int nNow, int nPrev})? twoWeekChange(
  List<WeightPoint> pts,
  DateTime d,
) {
  final e = dateOnly(d);
  final a = movingAverage(pts, e);
  final b = movingAverage(pts, DateTime(e.year, e.month, e.day - 7));
  if (a == null || b == null) return null;
  return (delta: a.avg - b.avg, nNow: a.n, nPrev: b.n);
}

class SessionPoint {
  final DateTime date;
  final String sessionId;
  final double? e1rm;
  final double? bestWeight;
  final double volume;
  final int workingSets;
  const SessionPoint(
    this.date,
    this.sessionId,
    this.e1rm,
    this.bestWeight,
    this.volume,
    this.workingSets,
  );
}

/// Builds a session point from its sets; null if there are no working sets.
SessionPoint? sessionPoint(DateTime date, String id, List<SetData> sets) {
  final w = sets.where((s) => s.isWorking).toList();
  if (w.isEmpty) return null;
  double? best;
  for (final s in w) {
    if (s.weight > 0 && (best == null || s.weight > best)) best = s.weight;
  }
  return SessionPoint(
    dateOnly(date),
    id,
    sessionE1rm(w),
    best,
    workingVolume(w),
    w.length,
  );
}

/// (last - first) / first * 100 over >= 2 values with first > 0.
double? changePercent(List<double> values) {
  if (values.length < 2 || values.first <= 0) return null;
  return (values.last - values.first) / values.first * 100;
}

/// "Average over N days with entries out of 7": days without entries are
/// not counted as zero.
({double avg, int days})? averageOverEntryDays(List<double?> perDay) {
  final v = perDay.whereType<double>().toList();
  if (v.isEmpty) return null;
  return (avg: v.fold(0.0, (a, b) => a + b) / v.length, days: v.length);
}
