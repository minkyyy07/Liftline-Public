import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:liftline_app/app_shell.dart';
import 'package:liftline_app/db.dart';
import 'package:liftline_app/nutrition_calc.dart';
import 'package:liftline_app/nutrition_repo.dart';
import 'package:liftline_app/progress_repo.dart';
import 'package:liftline_app/repo.dart';
import 'package:liftline_app/theme.dart';
import 'package:liftline_app/week_utils.dart';
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

  Widget buildAppWithConfig({
    required double width,
    required double textScale,
    EdgeInsets padding = const EdgeInsets.only(top: 24, bottom: 16),
    EdgeInsets viewInsets = EdgeInsets.zero,
  }) {
    return MaterialApp(
      title: 'Liftspire',
      debugShowCheckedModeBanner: false,
      theme: buildLiftlineTheme(),
      builder: (context, widget) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: Size(width, 850),
            padding: padding,
            viewInsets: viewInsets,
            textScaler: TextScaler.linear(textScale),
          ),
          child: widget!,
        );
      },
      home: const MainNavigationScreen(),
    );
  }

  group('MainNavigationScreen full interface responsive tests (320, 360, 412px & 1.0, 1.5, 2.0x)', () {
    final configs = [
      (width: 320.0, scale: 1.0),
      (width: 320.0, scale: 1.5),
      (width: 320.0, scale: 2.0),
      (width: 360.0, scale: 1.5),
      (width: 412.0, scale: 1.0),
      (width: 412.0, scale: 2.0),
    ];

    for (final cfg in configs) {
      testWidgets(
        'Empty states at ${cfg.width.toInt()}px, scale ${cfg.scale}x with safe area',
        (tester) async {
          tester.view.physicalSize = Size(cfg.width, 850);
          tester.view.devicePixelRatio = 1.0;
          tester.platformDispatcher.textScaleFactorTestValue = cfg.scale;
          addTearDown(() {
            tester.view.reset();
            tester.platformDispatcher.clearTextScaleFactorTestValue();
          });

          late Database db;
          await tester.runAsync(() async {
            db = await openLiftlineDb(
              inMemoryDatabasePath,
              factory: databaseFactoryFfi,
            );
            AppDb.instance.useDatabase(db);
          });

          await tester.pumpWidget(
            buildAppWithConfig(
              width: cfg.width,
              textScale: cfg.scale,
              padding: const EdgeInsets.only(top: 44, bottom: 34),
            ),
          );
          await tester.runAsync(
            () => Future.delayed(const Duration(milliseconds: 200)),
          );
          await tester.pumpAndSettle();

          expect(find.text('Liftspire'), findsOneWidget);
          expect(tester.takeException(), isNull);

          // Workouts
          await tester.tap(find.byIcon(Icons.fitness_center_outlined));
          await tester.runAsync(
            () => Future.delayed(const Duration(milliseconds: 200)),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // Nutrition
          await tester.tap(find.byIcon(Icons.restaurant_outlined));
          await tester.runAsync(
            () => Future.delayed(const Duration(milliseconds: 200)),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // Progress
          await tester.tap(find.byIcon(Icons.show_chart_outlined));
          await tester.runAsync(
            () => Future.delayed(const Duration(milliseconds: 200)),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // PopScope back to Tab 0
          final popHandled = await tester.binding.handlePopRoute();
          expect(popHandled, isTrue);
          await tester.pumpAndSettle();
          expect(find.text('Liftspire'), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.runAsync(() => db.close());
        },
      );

      testWidgets(
        'Filled states at ${cfg.width.toInt()}px, scale ${cfg.scale}x with keyboard open and long Russian text',
        (tester) async {
          tester.view.physicalSize = Size(cfg.width, 850);
          tester.view.devicePixelRatio = 1.0;
          tester.platformDispatcher.textScaleFactorTestValue = cfg.scale;
          addTearDown(() {
            tester.view.reset();
            tester.platformDispatcher.clearTextScaleFactorTestValue();
          });

          late Database db;
          final today = dateOnly(DateTime.now());
          await tester.runAsync(() async {
            db = await openLiftlineDb(
              inMemoryDatabasePath,
              factory: databaseFactoryFfi,
            );
            AppDb.instance.useDatabase(db);

            final wrepo = WorkoutRepo(db);
            final wid = await wrepo.createWorkout(
              title: 'Комплексная силовая тренировка для всего тела с отягощениями',
              date: today,
              start: true,
            );
            final eid = await wrepo.addExercise(
              wid,
              'Жим штанги от груди в тренажере Смита с широким хватом',
            );
            final sid = await wrepo.addSet(eid);
            await wrepo.updateSet(sid, weight: 87.5, reps: 10, rir: 2);

            final nrepo = NutritionRepo(db);
            await nrepo.savePortion(
              date: dateKey(today),
              meal: 'breakfast',
              name: 'Каша гречневая с говяжьим фаршем и овощным рагу (большая порция)',
              total: const Nutrients(620, 48, 16, 70),
            );
            await nrepo.setGoals(
              today,
              const NutritionGoals(2500, 180, 75, 290),
            );

            final prepo = ProgressRepo(db);
            await prepo.saveWeight(today, 82.4);
          });

          await tester.pumpWidget(
            buildAppWithConfig(
              width: cfg.width,
              textScale: cfg.scale,
              padding: const EdgeInsets.only(top: 48, bottom: 34),
              viewInsets: const EdgeInsets.only(bottom: 220), // virtual keyboard
            ),
          );
          await tester.runAsync(
            () => Future.delayed(const Duration(milliseconds: 200)),
          );
          await tester.pumpAndSettle();

          expect(find.text('Liftspire'), findsOneWidget);
          expect(tester.takeException(), isNull);

          // Workouts tab
          await tester.tap(find.byIcon(Icons.fitness_center_outlined));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // Nutrition tab
          await tester.tap(find.byIcon(Icons.restaurant_outlined));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // Progress tab
          await tester.tap(find.byIcon(Icons.show_chart_outlined));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          await tester.runAsync(() => db.close());
        },
      );
    }
  });
}
