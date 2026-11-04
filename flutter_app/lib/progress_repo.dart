import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'calc.dart';
import 'data_events.dart';
import 'nutrition_calc.dart';
import 'nutrition_repo.dart';
import 'progress_calc.dart';
import 'repo.dart' show Rec;
import 'week_utils.dart';

class ProgressRepo {
  final Database db;
  ProgressRepo(this.db);
  final _uuid = const Uuid();

  // ---------- body weight ----------
  /// Primary measurements only (one per day), oldest first.
  Future<List<Rec>> weights() =>
      db.query('body_weights', where: 'is_primary = 1', orderBy: 'date, rowid');

  Future<Rec?> primaryFor(String date) async {
    final r = await db.query(
      'body_weights',
      where: 'date = ? AND is_primary = 1',
      whereArgs: [date],
      limit: 1,
    );
    return r.isEmpty ? null : r.first;
  }

  /// Latest primary measurement on or before [date] (never a later one).
  Future<Rec?> latestUpTo(String date) async {
    final r = await db.query(
      'body_weights',
      where: 'date <= ? AND is_primary = 1',
      whereArgs: [date],
      orderBy: 'date DESC, rowid DESC',
      limit: 1,
    );
    return r.isEmpty ? null : r.first;
  }

  /// Adds a measurement. If the day already has a primary one and
  /// [replaceExisting] is false, throws [WeightExists] (nothing is changed).
  Future<String> saveWeight(
    DateTime date,
    double kg, {
    bool replaceExisting = false,
  }) async {
    if (!kg.isFinite || kg <= 0) throw ArgumentError('kg must be > 0');
    final key = dateKey(date);
    final ex = await primaryFor(key);
    if (ex != null) {
      if (!replaceExisting) throw WeightExists(ex['id'] as String);
      await db.update(
        'body_weights',
        {'kg': kg},
        where: 'id = ?',
        whereArgs: [ex['id']],
      );
      AppDataEvents.instance.notifyWeightChanged();
      return ex['id'] as String;
    }
    final id = _uuid.v4();
    await db.insert('body_weights', {
      'id': id,
      'date': key,
      'kg': kg,
      'is_primary': 1,
    });
    AppDataEvents.instance.notifyWeightChanged();
    return id;
  }

  Future<void> updateWeight(String id, DateTime date, double kg) async {
    if (!kg.isFinite || kg <= 0) throw ArgumentError('kg must be > 0');
    final key = dateKey(date);
    await db.transaction((t) async {
      final clash = await t.query(
        'body_weights',
        where: 'date = ? AND is_primary = 1 AND id <> ?',
        whereArgs: [key, id],
      );
      if (clash.isNotEmpty) throw WeightExists(clash.first['id'] as String);
      await t.update(
        'body_weights',
        {'date': key, 'kg': kg},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    AppDataEvents.instance.notifyWeightChanged();
  }

  Future<void> deleteWeight(String id) async {
    await db.delete('body_weights', where: 'id = ?', whereArgs: [id]);
    AppDataEvents.instance.notifyWeightChanged();
  }

  // ---------- strength ----------
  /// Catalogue exercises that have at least one finished session.
  Future<List<Rec>> exercisesWithHistory() => db.rawQuery('''
    SELECT DISTINCT x.id, x.name FROM exercises x
    JOIN workout_exercises e ON e.exercise_ref_id = x.id
    JOIN workouts w ON w.id = e.workout_id
    WHERE w.status = 'finished' ORDER BY x.name COLLATE NOCASE''');

  /// Session points (oldest first by date, start time, id) from FINISHED
  /// workouts only; warm-up/uncompleted sets are excluded.
  Future<List<SessionPoint>> strengthSessions(String refId) async {
    final rows = await db.rawQuery(
      '''
      SELECT w.id AS wid, e.id AS weid, w.date, s.weight_kg, s.reps,
             s.completed, s.set_type
      FROM set_entries s
      JOIN workout_exercises e ON s.exercise_id = e.id
      JOIN workouts w ON e.workout_id = w.id
      WHERE e.exercise_ref_id = ? AND w.status = 'finished'
      ORDER BY w.date, COALESCE(w.started_at_utc, 0), w.id, e.id, s.set_number''',
      [refId],
    );
    final groups = <String, List<Rec>>{};
    for (final r in rows) {
      groups.putIfAbsent(r['weid'] as String, () => []).add(r);
    }
    final out = <SessionPoint>[];
    for (final g in groups.values) {
      final sets =
          g
              .map(
                (r) => SetData(
                  (r['weight_kg'] as num).toDouble(),
                  r['reps'] as int,
                  completed: r['completed'] == 1,
                  warmup: r['set_type'] == 'warmup',
                ),
              )
              .toList();
      final p = sessionPoint(
        DateTime.parse(g.first['date'] as String),
        g.first['wid'] as String,
        sets,
      );
      if (p != null) out.add(p);
    }
    return out;
  }

  // ---------- nutrition week ----------
  /// Per-day totals for [end-6, end] with the goal valid on each day.
  Future<List<({DateTime date, Nutrients? totals, double? goalKcal})>> week(
    DateTime end,
  ) async {
    final n = NutritionRepo(db);
    final e = dateOnly(end);
    final out = <({DateTime date, Nutrients? totals, double? goalKcal})>[];
    for (var i = 6; i >= 0; i--) {
      final d = DateTime(e.year, e.month, e.day - i);
      final key = dateKey(d);
      final entries = await n.day(key);
      final g = await n.goalsFor(key);
      out.add((
        date: d,
        totals: entries.isEmpty ? null : sumNutrients(entries.map(entryTotals)),
        goalKcal: g.calories,
      ));
    }
    return out;
  }
}

class WeightExists implements Exception {
  final String existingId;
  WeightExists(this.existingId);
  @override
  String toString() => 'На эту дату уже есть измерение';
}
