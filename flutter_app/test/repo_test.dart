import 'package:flutter_test/flutter_test.dart';
import 'package:liftline_app/db.dart';
import 'package:liftline_app/repo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late WorkoutRepo repo;
  var clock = DateTime(2026, 5, 10, 10, 0);

  setUp(() async {
    clock = DateTime(2026, 5, 10, 10, 0);
    final db = await openLiftlineDb(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    repo = WorkoutRepo(db, now: () => clock);
  });
  tearDown(() => repo.db.close());

  test(
    'exercise is one catalogue entity across workouts; rename keeps history',
    () async {
      final w1 = await repo.createWorkout(
        title: 'A',
        date: clock,
        start: false,
      );
      final w2 = await repo.createWorkout(
        title: 'B',
        date: clock,
        start: false,
      );
      final e1 = await repo.addExercise(w1, 'Жим лежа');
      final e2 = await repo.addExercise(w2, ' Жим лежа ');
      expect((await repo.activeExercises()).length, 1);
      final ref =
          (await repo.workoutExercises(w1)).first['exercise_ref_id'] as String;
      await repo.renameExercise(ref, 'Жим штанги');
      expect((await repo.exerciseHistory(ref)).length, 2);
      await repo.archiveExercise(ref);
      expect((await repo.exerciseHistory(ref)).length, 2); // history intact
      expect(e1 == e2, isFalse);
    },
  );

  test(
    'only one active workout; finish is idempotent, keeps unfinished sets',
    () async {
      final w = await repo.createWorkout(title: 'A', date: clock, start: true);
      await expectLater(
        repo.createWorkout(title: 'B', date: clock, start: true),
        throwsA(isA<ActiveWorkoutExists>()),
      );
      final e = await repo.addExercise(w, 'Присед');
      final s1 = await repo.addSet(e);
      await repo.addSet(e);
      await repo.updateSet(s1, weight: 100, reps: 5);
      expect(await repo.setCompleted(s1, true), isTrue);
      final sum = await repo.summary(w);
      expect((sum.done, sum.remaining), (1, 1));
      clock = clock.add(const Duration(minutes: 45));
      expect(await repo.finishWorkout(w), isTrue);
      expect(await repo.finishWorkout(w), isFalse);
      final row = (await repo.workout(w))!;
      expect(row['status'], 'finished');
      expect(row['duration_minutes'], 45);
      final sets = await repo.sets(e);
      expect(sets.map((s) => s['completed']), [1, 0]); // not auto-completed
    },
  );

  test(
    'active workout date is fixed at start (not moved after midnight)',
    () async {
      final w = await repo.createWorkout(title: 'A', date: clock, start: true);
      clock = DateTime(2026, 5, 11, 0, 30);
      await repo.finishWorkout(w);
      expect((await repo.workout(w))!['date'], '2026-05-10');
    },
  );

  test(
    'set completion: only new completion reports true; uncheck keeps values',
    () async {
      final w = await repo.createWorkout(title: 'A', date: clock, start: true);
      final e = await repo.addExercise(w, 'Тяга');
      final s = await repo.addSet(e);
      await repo.updateSet(s, weight: 80.5, reps: 6, rir: null);
      expect(await repo.setCompleted(s, true), isTrue);
      expect(await repo.setCompleted(s, true), isFalse); // no new rest
      expect(await repo.setCompleted(s, false), isFalse);
      final r = (await repo.sets(e)).single;
      expect(r['weight_kg'], 80.5);
      expect(r['reps'], 6);
      expect(r['rir'], isNull); // empty is not 0
      expect(r['completed'], 0);
    },
  );

  test(
    'new set inherits values but is not completed; delete renumbers',
    () async {
      final w = await repo.createWorkout(title: 'A', date: clock, start: true);
      final e = await repo.addExercise(w, 'Тяга');
      final s1 = await repo.addSet(e);
      await repo.updateSet(s1, weight: 70, reps: 8, rir: 2);
      await repo.setCompleted(s1, true);
      final s2 = await repo.addSet(e);
      await repo.addSet(e);
      var sets = await repo.sets(e);
      expect(sets[1]['weight_kg'], 70);
      expect(sets[1]['rir'], 2);
      expect(sets[1]['completed'], 0);
      await repo.deleteSet(s2);
      sets = await repo.sets(e);
      expect(sets.map((s) => s['set_number']), [1, 2]);
    },
  );

  test(
    'repeat copies structure/plan, new ids, no sets or completion',
    () async {
      final w = await repo.createWorkout(
        title: 'Push',
        date: clock,
        start: true,
      );
      final e = await repo.addExercise(w, 'Жим');
      await repo.updatePlan(
        e,
        sets: 3,
        repMin: 6,
        repMax: 8,
        rir: 2,
        restSec: 90,
      );
      final s = await repo.addSet(e);
      await repo.setCompleted(s, true);
      await repo.finishWorkout(w);
      final n = await repo.repeatWorkout(w, date: DateTime(2026, 5, 12));
      expect(n, isNot(w));
      final ex = await repo.workoutExercises(n);
      expect(ex.single['id'], isNot(e));
      expect(ex.single['plan_rest_sec'], 90);
      expect(await repo.sets(ex.single['id'] as String), isEmpty);
      expect((await repo.workout(n))!['status'], 'planned');
      expect((await repo.sets(e)).single['completed'], 1); // source untouched
    },
  );

  test(
    'delete workout removes its sets only; remove exercise keeps others',
    () async {
      final w1 = await repo.createWorkout(
        title: 'A',
        date: clock,
        start: false,
      );
      final w2 = await repo.createWorkout(
        title: 'B',
        date: clock,
        start: false,
      );
      final a = await repo.addExercise(w1, 'X');
      final b = await repo.addExercise(w2, 'X');
      await repo.addSet(a);
      await repo.addSet(b);
      await repo.deleteWorkout(w1);
      expect(await repo.sets(a), isEmpty);
      expect((await repo.sets(b)).length, 1);
      expect((await repo.activeExercises()).length, 1);
      final c = await repo.addExercise(w2, 'Y');
      await repo.moveExercise(c, -1);
      expect((await repo.workoutExercises(w2)).first['id'], c);
      await repo.removeExercise(c);
      expect((await repo.workoutExercises(w2)).single['id'], b);
    },
  );

  test('previousSets gives earlier finished work sets only', () async {
    final old = await repo.createWorkout(
      title: 'old',
      date: DateTime(2026, 5, 1),
      start: false,
    );
    final eo = await repo.addExercise(old, 'Жим');
    final so = await repo.addSet(eo);
    await repo.updateSet(so, weight: 90, reps: 5);
    await repo.setCompleted(so, true);
    final warm = await repo.addSet(eo, warmup: true);
    await repo.setCompleted(warm, true);
    final cur = await repo.createWorkout(
      title: 'cur',
      date: clock,
      start: true,
    );
    await repo.addExercise(cur, 'Жим');
    final ref =
        (await repo.workoutExercises(cur)).single['exercise_ref_id'] as String;
    final prev = await repo.previousSets(ref, cur);
    expect(prev.length, 1);
    expect(prev.single['weight_kg'], 90);
    // an earlier workout never sees a later one
    final fut = await repo.createWorkout(
      title: 'fut',
      date: DateTime(2026, 6, 1),
      start: false,
    );
    final ef = await repo.addExercise(fut, 'Жим');
    final sf = await repo.addSet(ef);
    await repo.setCompleted(sf, true);
    expect((await repo.previousSets(ref, old)), isEmpty);
  });
}
