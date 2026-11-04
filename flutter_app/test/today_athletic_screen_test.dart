import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:liftline_app/db.dart';
import 'package:liftline_app/nutrition_calc.dart';
import 'package:liftline_app/nutrition_repo.dart';
import 'package:liftline_app/progress_repo.dart';
import 'package:liftline_app/repo.dart';
import 'package:liftline_app/theme.dart';
import 'package:liftline_app/today_screen.dart';
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

  Widget createTestWidget({
    required Widget child,
    double width = 360.0,
    double textScale = 1.0,
  }) {
    return MaterialApp(
      theme: buildLiftlineTheme(),
      builder: (context, widget) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: Size(width, 1200),
            textScaler: TextScaler.linear(textScale),
          ),
          child: widget!,
        );
      },
      home: child,
    );
  }

  group('TodayScreen Athletic Focus widget tests', () {
    testWidgets('Empty state renders correctly with real data indicators', (tester) async {
      tester.view.physicalSize = const Size(360, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      late Database db;
      final date = DateTime(2026, 11, 4);

      await tester.runAsync(() async {
        db = await openLiftlineDb(inMemoryDatabasePath, factory: databaseFactoryFfi);
        AppDb.instance.useDatabase(db);
      });

      await tester.pumpWidget(
        createTestWidget(
          child: TodayScreen(
            selectedDate: date,
            isFollowingToday: true,
            onDateChanged: (_) {},
            onGoToTab: (_) {},
          ),
        ),
      );

      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 250)));
      await tester.pumpAndSettle();

      // Brand & Header
      expect(find.text('Liftspire'), findsOneWidget);
      expect(find.text('Тренировки дня'), findsOneWidget);

      // Empty workout hero
      expect(find.text('На эту дату тренировок нет'), findsOneWidget);
      expect(find.text('Создать тренировку'), findsOneWidget);
      expect(find.text('Выбрать из списка'), findsOneWidget);

      // Nutrition without goals
      expect(find.text('Питание'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('ккал'), findsOneWidget);
      expect(find.text('Цель не задана'), findsOneWidget);
      expect(find.text('Задать цель'), findsOneWidget);

      // Weight without records
      expect(find.text('--'), findsOneWidget);
      expect(find.text('Измерений до этой даты нет'), findsOneWidget);

      // Quick actions
      expect(find.text('Добавить еду'), findsOneWidget);
      expect(find.text('Записать вес'), findsWidgets);

      expect(tester.takeException(), isNull);
      await tester.runAsync(() => db.close());
    });

    testWidgets('Filled state with planned workout, nutrition goals & body weight', (tester) async {
      tester.view.physicalSize = const Size(360, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      late Database db;
      final date = DateTime(2026, 11, 4);

      await tester.runAsync(() async {
        db = await openLiftlineDb(inMemoryDatabasePath, factory: databaseFactoryFfi);
        AppDb.instance.useDatabase(db);

        // Seed workout
        final wrepo = WorkoutRepo(db);
        await wrepo.createWorkout(
          title: 'Силовая тренировка: Жим и трицепс',
          date: date,
          start: false,
        );

        // Seed nutrition
        final nrepo = NutritionRepo(db);
        await nrepo.setGoals(date, const NutritionGoals(2400, 160, 70, 260));
        await nrepo.savePortion(
          date: dateKey(date),
          meal: 'lunch',
          name: 'Куриная грудка с рисом',
          total: const Nutrients(650, 48, 14, 80),
        );

        // Seed weight
        final prepo = ProgressRepo(db);
        await prepo.saveWeight(date, 82.4);
      });

      await tester.pumpWidget(
        createTestWidget(
          child: TodayScreen(
            selectedDate: date,
            isFollowingToday: true,
            onDateChanged: (_) {},
            onGoToTab: (_) {},
          ),
        ),
      );

      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 250)));
      await tester.pumpAndSettle();

      // Planned workout hero
      expect(find.text('Силовая тренировка: Жим и трицепс'), findsOneWidget);
      expect(find.text('ЗАПЛАНИРОВАНО'), findsOneWidget);
      expect(find.text('Начать тренировку'), findsOneWidget);

      // Nutrition with goal
      expect(find.text('650'), findsOneWidget);
      expect(find.text('/ 2400 ккал'), findsOneWidget);
      expect(find.text('Записей за день: 1'), findsOneWidget);
      expect(find.text('Изменить цель'), findsOneWidget);
      expect(find.text('48 / 160 г'), findsOneWidget);

      // Body weight (locale-formatted)
      expect(find.text(fmtG(82.4)), findsOneWidget);
      expect(find.text('Измерение за этот день'), findsOneWidget);

      expect(tester.takeException(), isNull);
      await tester.runAsync(() => db.close());
    });

    testWidgets('Active workout in progress displays "Продолжить" hero button', (tester) async {
      tester.view.physicalSize = const Size(360, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      late Database db;
      final date = DateTime(2026, 11, 4);

      await tester.runAsync(() async {
        db = await openLiftlineDb(inMemoryDatabasePath, factory: databaseFactoryFfi);
        AppDb.instance.useDatabase(db);

        final wrepo = WorkoutRepo(db);
        await wrepo.createWorkout(
          title: 'Активная тренировка спины',
          date: date,
          start: true,
        );
      });

      await tester.pumpWidget(
        createTestWidget(
          child: TodayScreen(
            selectedDate: date,
            isFollowingToday: true,
            onDateChanged: (_) {},
            onGoToTab: (_) {},
          ),
        ),
      );

      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 250)));
      await tester.pumpAndSettle();

      expect(find.text('СЕССИЯ В ПРОЦЕССЕ'), findsOneWidget);
      expect(find.text('Активная тренировка спины'), findsOneWidget);
      expect(find.text('Продолжить'), findsOneWidget);

      expect(tester.takeException(), isNull);
      await tester.runAsync(() => db.close());
    });

    testWidgets('Kinetic calendar day tap fires onDateChanged callback', (tester) async {
      tester.view.physicalSize = const Size(360, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      late Database db;
      final date = DateTime(2026, 11, 4); // Wednesday
      DateTime? changedDate;

      await tester.runAsync(() async {
        db = await openLiftlineDb(inMemoryDatabasePath, factory: databaseFactoryFfi);
        AppDb.instance.useDatabase(db);
      });

      await tester.pumpWidget(
        createTestWidget(
          child: TodayScreen(
            selectedDate: date,
            isFollowingToday: true,
            onDateChanged: (d) => changedDate = d,
            onGoToTab: (_) {},
          ),
        ),
      );

      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();

      // Tap Monday pill (day 2 of November 2026)
      await tester.tap(find.text('ПН'));
      expect(changedDate, isNotNull);
      expect(changedDate!.day, 2);

      await tester.runAsync(() => db.close());
    });

    testWidgets('Verify layout on 320, 360, 412 px and 1.0x, 2.0x font scaling without overflow', (tester) async {
      final widths = [320.0, 360.0, 412.0];
      final scales = [1.0, 2.0];

      for (final w in widths) {
        for (final s in scales) {
          tester.view.physicalSize = Size(w, 1400);
          tester.view.devicePixelRatio = 1.0;
          tester.platformDispatcher.textScaleFactorTestValue = s;
          addTearDown(() {
            tester.view.reset();
            tester.platformDispatcher.clearTextScaleFactorTestValue();
          });

          late Database db;
          final date = DateTime(2026, 11, 4);

          await tester.runAsync(() async {
            db = await openLiftlineDb(inMemoryDatabasePath, factory: databaseFactoryFfi);
            AppDb.instance.useDatabase(db);

            final wrepo = WorkoutRepo(db);
            await wrepo.createWorkout(
              title: 'Длинное название тренировки груди и плеч на узком экране',
              date: date,
              start: false,
            );
            final nrepo = NutritionRepo(db);
            await nrepo.setGoals(date, const NutritionGoals(2550, 180, 80, 320));
            await nrepo.savePortion(
              date: dateKey(date),
              meal: 'breakfast',
              name: 'Овсяная каша со свежими ягодами и протеиновым коктейлем',
              total: const Nutrients(550, 40, 12, 70),
            );
            final prepo = ProgressRepo(db);
            await prepo.saveWeight(date, 79.8);
          });

          await tester.pumpWidget(
            createTestWidget(
              width: w,
              textScale: s,
              child: TodayScreen(
                selectedDate: date,
                isFollowingToday: false,
                onDateChanged: (_) {},
                onGoToTab: (_) {},
              ),
            ),
          );

          await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
          await tester.pumpAndSettle();

          expect(find.text('Liftspire'), findsOneWidget);
          expect(find.text('Питание'), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.runAsync(() => db.close());
        }
      }
    });
  });
}
