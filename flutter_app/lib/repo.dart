import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'week_utils.dart';

const int kDefaultRestSec = 120;

class ActiveWorkoutExists implements Exception {
  final String activeId;
  ActiveWorkoutExists(this.activeId);
  @override
  String toString() => 'Уже есть активная тренировка';
}

class FinishSummary {
  final int done;
  final int remaining;
  const FinishSummary(this.done, this.remaining);
}

typedef Rec = Map<String, Object?>;

/// Workout/exercise/set data access. All multi-row changes are transactional.
class WorkoutRepo {
  final Database db;
  final DateTime Function() now;
  final _uuid = const Uuid();
  WorkoutRepo(this.db, {DateTime Function()? now}) : now = now ?? DateTime.now;

  int get _nowUtcMs => now().toUtc().millisecondsSinceEpoch;

  // ---------- exercises catalogue ----------
  Future<String> findOrCreateExercise(String name, [DatabaseExecutor? ex]) async {
    final e = ex ?? db;
    final n = name.trim();
    final found =
        await e.query('exercises', where: 'name = ?', whereArgs: [n], limit: 1);
    if (found.isNotEmpty) {
      final id = found.first['id'] as String;
      if (found.first['archived'] == 1) {
        await e.update('exercises', {'archived': 0}, where: 'id = ?', whereArgs: [id]);
      }
      return id;
    }
    final id = _uuid.v4();
    await e.insert('exercises', {'id': id, 'name': n});
    return id;
  }

  Future<List<Rec>> activeExercises() =>
      db.query('exercises', where: 'archived = 0', orderBy: 'name COLLATE NOCASE');

  /// Rename keeps the id and therefore history.
  Future<void> renameExercise(String id, String name) => db.update(
      'exercises', {'name': name.trim()}, where: 'id = ?', whereArgs: [id]);

  /// Archive instead of deleting: past workouts stay intact.
  Future<void> archiveExercise(String id) => db.update(
      'exercises', {'archived': 1}, where: 'id = ?', whereArgs: [id]);

  // ---------- workouts ----------
  Future<Rec?> activeWorkout() async {
    final r = await db.query('workouts',
        where: "status = 'active'", limit: 1);
    return r.isEmpty ? null : r.first;
  }

