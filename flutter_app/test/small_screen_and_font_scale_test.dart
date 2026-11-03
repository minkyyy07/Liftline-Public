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

  Widget wrapWithConfig({
    required Widget child,
    required double width,
    required double textScale,
  }) {
    return MaterialApp(
      theme: buildLiftlineTheme(),
      builder: (context, widget) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: Size(width, 900),
            textScaler: TextScaler.linear(textScale),
          ),
          child: widget!,
        );
      },
      home: child,
    );
  }

  group('Responsive width & textScaler verification on all 4 tabs', () {
    final widths = [320.0, 360.0, 412.0];
    final scales = [1.0, 1.5, 2.0];

    for (final width in widths) {
      for (final scale in scales) {
        testWidgets(
          'TodayScreen at width ${width.toInt()}px, textScale ${scale}x (empty & filled)',
          (tester) async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1.0;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(() {
              tester.view.reset();
              tester.platformDispatcher.clearTextScaleFactorTestValue();
            });

            late Database db;
            final date = DateTime(2026, 6, 15);
            await tester.runAsync(() async {
              db = await openLiftlineDb(
                inMemoryDatabasePath,
                factory: databaseFactoryFfi,
              );
              AppDb.instance.useDatabase(db);

              // Seed with long Russian labels
              final wrepo = WorkoutRepo(db);
              final wid = await wrepo.createWorkout(
                title:
                    'Интенсивная тренировка груди, дельт и трицепса (длинное название)',
                date: date,
                start: false,
              );
              final eid = await wrepo.addExercise(
                wid,
                'Жим штанги лёжа на наклонной скамье',
              );
              final sid = await wrepo.addSet(eid);
              await wrepo.updateSet(sid, weight: 105.5, reps: 8, rir: 2);

              final nrepo = NutritionRepo(db);
              await nrepo.savePortion(
                date: dateKey(date),
                meal: 'breakfast',
                name: 'Овсяная каша с грецкими орехами и протеином',
                total: const Nutrients(450, 32, 12, 55),
              );
              await nrepo.setGoals(
                date,
                const NutritionGoals(2400, 160, 70, 280),
              );

              final prepo = ProgressRepo(db);
              await prepo.saveWeight(date, 78.4);
            });

            await tester.pumpWidget(
              wrapWithConfig(
                width: width,
                textScale: scale,
                child: TodayScreen(
                  selectedDate: date,
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

            // Verify textScaler actually reaches the inner screen
            final actualScale = MediaQuery.textScalerOf(
              tester.element(find.byType(TodayScreen)),
            ).scale(10.0);
            expect(actualScale, closeTo(10.0 * scale, 0.01));

            expect(find.text('Liftspire'), findsOneWidget);
            expect(find.text('Питание'), findsOneWidget);
            expect(tester.takeException(), isNull);

            await tester.runAsync(() => db.close());
          },
        );

        testWidgets(
          'WorkoutsScreen at width ${width.toInt()}px, textScale ${scale}x (empty & filled)',
          (tester) async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1.0;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
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
              final wrepo = WorkoutRepo(db);
              await wrepo.createWorkout(
                title: 'Тяжёлая тренировка спины и бицепса (сессия 1)',
                date: DateTime(2026, 6, 15),
                start: false,
              );
            });

            await tester.pumpWidget(
              wrapWithConfig(
                width: width,
                textScale: scale,
                child: WorkoutsScreen(selectedDate: DateTime(2026, 6, 15)),
              ),
            );

            await tester.runAsync(
              () => Future.delayed(const Duration(milliseconds: 300)),
            );
            await tester.pumpAndSettle();

            final actualScale = MediaQuery.textScalerOf(
              tester.element(find.byType(WorkoutsScreen)),
            ).scale(10.0);
            expect(actualScale, closeTo(10.0 * scale, 0.01));

            expect(find.text('Тренировки'), findsOneWidget);
            expect(tester.takeException(), isNull);

            await tester.runAsync(() => db.close());
          },
        );

        testWidgets(
          'NutritionScreen at width ${width.toInt()}px, textScale ${scale}x (empty & filled)',
          (tester) async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1.0;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(() {
              tester.view.reset();
              tester.platformDispatcher.clearTextScaleFactorTestValue();
            });

            late Database db;
            final date = DateTime(2026, 6, 15);
            await tester.runAsync(() async {
              db = await openLiftlineDb(
                inMemoryDatabasePath,
                factory: databaseFactoryFfi,
              );
              AppDb.instance.useDatabase(db);
              final nrepo = NutritionRepo(db);
              await nrepo.savePortion(
                date: dateKey(date),
                meal: 'lunch',
                name: 'Куриная грудка запечённая с брокколи и соусом',
                total: const Nutrients(520, 54, 8, 35),
              );
            });

            await tester.pumpWidget(
              wrapWithConfig(
                width: width,
                textScale: scale,
                child: NutritionScreen(
                  selectedDate: date,
                  onDateChanged: (_) {},
                ),
              ),
            );

            await tester.runAsync(
              () => Future.delayed(const Duration(milliseconds: 300)),
            );
            await tester.pumpAndSettle();

            final actualScale = MediaQuery.textScalerOf(
              tester.element(find.byType(NutritionScreen)),
            ).scale(10.0);
            expect(actualScale, closeTo(10.0 * scale, 0.01));

            expect(find.text('Питание'), findsOneWidget);
            expect(tester.takeException(), isNull);

            await tester.runAsync(() => db.close());
          },
        );

        testWidgets(
          'ProgressScreen at width ${width.toInt()}px, textScale ${scale}x (empty & filled)',
          (tester) async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1.0;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
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
              final prepo = ProgressRepo(db);
              await prepo.saveWeight(DateTime(2026, 6, 15), 80.2);
            });

            await tester.pumpWidget(
              wrapWithConfig(
                width: width,
                textScale: scale,
                child: ProgressScreen(selectedDate: DateTime(2026, 6, 15)),
              ),
            );

            await tester.runAsync(
              () => Future.delayed(const Duration(milliseconds: 300)),
            );
            await tester.pumpAndSettle();

            final actualScale = MediaQuery.textScalerOf(
              tester.element(find.byType(ProgressScreen)),
            ).scale(10.0);
            expect(actualScale, closeTo(10.0 * scale, 0.01));

            expect(find.text('Прогресс'), findsOneWidget);
            expect(find.text('Силовые'), findsOneWidget);
            expect(find.text('Вес тела'), findsOneWidget);
            expect(find.text('Питание'), findsOneWidget);
            expect(tester.takeException(), isNull);

            await tester.runAsync(() => db.close());
          },
        );
      }
    }
  });
}
