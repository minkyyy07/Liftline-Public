import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:liftline_app/db.dart';
import 'package:liftline_app/nutrition_calc.dart';
import 'package:liftline_app/nutrition_repo.dart';
import 'package:liftline_app/nutrition_ui.dart';
import 'package:liftline_app/progress_repo.dart';
import 'package:liftline_app/progress_ui.dart';
import 'package:liftline_app/repo.dart';
import 'package:liftline_app/theme.dart';
import 'package:liftline_app/today_screen.dart';
import 'package:liftline_app/week_utils.dart';
import 'package:liftline_app/workouts_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'Filled state: multiple meals, long names, goal not set / set / exceeded',
    (tester) async {
      final now = DateTime(2026, 6, 15);
      final key = dateKey(now);

      // 1. Goal not set: facts only, no fake remaining or fake progress
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLiftlineTheme(),
          home: Scaffold(
            body: NutritionSummaryCard(
              totals: const Nutrients(1650, 110, 55, 180),
              goals: const NutritionGoals(null, null, null, null),
              hasEntries: true,
              onSetGoals: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1650 ккал съедено'), findsOneWidget);
      expect(find.text('Задать цель'), findsOneWidget);
      expect(find.textContaining('Осталось'), findsNothing);
      expect(find.textContaining('Сверх цели'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      // 2. Goal set and not exceeded: shows eaten, goal, remaining
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLiftlineTheme(),
          home: Scaffold(
            body: NutritionSummaryCard(
              totals: const Nutrients(1800, 120, 60, 200),
              goals: const NutritionGoals(2200, 140, 70, 250),
              hasEntries: true,
              onSetGoals: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1800'), findsOneWidget);
      expect(find.text(' / 2200 ккал'), findsOneWidget);
      expect(find.text('Осталось: 400 ккал'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // 3. Goal exceeded: shows "Сверх цели: ...", not negative remaining
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLiftlineTheme(),
          home: Scaffold(
            body: NutritionSummaryCard(
              totals: const Nutrients(2550, 150, 85, 300),
              goals: const NutritionGoals(2200, 140, 70, 250),
              hasEntries: true,
              onSetGoals: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2550'), findsOneWidget);
      expect(find.text(' / 2200 ккал'), findsOneWidget);
      expect(find.text('Сверх цели: 350 ккал'), findsOneWidget);
      expect(find.textContaining('Осталось'), findsNothing);
      expect(find.textContaining('-'), findsNothing);

      // 4. Multiple meals and very long product names in NutritionScreen
      late Database db;
      await tester.runAsync(() async {
        db = await openLiftlineDb(
          inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        );
        AppDb.instance.useDatabase(db);
        final nrepo = NutritionRepo(db);

        // Breakfast with very long name
        await nrepo.savePortion(
          date: key,
          meal: 'breakfast',
          name:
              'Овсяная каша из цельного зерна с ягодами годжи, миндалём и мёдом разнотравье',
          total: const Nutrients(450, 15, 12, 70),
        );
        // Lunch
        await nrepo.saveProduct(
          date: key,
          meal: 'lunch',
          name: 'Куриное филе грудки запечённое с прованскими травами',
          grams: 200,
          per100: const Nutrients(165, 31, 3.6, 0),
        );
        // Dinner
        await nrepo.savePortion(
          date: key,
          meal: 'dinner',
          name: 'Лосось на пару с брокколи',
          total: const Nutrients(520, 42, 28, 12),
        );
        // Snack
        await nrepo.savePortion(
          date: key,
          meal: 'snack',
          name: 'Греческий йогурт натуральный 2%',
          total: const Nutrients(130, 16, 4, 6),
        );
      });

      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      await tester.pumpWidget(
        MaterialApp(
          theme: buildLiftlineTheme(),
          home: NutritionScreen(selectedDate: now, onDateChanged: (_) {}),
        ),
      );
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Овсяная каша'), findsOneWidget);
      expect(find.textContaining('Куриное филе'), findsOneWidget);
      expect(find.textContaining('Лосось на пару'), findsOneWidget);
      expect(find.textContaining('Греческий йогурт'), findsOneWidget);
      expect(tester.takeException(), isNull); // No layout/rendering errors

      await tester.runAsync(() => db.close());
    },
  );

  testWidgets(
    'Filled state: workout with multiple exercises and sets on TodayScreen and WorkoutsScreen',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      final now = DateTime(2026, 6, 15);
      late Database db;

      await tester.runAsync(() async {
        db = await openLiftlineDb(
          inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        );
        AppDb.instance.useDatabase(db);
        final wrepo = WorkoutRepo(db);

        final wid = await wrepo.createWorkout(
          title: 'День жима и спины (интенсивная тренировка)',
          date: now,
          start: false,
        );
        final ex1 = await wrepo.addExercise(
          wid,
          'Жим штанги лёжа на горизонтальной скамье',
        );
        final s1 = await wrepo.addSet(ex1);
        final s2 = await wrepo.addSet(ex1);
        await wrepo.updateSet(s1, weight: 100, reps: 5, rir: 2);
        await wrepo.setCompleted(s1, true);
        await wrepo.updateSet(s2, weight: 100, reps: 5, rir: 1);
        await wrepo.setCompleted(s2, true);

        final ex2 = await wrepo.addExercise(
          wid,
          'Тяга верхнего блока широким хватом к груди',
        );
        final s3 = await wrepo.addSet(ex2);
        await wrepo.updateSet(s3, weight: 70, reps: 10, rir: 3);
        await wrepo.setCompleted(s3, true);

        await db.update(
          'workouts',
          {'duration_minutes': 55, 'status': 'finished'},
          where: 'id = ?',
          whereArgs: [wid],
        );
      });

      // Test on TodayScreen
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLiftlineTheme(),
          home: TodayScreen(
            selectedDate: now,
            isFollowingToday: false,
            onDateChanged: (_) {},
            onGoToTab: (_) {},
          ),
        ),
      );
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('День жима и спины (интенсивная тренировка)'),
        findsOneWidget,
      );
      expect(find.text('Длительность: 55 мин'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Test on WorkoutsScreen
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLiftlineTheme(),
          home: WorkoutsScreen(selectedDate: now),
        ),
      );
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('День жима и спины (интенсивная тренировка)'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.runAsync(() => db.close());
    },
  );

  testWidgets('Filled state: weight measurements and progress data', (
    tester,
  ) async {
    final now = DateTime(2026, 6, 15);
    late Database db;

    await tester.runAsync(() async {
      db = await openLiftlineDb(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      AppDb.instance.useDatabase(db);
      final prepo = ProgressRepo(db);

      // Add several weight measurements across recent days
      await prepo.saveWeight(DateTime(2026, 6, 10), 82.5);
      await prepo.saveWeight(DateTime(2026, 6, 12), 82.2);
      await prepo.saveWeight(DateTime(2026, 6, 14), 81.9);
      await prepo.saveWeight(DateTime(2026, 6, 15), 81.7);
    });

    // Test WeightTab
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLiftlineTheme(),
        home: Scaffold(body: WeightTab(end: now)),
      ),
    );
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Записать вес'), findsOneWidget);
    expect(find.textContaining('81.7 кг'), findsWidgets);
    expect(find.textContaining('81.9 кг'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });
}
