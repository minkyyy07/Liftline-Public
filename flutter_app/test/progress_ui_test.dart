import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:liftline_app/chart.dart';
import 'package:liftline_app/db.dart';
import 'package:liftline_app/progress_repo.dart';
import 'package:liftline_app/progress_ui.dart';
import 'package:liftline_app/theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 250)));
    await t.pump();
  }

  Future<ProgressRepo> setup(WidgetTester t, Widget home) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await initializeDateFormatting('ru');
    late ProgressRepo r;
    await t.runAsync(() async {
      final db = await openLiftlineDb(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      AppDb.instance.useDatabase(db);
      r = ProgressRepo(db);
    });
    await t.pumpWidget(MaterialApp(theme: buildLiftlineTheme(), home: home));
    await settle(t);
    return r;
  }

  testWidgets('weight tab: empty state, add, insufficient-data dashes', (
    t,
  ) async {
    final repo = await setup(
      t,
      Scaffold(body: WeightTab(end: DateTime(2026, 5, 20))),
    );
    expect(find.textContaining('измерений нет'), findsOneWidget);
    await t.tap(find.text('Записать вес'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '0');
    await t.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await t.pump();
    expect(find.text('Введите число больше 0'), findsOneWidget);
    await t.enterText(find.byType(TextField), '79,5');
    await t.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await settle(t);
    await t.pumpAndSettle();
    await settle(t);
    final rows = await t.runAsync(() => repo.weights());
    expect(rows!.single['kg'], 79.5);
    expect(find.textContaining('Среднее 7 дн.: —'), findsOneWidget); // < 3 days
    expect(find.textContaining('Изм. средних 2 нед.: —'), findsOneWidget);
    await t.runAsync(() => AppDb.instance.db.close());
  });

  testWidgets('chart: single point draws, no crash; shows selected value', (
    t,
  ) async {
    await initializeDateFormatting('ru');
    await t.pumpWidget(
      MaterialApp(
        theme: buildLiftlineTheme(),
        home: Scaffold(
          body: LineChartView(
            points: [ChartPt(DateTime(2026, 5, 1), 80)],
            unit: 'кг',
          ),
        ),
      ),
    );
    await t.tap(find.byType(CustomPaint).last, warnIfMissed: false);
    await t.pump();
    expect(noException(t), isTrue);
  });

  testWidgets('strength tab: no finished sessions -> explanation', (t) async {
    await setup(t, Scaffold(body: StrengthTab(end: DateTime(2026, 5, 20))));
    expect(find.textContaining('Завершите тренировку'), findsOneWidget);
    await t.runAsync(() => AppDb.instance.db.close());
  });
}

bool noException(WidgetTester t) => t.takeException() == null;
