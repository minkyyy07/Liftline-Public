import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:liftline_app/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ll_mig');
    path = '${dir.path}/liftline.db';
  });
  tearDown(() async => dir.delete(recursive: true));

  Future<void> seedV1() async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, v) => createV1Schema(db),
      ),
    );
    await db.insert('workouts', {
      'id': 'w1',
      'date': '2025-01-10',
      'title': 'Грудь',
      'duration_minutes': 55,
      'notes': 'n',
    });
    await db.insert('workouts', {
      'id': 'w2',
      'date': '2025-01-12',
      'title': 'Грудь 2',
      'duration_minutes': 40,
    });
    await db.insert('workout_exercises', {
      'id': 'e1',
      'workout_id': 'w1',
      'exercise_name': 'Жим лежа',
      'sort_order': 1,
    });
    await db.insert('workout_exercises', {
      'id': 'e2',
      'workout_id': 'w2',
      'exercise_name': ' Жим лежа ',
      'sort_order': 1,
    });
    await db.insert('workout_exercises', {
      'id': 'e3',
      'workout_id': 'w2',
      'exercise_name': 'Жим лёжа',
      'sort_order': 2,
    });
    await db.insert('set_entries', {
      'id': 's1',
      'exercise_id': 'e1',
      'set_number': 1,
      'weight_kg': 100.5,
      'reps': 5,
      'completed': 1,
    });
    await db.insert('set_entries', {
      'id': 's2',
      'exercise_id': 'e1',
      'set_number': 2,
      'weight_kg': 100,
      'reps': 4,
      'completed': 0,
    });
    await db.insert('nutrition_entries', {
      'id': 'n1',
      'date': '2025-01-10',
      'name': 'Овсянка',
      'calories': 300,
      'protein': 10,
      'fat': 5,
      'carbs': 50,
    });
    await db.close();
  }

  test('v1 -> v2 keeps ids/values, creates backup, no fuzzy merge', () async {
    await seedV1();
    final db = await openLiftlineDb(path, factory: factory);
    expect(await db.getVersion(), kDbVersion);

    final w = await db.query('workouts', orderBy: 'id');
    expect(w.map((r) => r['id']), ['w1', 'w2']);
    expect(w.first['duration_minutes'], 55);
    expect(w.every((r) => r['status'] == 'finished'), isTrue);

    final s = await db.query('set_entries', orderBy: 'id');
    expect(s[0]['weight_kg'], 100.5);
    expect(s[0]['completed'], 1);
    expect(s[1]['completed'], 0); // not forced to completed
    expect(s.every((r) => r['rir'] == null), isTrue); // NULL, not 0
    expect(s.every((r) => r['set_type'] == 'work'), isTrue);

    // 'Жим лежа' (trim-equal) shares one catalogue id; 'Жим лёжа' differs.
    final ex = await db.query('exercises');
    expect(ex.length, 2);
    final we = {
      for (final r in await db.query('workout_exercises')) r['id']: r,
    };
    expect(we['e1']!['exercise_ref_id'], we['e2']!['exercise_ref_id']);
    expect(we['e1']!['exercise_ref_id'], isNot(we['e3']!['exercise_ref_id']));
    expect(we['e2']!['exercise_name'], ' Жим лежа '); // original kept

    expect((await db.query('nutrition_entries')).single['calories'], 300);
    await db.close();

    expect(await factory.databaseExists('$path.v1.bak'), isTrue);
    final bak = await factory.openDatabase(
      '$path.v1.bak',
      options: OpenDatabaseOptions(readOnly: true),
    );
    expect((await bak.query('set_entries')).length, 2);
    expect((await bak.rawQuery('PRAGMA user_version')).first.values.first, 1);
    await bak.close();
  });

  test('reopen keeps data; fresh install works', () async {
    await seedV1();
    var db = await openLiftlineDb(path, factory: factory);
    await db.close();
    db = await openLiftlineDb(path, factory: factory);
    expect((await db.query('set_entries')).length, 2);
    await db.close();

    final fresh = await openLiftlineDb(
      '${dir.path}/fresh.db',
      factory: factory,
    );
    expect(await fresh.getVersion(), kDbVersion);
    final tables = await fresh.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    final tableNames = tables.map((t) => t['name']).toSet();
    expect(tableNames.contains('workout_conflict_drafts'), isTrue);
    await fresh.close();
  });

  test('failed migration rolls back and keeps original data', () async {
    await seedV1();
    final db0 = await factory.openDatabase(path);
    await db0.execute('CREATE TABLE exercises (x INTEGER)'); // force conflict
    await db0.close();
    await expectLater(
      openLiftlineDb(path, factory: factory),
      throwsA(anything),
    );
    final db = await factory.openDatabase(path);
    expect((await db.rawQuery('PRAGMA user_version')).first.values.first, 1);
    expect((await db.query('set_entries')).length, 2);
    final cols = await db.rawQuery('PRAGMA table_info(set_entries)');
    expect(cols.any((c) => c['name'] == 'rir'), isFalse); // rolled back
    await db.close();
  });
}
