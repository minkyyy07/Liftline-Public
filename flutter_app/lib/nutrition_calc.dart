// Pure nutrition math. Per-100 g values are scaled by mass; "portion" mode
// values are used as entered (no scaling, no 4/9/4 recomputation).

class Nutrients {
  final double kcal, protein, fat, carbs;
  const Nutrients(this.kcal, this.protein, this.fat, this.carbs);
  static const zero = Nutrients(0, 0, 0, 0);

  Nutrients operator +(Nutrients o) => Nutrients(
    kcal + o.kcal,
    protein + o.protein,
    fat + o.fat,
    carbs + o.carbs,
  );

  /// value per 100 g * mass / 100 (exact, rounded only on display).
  Nutrients scaled(double grams) => Nutrients(
    kcal * grams / 100,
    protein * grams / 100,
    fat * grams / 100,
    carbs * grams / 100,
  );
}

Nutrients sumNutrients(Iterable<Nutrients> l) =>
    l.fold(Nutrients.zero, (a, b) => a + b);

/// Parses a decimal with comma or dot. null when empty/invalid/negative/non-finite.
double? parseDecimal(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final v = double.tryParse(s.trim().replaceAll(',', '.'));
  if (v == null || !v.isFinite || v < 0) return null;
  return v;
}

/// Remaining / over-goal description of calories.
/// Returns (remaining >= 0, over > 0). Never negative "remaining".
({double remaining, double over}) calorieBalance(double eaten, double goal) {
  final d = goal - eaten;
  return d >= 0 ? (remaining: d, over: 0.0) : (remaining: 0.0, over: -d);
}

String fmtKcal(double v) => v.round().toString();
String fmtG(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}
