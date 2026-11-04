import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'data_events.dart';
import 'nutrition_calc.dart';
import 'repo.dart' show Rec;
import 'week_utils.dart';

const kMeals = ['breakfast', 'lunch', 'dinner', 'snack'];
const kMealLabels = {
  'breakfast': 'Завтрак',
  'lunch': 'Обед',
  'dinner': 'Ужин',
  'snack': 'Перекус',
  'other': 'Без приёма пищи',
};

class NutritionGoals {
  final double? calories, protein, fat, carbs;
  const NutritionGoals(this.calories, this.protein, this.fat, this.carbs);
  bool get any =>
      calories != null || protein != null || fat != null || carbs != null;
}

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;

Nutrients entryTotals(Rec e) => Nutrients(
  _d(e['calories']),
  _d(e['protein']),
  _d(e['fat']),
  _d(e['carbs']),
);

class NutritionRepo {
  final Database db;
  NutritionRepo(this.db);
  final _uuid = const Uuid();

  Future<List<Rec>> day(String date) => db.query(
    'nutrition_entries',
    where: 'date = ?',
    whereArgs: [date],
    orderBy: 'rowid',
  );

  Future<Nutrients> dayTotals(String date) async =>
      sumNutrients((await day(date)).map(entryTotals));

  Future<Rec?> entry(String id) async {
    final r = await db.query(
      'nutrition_entries',
      where: 'id = ?',
      whereArgs: [id],
    );
    return r.isEmpty ? null : r.first;
  }

  // ---------- 12.1 product x mass ----------
  Map<String, Object?> _productRow({
    required String id,
    required String date,
    required String meal,
    required String name,
    required double grams,
    required Nutrients per100,
    String? foodId,
  }) {
    final t = per100.scaled(grams);
    return {
      'id': id,
      'date': date,
      'name': name.trim(),
      'mode': 'product',
      'meal': meal,
      'grams': grams,
      'per100_kcal': per100.kcal,
      'per100_protein': per100.protein,
      'per100_fat': per100.fat,
      'per100_carbs': per100.carbs,
      'food_id': foodId,
      'calories': t.kcal,
      'protein': t.protein,
      'fat': t.fat,
      'carbs': t.carbs,
    };
  }

  /// Insert (id == null) or update an entry in product mode. Totals come from
  /// the values on the entry itself, never from the current catalogue.
  Future<String> saveProduct({
    String? id,
    required String date,
    required String meal,
    required String name,
    required double grams,
    required Nutrients per100,
    String? foodId,
  }) async {
    if (grams <= 0) throw ArgumentError('grams must be > 0');
    final rid = id ?? _uuid.v4();
    final row = _productRow(
      id: rid,
      date: date,
      meal: meal,
      name: name,
      grams: grams,
      per100: per100,
      foodId: foodId,
    );
    if (id == null) {
      await db.insert('nutrition_entries', row);
    } else {
      await db.update(
        'nutrition_entries',
        {...row}..remove('id'),
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    AppDataEvents.instance.notifyNutritionChanged();
    return rid;
  }

  // ---------- 12.2 quick portion ----------
  Future<String> savePortion({
    String? id,
    required String date,
    required String meal,
    required String name,
    required Nutrients total,
  }) async {
    final nid = id ?? _uuid.v4();
    final row = {
      'date': date,
      'name': name.trim(),
      'mode': 'portion',
      'meal': meal,
      'grams': null,
      'per100_kcal': null,
      'per100_protein': null,
      'per100_fat': null,
      'per100_carbs': null,
      'food_id': null,
      'calories': total.kcal,
      'protein': total.protein,
      'fat': total.fat,
      'carbs': total.carbs,
    };
    if (id == null) {
      await db.insert('nutrition_entries', {'id': nid, ...row});
    } else {
      await db.update(
        'nutrition_entries',
        row,
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    AppDataEvents.instance.notifyNutritionChanged();
    return nid;
  }

  /// Independent copy (new id) of the entry's snapshot to another day.
  Future<String> repeat(
    String id, {
    required String date,
    String? meal,
    double? grams,
  }) async {
    final e = await entry(id);
    if (e == null) throw StateError('entry not found');
    final m = meal ?? (e['meal'] as String?) ?? 'snack';
    if (e['mode'] == 'product') {
      return saveProduct(
        date: date,
        meal: m,
        name: e['name'] as String,
        grams: grams ?? _d(e['grams']),
        per100: Nutrients(
          _d(e['per100_kcal']),
          _d(e['per100_protein']),
          _d(e['per100_fat']),
          _d(e['per100_carbs']),
        ),
        foodId: e['food_id'] as String?,
      );
    }
    final nid = _uuid.v4();
    await db.insert('nutrition_entries', {
      ...e,
      'id': nid,
      'date': date,
      'meal': m,
    });
    AppDataEvents.instance.notifyNutritionChanged();
    return nid;
  }

  Future<void> delete(String id) async {
    await db.delete('nutrition_entries', where: 'id = ?', whereArgs: [id]);
    AppDataEvents.instance.notifyNutritionChanged();
  }

  // ---------- catalogue ----------
  Future<List<Rec>> recentFoods({int limit = 12}) => db.query(
    'foods',
    where: 'archived = 0',
    orderBy: 'rowid DESC',
    limit: limit,
  );

  /// Create or update the catalogue product with this exact name. Does not
  /// touch existing diary entries.
  Future<String> upsertFood(String name, Nutrients per100) async {
    final n = name.trim();
    final found = await db.query(
      'foods',
      where: 'name = ?',
      whereArgs: [n],
      limit: 1,
    );
    final vals = {
      'name': n,
      'kcal100': per100.kcal,
      'protein100': per100.protein,
      'fat100': per100.fat,
      'carbs100': per100.carbs,
      'archived': 0,
    };
    if (found.isNotEmpty) {
      final id = found.first['id'] as String;
      await db.update('foods', vals, where: 'id = ?', whereArgs: [id]);
      return id;
    }
    final id = _uuid.v4();
    await db.insert('foods', {'id': id, ...vals});
    return id;
  }

  /// Hide from catalogue; diary history keeps its own snapshots.
  Future<void> archiveFood(String id) =>
      db.update('foods', {'archived': 1}, where: 'id = ?', whereArgs: [id]);

  // ---------- goals ----------
  /// Goals in force on [date]: latest row with effective_from <= date.
  Future<NutritionGoals> goalsFor(String date) async {
    final r = await db.query(
      'nutrition_goals',
      where: 'effective_from <= ?',
      whereArgs: [date],
      orderBy: 'effective_from DESC, rowid DESC',
      limit: 1,
    );
    if (r.isEmpty) return const NutritionGoals(null, null, null, null);
    final g = r.first;
    double? p(Object? v) =>
        (v as num?) == null || (v as num) <= 0 ? null : v.toDouble();
    return NutritionGoals(
      p(g['calories']),
      p(g['protein']),
      p(g['fat']),
      p(g['carbs']),
    );
  }

  /// New goals from [from] onwards; earlier days keep their goals.
  Future<void> setGoals(DateTime from, NutritionGoals g) async {
    final key = dateKey(from);
    await db.transaction((t) async {
      await t.delete(
        'nutrition_goals',
        where: 'effective_from = ?',
        whereArgs: [key],
      );
      await t.insert('nutrition_goals', {
        'id': _uuid.v4(),
        'effective_from': key,
        'calories': g.calories,
        'protein': g.protein,
        'fat': g.fat,
        'carbs': g.carbs,
      });
    });
    AppDataEvents.instance.notifyNutritionChanged();
  }
}
