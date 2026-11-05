import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:liftline_app/auth/api_client.dart';
import 'package:liftline_app/auth/auth_service.dart';
import 'package:liftline_app/auth/cloud_workout_sync.dart';
import 'package:liftline_app/auth/token_storage.dart';
import 'package:liftline_app/db.dart';
import 'package:liftline_app/repo.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Full cycle against the REAL Spring Boot backend (HTTP, Flyway, JPA, JSON):
/// device A uploads planned / active / finished workouts, device B downloads them into an
/// empty database, restarts, continues the active one and finishes it, device A picks it up.
///
/// Skipped unless the backend runs on 127.0.0.1:8080 (set MANDATORY_INTEGRATION=true to fail
/// instead of skip). Start it with the dev profile:
///   JWT_SECRET=<32+ bytes> java -jar backend/target/backend-0.1.0.jar --spring.profiles.active=dev
// No TestWidgetsFlutterBinding here: it replaces HttpClient with a stub that answers 400.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const baseUrl = 'http://127.0.0.1:8080';

  test('planned, active and finished workouts round-trip through the real backend', () async {
    var backendUp = false;
    try {
      final r = await http.get(Uri.parse('$baseUrl/api/workouts')).timeout(const Duration(milliseconds: 800));
      backendUp = r.statusCode == 401 || r.statusCode == 403;
    } catch (_) {
      backendUp = false;
    }
    if (!backendUp) {
      if (Platform.environment['MANDATORY_INTEGRATION'] == 'true') {
        fail('Backend is not running at $baseUrl, but MANDATORY_INTEGRATION is enabled');
      }
      markTestSkipped('Backend is not running on $baseUrl. Set MANDATORY_INTEGRATION=true to require it.');
      return;
    }

    final ts = DateTime.now().microsecondsSinceEpoch;
    final email = 'sync_contract_$ts@example.com';
    const password = 'Password123!';
    final httpClient = http.Client();
    final dbPaths = <String>[];
    final appDbs = <AppDb>[];

    try {
      // ---------- device A: the account owner ----------
      final tokensA = InMemoryTokenStorage();
      final apiA = ApiClient(baseUrl: baseUrl, tokenStorage: tokensA, client: httpClient);
      final appDbA = AppDb.isolated();
      appDbs.add(appDbA);
      final authA = AuthService.forTest(tokenStorage: tokensA, apiClient: apiA, appDb: appDbA);
      await authA.register(email, password);
      await authA.login(email, password);
      expect(authA.isAuthenticated, isTrue, reason: authA.errorMessage);
      final syncA = CloudWorkoutSync(apiClient: apiA, authService: authA, appDb: appDbA);
      final dbA = appDbA.db;
      dbPaths.add(await Device.dbPathFor(authA.user!.id));
      final repoA = WorkoutRepo(dbA);

      final plannedId = await repoA.createWorkout(
        title: 'Planned Push',
        date: DateTime(2026, 11, 10),
        start: false,
        status: 'planned',
      );
      final plannedEx = await repoA.addExercise(plannedId, 'Bench Press');
      await repoA.updatePlan(plannedEx, sets: 4, repMin: 6, repMax: 10, rir: 2, restSec: 120, note: 'pause 2s');
      final plannedSet = await repoA.addSet(plannedEx);
      await repoA.updateSet(plannedSet, weight: 80, reps: 8, rir: 1);

      final finishedId = await repoA.createWorkout(title: 'Finished Legs', date: DateTime(2026, 11, 9), start: true);
      final finishedEx = await repoA.addExercise(finishedId, 'Squat');
      final finishedSet = await repoA.addSet(finishedEx);
      await repoA.updateSet(finishedSet, weight: 100, reps: 5, rir: 3);
      await repoA.setCompleted(finishedSet, true);
      expect(await repoA.finishWorkout(finishedId), isTrue);

      final activeId = await repoA.createWorkout(title: 'Active Pull', date: DateTime(2026, 11, 10), start: true);
      final activeEx = await repoA.addExercise(activeId, 'Barbell Row');
      final activeSet1 = await repoA.addSet(activeEx);
      await repoA.updateSet(activeSet1, weight: 70, reps: 8, rir: 2);
      await repoA.setCompleted(activeSet1, true);
      await repoA.addSet(activeEx); // open set

      await syncA.processSyncQueue(dbA);
      final localActiveStarted = (await dbA.query('workouts', where: 'id = ?', whereArgs: [activeId])).single['started_at_utc'] as int;
      final localFinishedAt = (await dbA.query('workouts', where: 'id = ?', whereArgs: [finishedId])).single['finished_at_utc'] as int;

      // What the server really stored (direct HTTP read, independent of the client mapper).
      final token = await tokensA.getAccessToken();
      Future<Map<String, dynamic>> serverGet(String id) async {
        final res = await httpClient.get(
          Uri.parse('$baseUrl/api/workouts/$id'),
          headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
        );
        expect(res.statusCode, 200, reason: res.body);
        return jsonDecode(res.body) as Map<String, dynamic>;
      }

      final serverPlanned = await serverGet(plannedId);
      expect(serverPlanned['status'], 'planned');
      expect(serverPlanned['startedAtUtc'], isNull);
      final serverPlannedEx = (serverPlanned['exercises'] as List).single as Map<String, dynamic>;
      expect(serverPlannedEx['planRir'], 2);
      expect(serverPlannedEx['exerciseRefId'], isNotNull);
      expect(((serverPlannedEx['sets'] as List).single as Map)['rir'], 1);

      final serverActive = await serverGet(activeId);
      expect(serverActive['status'], 'active');
      expect(serverActive['startedAtUtc'], isNotNull);
      expect(DateTime.parse(serverActive['startedAtUtc'] as String).millisecondsSinceEpoch, localActiveStarted);

      final serverFinished = await serverGet(finishedId);
      expect(serverFinished['status'], 'finished');
      expect(DateTime.parse(serverFinished['finishedAtUtc'] as String).millisecondsSinceEpoch, localFinishedAt);

      // ---------- device B: same account, EMPTY local database ----------
      final tokensB = InMemoryTokenStorage();
      await tokensB.setAccessToken(token!);
      await tokensB.setRefreshToken((await tokensA.getRefreshToken())!);
      final localUserB = 'devB_$ts';
      await tokensB.setUserId(localUserB);
      await tokensB.setUserEmail(email);
      final apiB = ApiClient(baseUrl: baseUrl, tokenStorage: tokensB, client: httpClient);
      final appDbB = AppDb.isolated();
      appDbs.add(appDbB);
      final authB = AuthService.forTest(tokenStorage: tokensB, apiClient: apiB, appDb: appDbB);
      dbPaths.add(await Device.dbPathFor(localUserB));
      await databaseFactoryFfi.deleteDatabase(await Device.dbPathFor(localUserB));
      await authB.init();
      expect(authB.isAuthenticated, isTrue);
      final syncB = CloudWorkoutSync(apiClient: apiB, authService: authB, appDb: appDbB);
      final dbB = appDbB.db;
      expect(await dbB.query('workouts'), isEmpty);

      final downloaded = await syncB.syncFromServer(dbB);
      expect(downloaded, 3);

      Future<Map<String, Object?>> row(Database db, String table, String id) async =>
          (await db.query(table, where: 'id = ?', whereArgs: [id])).single;

      final bPlanned = await row(dbB, 'workouts', plannedId);
      expect(bPlanned['status'], 'planned');
      expect(bPlanned['started_at_utc'], isNull);
      expect(bPlanned['date'], '2026-11-10');
      final bPlannedEx = (await WorkoutRepo(dbB).workoutExercises(plannedId)).single;
      expect(bPlannedEx['exercise_ref_id'], serverPlannedEx['exerciseRefId']);
      expect(bPlannedEx['plan_sets'], 4);
      expect(bPlannedEx['plan_rep_min'], 6);
      expect(bPlannedEx['plan_rep_max'], 10);
      expect(bPlannedEx['plan_rir'], 2);
      expect(bPlannedEx['plan_rest_sec'], 120);
      expect(bPlannedEx['note'], 'pause 2s');
      final bPlannedSet = (await WorkoutRepo(dbB).sets(bPlannedEx['id'] as String)).single;
      expect(bPlannedSet['rir'], 1);
      expect(bPlannedSet['weight_kg'], 80.0);

      final bActive = await row(dbB, 'workouts', activeId);
      expect(bActive['status'], 'active');
      expect(bActive['started_at_utc'], localActiveStarted);
      expect(bActive['finished_at_utc'], isNull);

      final bFinished = await row(dbB, 'workouts', finishedId);
      expect(bFinished['status'], 'finished');
      expect(bFinished['finished_at_utc'], localFinishedAt);
      final bFinishedSet = (await WorkoutRepo(dbB).sets(
        (await WorkoutRepo(dbB).workoutExercises(finishedId)).single['id'] as String,
      )).single;
      expect(bFinishedSet['rir'], 3);

      // Restart device B: real close + reopen of the SQLite file.
      await dbB.close();
      final reopenedB = await openLiftlineDb(await Device.dbPathFor(localUserB), factory: databaseFactoryFfi);
      appDbB.useDatabase(reopenedB);
      expect((await row(reopenedB, 'workouts', activeId))['status'], 'active');

      // Continue the active workout on B: add a set, finish, upload.
      final bActiveEx = (await WorkoutRepo(reopenedB).workoutExercises(activeId)).single['id'] as String;
      await WorkoutRepo(reopenedB).addSet(bActiveEx);
      expect(await WorkoutRepo(reopenedB).finishWorkout(activeId), isTrue);
      final bActiveFinishedAt = (await row(reopenedB, 'workouts', activeId))['finished_at_utc'] as int;
      await syncB.processSyncQueue(reopenedB);
      expect((await row(reopenedB, 'workouts', activeId))['sync_status'], 'synced');

      final serverAfterFinish = await serverGet(activeId);
      expect(serverAfterFinish['status'], 'finished');
      expect(DateTime.parse(serverAfterFinish['finishedAtUtc'] as String).millisecondsSinceEpoch, bActiveFinishedAt);
      expect((serverAfterFinish['exercises'] as List).single['sets'], hasLength(3));

      // Device A downloads the result; finished stays finished, nothing duplicated.
      await syncA.syncFromServer(dbA);
      expect((await row(dbA, 'workouts', activeId))['status'], 'finished');
      expect((await row(dbA, 'workouts', plannedId))['status'], 'planned');
      expect(await dbA.query('workouts'), hasLength(3));

      // Repeated download on B changes nothing.
      final countsBefore = await reopenedB.rawQuery('SELECT COUNT(*) AS c FROM set_entries');
      await syncB.syncFromServer(reopenedB);
      await syncB.syncFromServer(reopenedB);
      expect(await reopenedB.query('workouts'), hasLength(3));
      expect(await reopenedB.rawQuery('SELECT COUNT(*) AS c FROM set_entries'), countsBefore);
      expect((await row(reopenedB, 'workouts', finishedId))['status'], 'finished');
    } finally {
      for (final db in appDbs) {
        if (db.isOpen) {
          await db.db.close();
        }
      }
      for (final path in dbPaths) {
        await databaseFactoryFfi.deleteDatabase(path);
      }
      httpClient.close();
    }
  });
}

/// Re-declared here (instead of imported) so this file stays independent of the contract test.
class Device {
  static Future<String> dbPathFor(String userId) async {
    final dir = await databaseFactoryFfi.getDatabasesPath();
    final safe = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return p.join(dir, 'liftline_user_$safe.db');
  }
}