  Future<Rec?> workout(String id) async {
    final r = await db.query('workouts', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : r.first;
  }

  /// [start] true: begins an active session now (date = today, fixed).
  /// false: records a finished workout on [date] (backfill).
  Future<String> createWorkout(
      {required String title, required DateTime date, required bool start}) async {
    if (start) {
      final a = await activeWorkout();
      if (a != null) throw ActiveWorkoutExists(a['id'] as String);
    }
    final id = _uuid.v4();
    final n = now();
    await db.insert('workouts', {
      'id': id,
      'date': dateKey(start ? n : date),
      'title': title.trim(),
      'status': start ? 'active' : 'finished',
      'started_at_utc': start ? _nowUtcMs : null,
      'finished_at_utc': start ? null : null,
    });
    return id;
  }

  /// planned -> active (date fixed to today at start).
  Future<void> startWorkout(String id) async {
    final a = await activeWorkout();
    if (a != null && a['id'] != id) throw ActiveWorkoutExists(a['id'] as String);
    await db.update(
        'workouts',
        {'status': 'active', 'date': dateKey(now()), 'started_at_utc': _nowUtcMs},
        where: "id = ? AND status = 'planned'",
        whereArgs: [id]);
  }

  Future<void> renameWorkout(String id, String title) => db.update(
      'workouts', {'title': title.trim()}, where: 'id = ?', whereArgs: [id]);

  /// Only for non-active workouts (active date is fixed at start).
  Future<void> changeWorkoutDate(String id, DateTime date) => db.update(
      'workouts', {'date': dateKey(date)},
      where: "id = ? AND status <> 'active'", whereArgs: [id]);

  Future<List<Rec>> listWorkouts() => db.rawQuery('''
    SELECT w.*,
      (SELECT COUNT(*) FROM workout_exercises e WHERE e.workout_id = w.id) AS ex_count,
      (SELECT COUNT(*) FROM set_entries s JOIN workout_exercises e ON s.exercise_id = e.id
        WHERE e.workout_id = w.id AND s.completed = 1 AND s.set_type = 'work') AS done_sets
    FROM workouts w
    ORDER BY w.date DESC, COALESCE(w.started_at_utc, 0) DESC, w.id DESC''');

  Future<FinishSummary> summary(String workoutId) async {
    final r = await db.rawQuery('''
      SELECT SUM(CASE WHEN s.completed = 1 THEN 1 ELSE 0 END) AS d,
             SUM(CASE WHEN s.completed = 0 THEN 1 ELSE 0 END) AS r
      FROM set_entries s JOIN workout_exercises e ON s.exercise_id = e.id
      WHERE e.workout_id = ?''', [workoutId]);
    return FinishSummary((r.first['d'] as int?) ?? 0, (r.first['r'] as int?) ?? 0);
  }

  /// Idempotent: finishing twice does nothing. Unfinished sets are kept as is.
  Future<bool> finishWorkout(String id) async {
    final w = await workout(id);
    if (w == null || w['status'] != 'active') return false;
    final started = w['started_at_utc'] as int?;
    final end = _nowUtcMs;
    final minutes = started == null ? null : ((end - started) / 60000).round();
    final n = await db.update(
        'workouts',
        {
          'status': 'finished',
          'finished_at_utc': end,
          if (minutes != null) 'duration_minutes': minutes,
        },
        where: "id = ? AND status = 'active'",
        whereArgs: [id]);
    return n == 1;
  }

  Future<void> deleteWorkout(String id) => db.transaction((t) async {
        await t.rawDelete('''DELETE FROM set_entries WHERE exercise_id IN
            (SELECT id FROM workout_exercises WHERE workout_id = ?)''', [id]);
        await t.delete('workout_exercises', where: 'workout_id = ?', whereArgs: [id]);
        await t.delete('workouts', where: 'id = ?', whereArgs: [id]);
      });

  /// New workout (status planned) copying exercises and plan; no sets and no
  /// completion flags are copied.
  Future<String> repeatWorkout(String id, {required DateTime date}) =>
      db.transaction((t) async {
        final src = (await t.query('workouts', where: 'id = ?', whereArgs: [id])).first;
        final nid = _uuid.v4();
        await t.insert('workouts', {
          'id': nid,
          'date': dateKey(date),
          'title': src['title'],
          'status': 'planned',
        });
        final exs = await t.query('workout_exercises',
            where: 'workout_id = ?', whereArgs: [id], orderBy: 'sort_order');
        for (final e in exs) {
          await t.insert('workout_exercises', {
            ...e,
            'id': _uuid.v4(),
            'workout_id': nid,
            'note': null,
          });
        }
        return nid;
      });

  // ---------- workout exercises ----------
  Future<List<Rec>> workoutExercises(String workoutId) => db.query(
      'workout_exercises',
      where: 'workout_id = ?', whereArgs: [workoutId], orderBy: 'sort_order');

  Future<String> addExercise(String workoutId, String name) =>
      db.transaction((t) async {
        final ref = await findOrCreateExercise(name, t);
        final c = Sqflite.firstIntValue(await t.rawQuery(
                'SELECT COUNT(*) FROM workout_exercises WHERE workout_id = ?',
                [workoutId])) ??
            0;
        final id = _uuid.v4();
        await t.insert('workout_exercises', {
          'id': id,
          'workout_id': workoutId,
          'exercise_name': name.trim(),
          'exercise_ref_id': ref,
          'sort_order': c + 1,
        });
        return id;
      });

  /// Removes the exercise from this session only (catalogue untouched).
  Future<void> removeExercise(String weId) => db.transaction((t) async {
        final r = await t.query('workout_exercises', where: 'id = ?', whereArgs: [weId]);
        if (r.isEmpty) return;
        final wid = r.first['workout_id'] as String;
        await t.delete('set_entries', where: 'exercise_id = ?', whereArgs: [weId]);
        await t.delete('workout_exercises', where: 'id = ?', whereArgs: [weId]);
        await _renumber(t, wid);
      });

  Future<void> _renumber(DatabaseExecutor t, String wid) async {
    final rows = await t.query('workout_exercises',
        columns: ['id'], where: 'workout_id = ?', whereArgs: [wid], orderBy: 'sort_order, id');
    for (var i = 0; i < rows.length; i++) {
      await t.update('workout_exercises', {'sort_order': i + 1},
          where: 'id = ?', whereArgs: [rows[i]['id']]);
    }
  }

  Future<void> moveExercise(String weId, int delta) => db.transaction((t) async {
        final r = await t.query('workout_exercises', where: 'id = ?', whereArgs: [weId]);
        if (r.isEmpty) return;
        final wid = r.first['workout_id'] as String;
        await _renumber(t, wid);
        final rows = await t.query('workout_exercises',
            where: 'workout_id = ?', whereArgs: [wid], orderBy: 'sort_order');
        final i = rows.indexWhereId(weId);
        final j = i + delta;
        if (i < 0 || j < 0 || j >= rows.length) return;
        await t.update('workout_exercises', {'sort_order': j + 1},
            where: 'id = ?', whereArgs: [rows[i]['id']]);
        await t.update('workout_exercises', {'sort_order': i + 1},
            where: 'id = ?', whereArgs: [rows[j]['id']]);
      });

  Future<void> updatePlan(String weId,
          {int? sets, int? repMin, int? repMax, int? rir, int? restSec, String? note}) =>
      db.update(
          'workout_exercises',
          {
            'plan_sets': sets,
            'plan_rep_min': repMin,
            'plan_rep_max': repMax,
            'plan_rir': rir,
            'plan_rest_sec': restSec,
            'note': note,
          },
          where: 'id = ?',
          whereArgs: [weId]);

  // ---------- sets ----------
  Future<List<Rec>> sets(String weId) => db.query('set_entries',
      where: 'exercise_id = ?', whereArgs: [weId], orderBy: 'set_number');

  /// New set inherits entered values of the previous one but is NOT completed.
  Future<String> addSet(String weId, {bool warmup = false}) =>
      db.transaction((t) async {
        final prev = await t.query('set_entries',
            where: 'exercise_id = ?', whereArgs: [weId], orderBy: 'set_number DESC', limit: 1);
        final id = _uuid.v4();
        await t.insert('set_entries', {
          'id': id,
          'exercise_id': weId,
          'set_number': prev.isEmpty ? 1 : (prev.first['set_number'] as int) + 1,
          'weight_kg': prev.isEmpty ? 0.0 : prev.first['weight_kg'],
          'reps': prev.isEmpty ? 1 : prev.first['reps'],
          'rir': prev.isEmpty ? null : prev.first['rir'],
          'set_type': warmup ? 'warmup' : 'work',
          'completed': 0,
        });
        return id;
      });

  Future<void> updateSet(String id,
          {double? weight, int? reps, Object? rir = kUnset, Object? note = kUnset, String? type}) =>
      db.update(
          'set_entries',
          {
            if (weight != null) 'weight_kg': weight,
            if (reps != null) 'reps': reps,
            if (rir != kUnset) 'rir': rir,
            if (note != kUnset) 'note': note,
            if (type != null) 'set_type': type,
          },
          where: 'id = ?',
          whereArgs: [id]);

  /// Returns true only if this call newly marked the set as completed.
  Future<bool> setCompleted(String id, bool value) async {
    final r = await db.query('set_entries', where: 'id = ?', whereArgs: [id]);
    if (r.isEmpty) return false;
    final was = r.first['completed'] == 1;
    await db.update(
        'set_entries',
        {'completed': value ? 1 : 0, 'completed_at_utc': value ? _nowUtcMs : null},
        where: 'id = ?',
        whereArgs: [id]);
    return value && !was;
  }

  Future<void> deleteSet(String id) => db.transaction((t) async {
        final r = await t.query('set_entries', where: 'id = ?', whereArgs: [id]);
        if (r.isEmpty) return;
        final we = r.first['exercise_id'] as String;
        await t.delete('set_entries', where: 'id = ?', whereArgs: [id]);
        final rows = await t.query('set_entries',
            columns: ['id'], where: 'exercise_id = ?', whereArgs: [we], orderBy: 'set_number');
        for (var i = 0; i < rows.length; i++) {
          await t.update('set_entries', {'set_number': i + 1},
              where: 'id = ?', whereArgs: [rows[i]['id']]);
        }
      });

  // ---------- history ----------
  /// Sessions (newest first) of one catalogue exercise with their sets.
  Future<List<Map<String, Object?>>> exerciseHistory(String refId) async {
    final sessions = await db.rawQuery('''
      SELECT e.id AS we_id, e.note AS note, w.id AS workout_id, w.date, w.title, w.status
      FROM workout_exercises e JOIN workouts w ON e.workout_id = w.id
      WHERE e.exercise_ref_id = ?
      ORDER BY w.date DESC, COALESCE(w.started_at_utc, 0) DESC, w.id DESC''', [refId]);
    final out = <Map<String, Object?>>[];
    for (final s in sessions) {
      out.add({...s, 'sets': await sets(s['we_id'] as String)});
    }
    return out;
  }

  /// Sets of the latest earlier finished session of the same exercise (hints).
  Future<List<Rec>> previousSets(String refId, String currentWorkoutId) async {
    final cur = await workout(currentWorkoutId);
    if (cur == null) return [];
    final r = await db.rawQuery('''
      SELECT e.id FROM workout_exercises e JOIN workouts w ON e.workout_id = w.id
      WHERE e.exercise_ref_id = ? AND w.status = 'finished' AND w.id <> ?
        AND w.date <= ?
      ORDER BY w.date DESC, COALESCE(w.started_at_utc, 0) DESC, w.id DESC LIMIT 1''',
        [refId, currentWorkoutId, cur['date']]);
    if (r.isEmpty) return [];
    final all = await sets(r.first['id'] as String);
    return all.where((s) => s['completed'] == 1 && s['set_type'] == 'work').toList();
  }
}

const Object kUnset = Object();

extension _Idx on List<Rec> {
  int indexWhereId(String id) => indexWhere((r) => r['id'] == id);
}
