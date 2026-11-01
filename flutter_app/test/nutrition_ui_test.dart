import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:liftline_app/db.dart';
import 'package:liftline_app/nutrition_calc.dart';
import 'package:liftline_app/nutrition_repo.dart';
import 'package:liftline_app/nutrition_ui.dart';
import 'package:liftline_app/theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late NutritionRepo repo;
  final date = DateTime(2026, 5, 10);

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 250)));
    await t.pump();
  }

  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(800, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await initializeDateFormatting('ru');
    await t.runAsync(() async {
      final db = await openLiftlineDb(inMemoryDatabasePath, factory: databaseFactoryFfi);
      AppDb.instance.useDatabase(db);
      repo = NutritionRepo(db);
    });
    await t.pumpWidget(MaterialApp(
        theme: buildLiftlineTheme(),
        home: EntryFormScreen(date: date)));
    await settle(t);
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  testWidgets('product mode: live preview and save 150 g -> 300 kcal',
      (t) async {
    await open(t);
    await t.enterText(field('Название *'), 'Рис');
    await t.enterText(field('Съеденная масса, г *'), '150');
    await t.enterText(field('Калории, ккал (на 100 г)'), '200');
    await t.enterText(field('Белки, г (на 100 г)'), '10');
    await t.enterText(field('Жиры, г (на 100 г)'), '8');
    await t.enterText(field('Углеводы, г (на 100 г)'), '22,5'); // comma
    await t.pump();
    expect(find.textContaining('Итого: 300 ккал'), findsOneWidget);
    await t.tap(find.text('Добавить').last);
    await settle(t);
    final rows = await t.runAsync(() => repo.day('2026-05-10'));
    expect(rows!.length, 1);
    expect(rows.single['calories'], 300);
    expect(rows.single['carbs'], closeTo(33.75, 1e-9));
    expect(rows.single['mode'], 'product');
    await t.runAsync(() => AppDb.instance.db.close());
  });

  testWidgets('portion mode saves values as entered, no mass needed',
      (t) async {
    await open(t);
    await t.tap(find.text('Быстрая порция'));
    await t.pump();
    expect(find.text('Съеденная масса, г *'), findsNothing);
    await t.enterText(field('Название *'), 'Этикетка');
    await t.enterText(field('Калории, ккал (за порцию)'), '500');
    await t.enterText(field('Белки, г (за порцию)'), '30');
    await t.enterText(field('Жиры, г (за порцию)'), '20');
    await t.enterText(field('Углеводы, г (за порцию)'), '40');
    await t.tap(find.text('Добавить').last);
    await settle(t);
    final e = (await t.runAsync(() => repo.day('2026-05-10')))!.single;
    expect((e['calories'], e['protein'], e['fat'], e['carbs']), (500, 30, 20, 40));
    expect(e['grams'], isNull);
    await t.runAsync(() => AppDb.instance.db.close());
  });

  testWidgets('invalid values are rejected and nothing is saved', (t) async {
    await open(t);
    await t.enterText(field('Название *'), 'X');
    await t.enterText(field('Съеденная масса, г *'), '0');
    await t.enterText(field('Белки, г (на 100 г)'), '-5');
    await t.tap(find.text('Добавить').last);
    await settle(t);
    expect(find.text('Масса должна быть больше 0'), findsOneWidget);
    expect(find.textContaining('Калории'), findsWidgets);
    expect(find.textContaining('обязательно (введите 0'), findsWidgets);
    final rows = await t.runAsync(() => repo.day('2026-05-10'));
    expect(rows, isEmpty);
    await t.runAsync(() => AppDb.instance.db.close());
  });

  testWidgets('double tap on save creates a single entry', (t) async {
    await open(t);
    await t.enterText(field('Название *'), 'Яблоко');
    await t.enterText(field('Съеденная масса, г *'), '100');
    for (final l in ['Калории, ккал', 'Белки, г', 'Жиры, г', 'Углеводы, г']) {
      await t.enterText(field('$l (на 100 г)'), '1');
    }
    final btn = find.widgetWithText(FilledButton, 'Добавить');
    await t.tap(btn);
    await t.tap(btn, warnIfMissed: false);
    await settle(t);
    final rows = await t.runAsync(() => repo.day('2026-05-10'));
    expect(rows!.length, 1);
    await t.runAsync(() => AppDb.instance.db.close());
  });

  testWidgets('summary: over goal is stated calmly, not negative remaining',
      (t) async {
    await t.pumpWidget(MaterialApp(
      theme: buildLiftlineTheme(),
      home: Scaffold(
        body: NutritionSummaryCard(
          totals: const Nutrients(2300, 100, 50, 200),
          goals: const NutritionGoals(2000, null, null, null),
          hasEntries: true,
          onSetGoals: () {},
        ),
      ),
    ));
    expect(find.text('На 300 ккал выше цели'), findsOneWidget);
    expect(find.textContaining('Осталось'), findsNothing);
  });

  testWidgets('no goals: facts only and "Задать цель"', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: buildLiftlineTheme(),
      home: Scaffold(
        body: NutritionSummaryCard(
          totals: const Nutrients(500, 30, 20, 40),
          goals: const NutritionGoals(null, null, null, null),
          hasEntries: true,
          onSetGoals: () {},
        ),
      ),
    ));
    expect(find.text('500 ккал съедено'), findsOneWidget);
    expect(find.text('Задать цель'), findsOneWidget);
  });
}
