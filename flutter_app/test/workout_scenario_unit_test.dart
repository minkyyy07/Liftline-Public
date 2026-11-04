import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:liftline_app/calc.dart';
import 'package:liftline_app/db.dart';
import 'package:liftline_app/repo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final ffiFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDb appDb;
  late WorkoutRepo repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ll_unit_scen_');
    appDb = AppDb.isolated();
    final uniqueUser = 'scen_user_${DateTime.now().microsecondsSinceEpoch}';
    await appDb.switchToUser(uniqueUser, factory: ffiFactory);
    repo = WorkoutRepo(appDb.db);
  });

  tearDown(() async {
    if (appDb.isOpen) await appDb.db.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Workout Scenario Unit & Flow Logic Tests', () {
    test('1. Create planned workout on chosen date, add exercise, fill sets, verify offline persistance', () async {
      final plannedDate = DateTime(2026, 11, 20);

      // Create planned workout
      final workoutId = await repo.createWorkout(
        title: 'День ног',
        date: plannedDate,
        start: false,
        status: 'planned',
      );

      final w = await repo.workout(workoutId);
      expect(w!['status'], 'planned');
      expect(w['date'], '2026-11-20');
      expect(w['title'], 'День ног');

      // Add exercise from catalogue
      final exName = 'Приседания со штангой';
      final weId = await repo.addExercise(workoutId, exName);
      final exercises = await repo.workoutExercises(workoutId);
      expect(exercises.length, 1);
      expect(exercises.first['exercise_name'], exName);

      // Add set, enter weight & reps
      final setId = await repo.addSet(weId);
      await repo.updateSet(setId, weight: 140.0, reps: 5);
      await repo.setCompleted(setId, true);

      final sets = await repo.sets(weId);
      expect(sets.length, 1);
      expect(sets.first['weight_kg'], 140.0);
      expect(sets.first['reps'], 5);
      expect(sets.first['completed'], 1);

      // Start workout: status becomes active
      await repo.startWorkout(workoutId);
      final startedW = await repo.workout(workoutId);
      expect(startedW!['status'], 'active');
      expect(startedW['started_at_utc'], isNotNull);

      // Finish workout: status becomes finished
      await repo.finishWorkout(workoutId);
      final finishedW = await repo.workout(workoutId);
      expect(finishedW!['status'], 'finished');
      expect(finishedW['finished_at_utc'], isNotNull);

      // Verify calculations
      final summary = await repo.summary(workoutId);
      expect(summary.done, 1);
      expect(summary.remaining, 0);

      final sData = SetData(140.0, 5, completed: true, warmup: false);
      expect(workingVolume([sData]), 700.0); // 140 * 5
      expect(sessionE1rm([sData]), closeTo(163.33, 0.05)); // 140 * (1 + 5/30) = 163.33
    });

    test('2. Unfilled set does not count as completed working volume', () {
      final sIncomplete = SetData(0.0, 0, completed: false, warmup: false);
      final sWarmup = SetData(60.0, 10, completed: true, warmup: true);
      final sDone = SetData(100.0, 5, completed: true, warmup: false);

      final vol = workingVolume([sIncomplete, sWarmup, sDone]);
      expect(vol, 500.0); // only sDone counts
    });
  });
}
