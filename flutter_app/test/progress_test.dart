import 'package:flutter_test/flutter_test.dart';
import 'package:liftline_app/calc.dart';
import 'package:liftline_app/db.dart';
import 'package:liftline_app/progress_calc.dart';
import 'package:liftline_app/progress_repo.dart';
import 'package:liftline_app/repo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

WeightPoint w(int day, double kg) => WeightPoint(DateTime(2026, 5, day), kg);

void main() {
  sqfliteFfiInit();

  group('weight averages', () {
    final d = DateTime(2026, 5, 20);
    test('reference example: -0.5 kg', () {
      final pts = [
        w(14, 79.5), w(16, 79.3), w(20, 79.7), // [D-6, D]
        w(7, 80.0), w(9, 79.8), w(13, 80.2), // [D-13, D-7]
      ];
      expect(movingAverage(pts, d)!.avg, closeTo(79.5, 1e-9));
      expect(movingAverage(pts, d)!.n, 3);
      final c = twoWeekChange(pts, d)!;
      expect(c.delta, closeTo(-0.5, 1e-9));
      expect((c.nNow, c.nPrev), (3, 3));
    });
    test('two measurements in a window -> no value', () {
      final pts = [w(14, 79.5), w(20, 79.7), w(7, 80), w(9, 80), w(13, 80)];
      expect(movingAverage(pts, d), isNull);
      expect(twoWeekChange(pts, d), isNull);
      final pts2 = [w(14, 79.5), w(16, 79), w(20, 79.7), w(7, 80), w(9, 80)];
      expect(twoWeekChange(pts2, d), isNull); // previous window has 2
    });
    test('future measurements are not used', () {
      final pts = [w(14, 79), w(16, 79), w(18, 79), w(25, 100)];
      expect(movingAverage(pts, d)!.avg, 79);
    });
  });

  group('periods', () {
    test('window ends on D and includes it', () {
      final end = DateTime(2026, 5, 20);
      expect(periodStart('1Н', end), DateTime(2026, 5, 14));
      expect(periodStart('1М', end), DateTime(2026, 4, 21));
      expect(periodStart('Всё', end), isNull);
      expect(inWindow(DateTime(2026, 5, 14), periodStart('1Н', end), end), isTrue);
      expect(inWindow(DateTime(2026, 5, 13), periodStart('1Н', end), end), isFalse);
      expect(inWindow(DateTime(2026, 5, 21), periodStart('1Н', end), end), isFalse);
    });
  });

  group('strength math', () {
    test('change percent needs 2 values and first > 0', () {
      expect(changePercent([100]), isNull);
      expect(changePercent([0, 5]), isNull);
      expect(changePercent([100, 110]), closeTo(10, 1e-9));
    });
    test('session point ignores warm-up/uncompleted; bodyweight has no e1RM',
        () {
      final p = sessionPoint(DateTime(2026, 5, 1), 's', const [
        SetData(100, 5),
        SetData(120, 5, warmup: true),
        SetData(130, 5, completed: false),
      ])!;
      expect(p.volume, 500);
      expect(p.bestWeight, 100);
      expect(p.e1rm, closeTo(116.67, 0.01));
      final bw = sessionPoint(DateTime(2026, 5, 1), 's', const [SetData(0, 12)])!;
      expect(bw.e1rm, isNull);
      expect(bw.bestWeight, isNull);
      expect(bw.volume, 0);
      expect(sessionPoint(DateTime(2026, 5, 1), 's', const [SetData(50, 5, warmup: true)]), isNull);
    });
    test('average over entry days is not diluted by empty days', () {
      final a = averageOverEntryDays([2000, null, 1000, null, null, null, null])!;
      expect((a.avg, a.days), (1500, 2));
      expect(averageOverEntryDays([null, null]), isNull);
    });
  });

  group('repo (real SQLite)', () {
    late ProgressRepo repo;
    late WorkoutRepo wr;
    var clock = DateTime(2026, 5, 10, 10);
    setUp(() async {
      final db = await openLiftlineDb(inMemoryDatabasePath, factory: databaseFactoryFfi);
      repo = ProgressRepo(db);
      wr = WorkoutRepo(db, now: () => clock);
    });
    tearDown(() => repo.db.close());

    test('one primary weight per day; duplicate asks, never silently replaces',
        () async {
      final id = await repo.saveWeight(DateTime(2026, 5, 1), 80);
      await expectLater(repo.saveWeight(DateTime(2026, 5, 1), 81),
          throwsA(isA<WeightExists>()));
      expect((await repo.weights()).single['kg'], 80);
      await repo.saveWeight(DateTime(2026, 5, 1), 81, replaceExisting: true);
      expect((await repo.weights()).single['kg'], 81);
      await expectLater(repo.saveWeight(DateTime(2026, 5, 2), 0), throwsArgumentError);
      await repo.deleteWeight(id);
      expect(await repo.weights(), isEmpty);
    });

    test('latestUpTo never returns a later measurement', () async {
      await repo.saveWeight(DateTime(2026, 5, 1), 80);
      await repo.saveWeight(DateTime(2026, 5, 10), 79);
      expect((await repo.latestUpTo('2026-05-05'))!['date'], '2026-05-01');
      expect(await repo.latestUpTo('2026-04-01'), isNull);
    });

    test('legacy duplicate rows of a day are kept; only primary is used',
        () async {
      await repo.db.insert('body_weights', {'id': 'a', 'date': '2026-05-01', 'kg': 80.0, 'is_primary': 1});
      await repo.db.insert('body_weights', {'id': 'b', 'date': '2026-05-01', 'kg': 82.0, 'is_primary': 0});
      expect((await repo.weights()).single['id'], 'a');
      expect((await repo.db.query('body_weights')).length, 2);
    });

    test('strength: only finished sessions; active/warm-up excluded; sorted',
        () async {
      Future<void> session(DateTime d, double kg, int reps,
          {bool finish = true, bool warm = false}) async {
        clock = d;
        final id = await wr.createWorkout(title: 't', date: d, start: true);
        final e = await wr.addExercise(id, 'Жим');
        final s = await wr.addSet(e, warmup: warm);
        await wr.updateSet(s, weight: kg, reps: reps);
        await wr.setCompleted(s, true);
        if (finish) await wr.finishWorkout(id);
      }
      await session(DateTime(2026, 5, 3, 9), 110, 3);
      await session(DateTime(2026, 5, 1, 9), 100, 5);
      await session(DateTime(2026, 5, 4, 9), 200, 5, warm: true);
      await session(DateTime(2026, 5, 5, 9), 150, 5, finish: false);
      final ref = (await repo.exercisesWithHistory()).single['id'] as String;
      final pts = await repo.strengthSessions(ref);
      expect(pts.map((p) => p.date.day), [1, 3]);
      expect(pts[0].e1rm, closeTo(116.67, 0.01));
      expect(pts[1].e1rm, closeTo(121.0, 0.01));
      expect(pts[0].volume, 500);
    });

    test('week: goal valid on each day, days without entries are null',
        () async {
      final n = repo.db;
      await n.insert('nutrition_entries', {'id': 'x', 'date': '2026-05-10', 'name': 'a', 'calories': 1500, 'protein': 0, 'fat': 0, 'carbs': 0});
      await n.insert('nutrition_goals', {'id': 'g', 'effective_from': '2026-05-09', 'calories': 2000});
      final wk = await repo.week(DateTime(2026, 5, 10));
      expect(wk.length, 7);
      expect(wk.last.totals!.kcal, 1500);
      expect(wk.last.goalKcal, 2000);
      expect(wk.first.totals, isNull);
      expect(wk.first.goalKcal, isNull); // before the goal's date
    });
  });
}
