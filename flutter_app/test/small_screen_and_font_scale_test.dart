import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:liftline_app/db.dart';
import 'package:liftline_app/nutrition_ui.dart';
import 'package:liftline_app/progress_ui.dart';
import 'package:liftline_app/theme.dart';
import 'package:liftline_app/today_screen.dart';
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

  testWidgets('Small screen (320px) and enlarged font scale (1.5x) on TodayScreen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    late Database db;
    await tester.runAsync(() async {
      db = await openLiftlineDb(inMemoryDatabasePath, factory: databaseFactoryFfi);
      AppDb.instance.useDatabase(db);
    });

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 600),
          textScaler: TextScaler.linear(1.5),
        ),
        child: MaterialApp(
          theme: buildLiftlineTheme(),
          home: TodayScreen(
            selectedDate: DateTime(2026, 6, 15),
            isFollowingToday: true,
            onDateChanged: (_) {},
            onGoToTab: (_) {},
          ),
        ),
      ),
    );

    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    expect(find.text('Сегодня'), findsWidgets);
    expect(find.text('Питание'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Тренировки дня'), 200);
    expect(find.text('Тренировки дня'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });

  testWidgets('Small screen (320px) and enlarged font scale (1.5x) on WorkoutsScreen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    late Database db;
    await tester.runAsync(() async {
      db = await openLiftlineDb(inMemoryDatabasePath, factory: databaseFactoryFfi);
      AppDb.instance.useDatabase(db);
    });

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 600),
          textScaler: TextScaler.linear(1.5),
        ),
        child: MaterialApp(
          theme: buildLiftlineTheme(),
          home: WorkoutsScreen(selectedDate: DateTime(2026, 6, 15)),
        ),
      ),
    );

    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    expect(find.text('Тренировки'), findsOneWidget);
    expect(find.text('Тренировок пока нет'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });

  testWidgets('Small screen (320px) and enlarged font scale (1.5x) on NutritionScreen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    late Database db;
    await tester.runAsync(() async {
      db = await openLiftlineDb(inMemoryDatabasePath, factory: databaseFactoryFfi);
      AppDb.instance.useDatabase(db);
    });

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 600),
          textScaler: TextScaler.linear(1.5),
        ),
        child: MaterialApp(
          theme: buildLiftlineTheme(),
          home: NutritionScreen(
            selectedDate: DateTime(2026, 6, 15),
            onDateChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    expect(find.text('Питание'), findsOneWidget);
    expect(find.text('Завтрак'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });

  testWidgets('Small screen (320px) and enlarged font scale (1.5x) on ProgressScreen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    late Database db;
    await tester.runAsync(() async {
      db = await openLiftlineDb(inMemoryDatabasePath, factory: databaseFactoryFfi);
      AppDb.instance.useDatabase(db);
    });

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 600),
          textScaler: TextScaler.linear(1.5),
        ),
        child: MaterialApp(
          theme: buildLiftlineTheme(),
          home: ProgressScreen(selectedDate: DateTime(2026, 6, 15)),
        ),
      ),
    );

    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    expect(find.text('Прогресс'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });
}
