import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:liftline_app/db.dart';
import 'package:liftline_app/nutrition_calc.dart';
import 'package:liftline_app/nutrition_repo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  group('calc', () {
    test('per-100 scaling: 200/10/8/22 x 150 g', () {
      final t = const Nutrients(200, 10, 8, 22).scaled(150);
      expect((t.kcal, t.protein, t.fat, t.carbs), (300, 15, 12, 33));
    });
    test('decimal comma and dot, 0,5 is not 5', () {
      expect(parseDecimal('0,5'), 0.5);
      expect(parseDecimal('0.5'), 0.5);
      expect(parseDecimal(''), isNull);
      expect(parseDecimal('-1'), isNull);
      expect(parseDecimal('abc'), isNull);
      expect(parseDecimal('Infinity'), isNull);
      expect(parseDecimal('0'), 0); // explicit zero is valid
    });
    test('balance never shows negative remaining', () {
      expect(calorieBalance(1800, 2000).remaining, 200);
      final b = calorieBalance(2300, 2000);
      expect((b.remaining, b.over), (0, 300));
    });
  });

  group('repo (real SQLite)', () {
    late NutritionRepo repo;
    setUp(() async {
      final db = await openLiftlineDb(inMemoryDatabasePath, factory: databaseFactoryFfi);
      repo = NutritionRepo(db);
    });
    tearDown(() => repo.db.close());

    test('quick portion saved as entered (no /100, no 4/9/4)', () async {
      final id = await repo.savePortion(
          date: '2026-05-10', meal: 'lunch', name: 'Этикетка',
          total: const Nutrients(500, 30, 20, 40));
      final e = (await repo.entry(id))!;
      expect(e['calories'], 500);
      expect((e['protein'], e['fat'], e['carbs']), (30, 20, 40));
      expect(e['grams'], isNull);
      expect((await repo.dayTotals('2026-05-10')).kcal, 500);
    });

    test('catalogue change does not rewrite diary; edit uses entry snapshot',
        () async {
      final fid = await repo.upsertFood('Рис', const Nutrients(200, 10, 8, 22));
      final id = await repo.saveProduct(
          date: '2026-05-10', meal: 'dinner', name: 'Рис', grams: 150,
          per100: const Nutrients(200, 10, 8, 22), foodId: fid);
      expect((await repo.entry(id))!['calories'], 300);
      await repo.upsertFood('Рис', const Nutrients(300, 10, 8, 22));
      expect((await repo.entry(id))!['calories'], 300); // unchanged
      // edit mass using snapshot values of the entry itself
      final e = (await repo.entry(id))!;
      await repo.saveProduct(
          id: id, date: '2026-05-10', meal: 'dinner', name: 'Рис', grams: 200,
          per100: Nutrients((e['per100_kcal'] as num).toDouble(), 10, 8, 22));
      expect((await repo.entry(id))!['calories'], 400); // not 600
      // changing only date/meal keeps nutrients
      await repo.saveProduct(
          id: id, date: '2026-05-11', meal: 'lunch', name: 'Рис', grams: 200,
          per100: const Nutrients(200, 10, 8, 22));
      expect((await repo.entry(id))!['calories'], 400);
      expect((await repo.day('2026-05-10')), isEmpty);
      expect((await repo.day('2026-05-11')).length, 1);
      // archived food does not delete history
      await repo.archiveFood(fid);
      expect((await repo.day('2026-05-11')).length, 1);
    });

    test('repeat creates independent copy; original unchanged', () async {
      final id = await repo.saveProduct(
          date: '2026-05-10', meal: 'snack', name: 'Банан', grams: 100,
          per100: const Nutrients(90, 1, 0.3, 22));
      final n = await repo.repeat(id, date: '2026-05-12', grams: 150);
      expect(n, isNot(id));
      expect((await repo.entry(n))!['calories'], closeTo(135, 1e-9));
      expect((await repo.entry(id))!['calories'], 90);
      final p = await repo.savePortion(
          date: '2026-05-10', meal: 'snack', name: 'Бар',
          total: const Nutrients(200, 5, 5, 30));
      final pn = await repo.repeat(p, date: '2026-05-12');
      expect((await repo.entry(pn))!['calories'], 200);
      expect((await repo.entry(pn))!['mode'], 'portion');
    });

    test('zero grams rejected; explicit zero nutrients allowed', () async {
      await expectLater(
          repo.saveProduct(date: 'd', meal: 'snack', name: 'x', grams: 0,
              per100: Nutrients.zero),
          throwsArgumentError);
      final id = await repo.saveProduct(
          date: '2026-05-10', meal: 'snack', name: 'Вода', grams: 250,
          per100: Nutrients.zero);
      expect((await repo.entry(id))!['calories'], 0);
    });

    test('goals are dated: past days keep older goals; null != 0', () async {
      expect((await repo.goalsFor('2026-05-10')).any, isFalse);
      await repo.setGoals(DateTime(2026, 5, 1),
          const NutritionGoals(2000, 150, null, null));
      await repo.setGoals(DateTime(2026, 5, 10),
          const NutritionGoals(2500, null, null, null));
      expect((await repo.goalsFor('2026-05-09')).calories, 2000);
      expect((await repo.goalsFor('2026-05-10')).calories, 2500);
      expect((await repo.goalsFor('2026-05-10')).protein, isNull);
      expect((await repo.goalsFor('2026-04-30')).any, isFalse);
    });
  });

  test('v2 -> v3 keeps old nutrition rows as portion entries; chain v1->v3',
      () async {
    final dir = await tmpDir();
    final path = '$dir/l.db';
    final f = databaseFactoryFfi;
    final v1 = await f.openDatabase(path,
        options: OpenDatabaseOptions(
            version: 1, onCreate: (db, v) => createV1Schema(db)));
    await v1.insert('nutrition_entries', {'id': 'n1', 'date': '2025-01-10', 'name': 'Овсянка', 'portion': '150г', 'calories': 300, 'protein': 10, 'fat': 5, 'carbs': 50});
    await v1.insert('user_goals', {'id': 'g1', 'calories': 2200, 'protein': 0, 'fat': null, 'carbs': 250});
    await v1.close();
    final db = await openLiftlineDb(path, factory: f);
    expect(await db.getVersion(), kDbVersion);
    final e = (await db.query('nutrition_entries')).single;
    expect(e['id'], 'n1');
    expect(e['mode'], 'portion');
    expect(e['calories'], 300);
    expect(e['per100_kcal'], isNull); // not guessed
    expect(e['portion'], '150г');
    final g = await NutritionRepo(db).goalsFor('2025-01-10');
    expect((g.calories, g.protein, g.fat, g.carbs), (2200, null, null, 250));
    await db.close();
  });
}

Future<String> tmpDir() async =>
    (await Directory.systemTemp.createTemp('ll_n')).path;
