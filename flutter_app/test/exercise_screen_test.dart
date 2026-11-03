import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liftline_app/db.dart';
import 'package:liftline_app/repo.dart';
import 'package:liftline_app/rest_timer.dart';
import 'package:liftline_app/theme.dart';
import 'package:liftline_app/workouts_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('enter set, validation blocks completion, completion saves', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    late WorkoutRepo repo;
    late String weId;
    late String wid;
    await tester.runAsync(() async {
      final db = await openLiftlineDb(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      AppDb.instance.useDatabase(db);
      repo = WorkoutRepo(db);
      wid = await repo.createWorkout(
        title: 'T',
        date: DateTime.now(),
        start: true,
      );
      weId = await repo.addExercise(wid, 'Жим');
      await repo.addSet(weId);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildLiftlineTheme(),
        home: ExerciseScreen(
          workoutId: wid,
          exerciseIds: [weId],
          initialIndex: 0,
        ),
      ),
    );
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    expect(find.text('Жим'), findsWidgets);
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));

    // invalid reps -> not saved, completion blocked
    await tester.enterText(fields.at(1), '0');
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(find.text('Повторы ≥ 1'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    var s = await tester.runAsync(() => repo.sets(weId));
    expect(s!.single['completed'], 0);
    expect(s.single['reps'], 1); // last valid value kept

    // valid values with decimal comma -> complete
    await tester.enterText(fields.at(0), '82,5');
    await tester.enterText(fields.at(1), '5');
    await tester.enterText(fields.at(2), '2');
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.tap(find.byType(Checkbox));
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    s = await tester.runAsync(() => repo.sets(weId));
    expect(s!.single['weight_kg'], 82.5);
    expect(s.single['reps'], 5);
    expect(s.single['rir'], 2);
    expect(s.single['completed'], 1);
    // rest timer started (default 120 s) for active workout
    expect(find.byIcon(Icons.timer), findsOneWidget);

    await tester.runAsync(() => RestTimerController.instance.stop());

    // re-create the screen: saved data restored
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLiftlineTheme(),
        home: ExerciseScreen(
          workoutId: wid,
          exerciseIds: [weId],
          initialIndex: 0,
        ),
      ),
    );
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    expect(find.text('82.5'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => AppDb.instance.db.close());
  });
}
