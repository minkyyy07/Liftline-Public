// Pure calculation helpers (no I/O). Formulas are Liftline's own (Epley).

class SetData {
  final double weight;
  final int reps;
  final bool completed;
  final bool warmup;
  const SetData(
    this.weight,
    this.reps, {
    this.completed = true,
    this.warmup = false,
  });

  /// Counts towards working statistics.
  bool get isWorking => completed && !warmup;
}

/// Sum of weight*reps over completed working sets (kg·reps).
double workingVolume(Iterable<SetData> sets) =>
    sets.where((s) => s.isWorking).fold(0.0, (a, s) => a + s.weight * s.reps);

/// Epley estimate. null when not applicable (reps<1, reps>10, weight<=0).
double? e1rm(double weight, int reps) {
  if (!weight.isFinite || weight <= 0 || reps < 1 || reps > 10) return null;
  if (reps == 1) return weight;
  return weight * (1 + reps / 30);
}

/// Best e1RM among working sets of one session, or null.
double? sessionE1rm(Iterable<SetData> sets) {
  double? best;
  for (final s in sets.where((s) => s.isWorking)) {
    final v = e1rm(s.weight, s.reps);
    if (v != null && (best == null || v > best)) best = v;
  }
  return best;
}

/// Rest timer based on a stored end time (UTC), not on UI ticks.
class RestTimer {
  final DateTime? endUtc;
  const RestTimer(this.endUtc);

  /// Remaining time, never negative; zero when stopped / elapsed.
  Duration remaining(DateTime nowUtc) {
    final e = endUtc;
    if (e == null) return Duration.zero;
    final d = e.difference(nowUtc);
    return d.isNegative ? Duration.zero : d;
  }

  bool isRunning(DateTime nowUtc) => remaining(nowUtc) > Duration.zero;
}
