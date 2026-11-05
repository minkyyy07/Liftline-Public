import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:liftline_app/auth/api_client.dart';
import 'package:liftline_app/auth/auth_service.dart';
import 'package:liftline_app/auth/cloud_workout_sync.dart';
import 'package:liftline_app/auth/token_storage.dart';
import 'package:liftline_app/auth/workout_sync_mapper.dart';
import 'package:liftline_app/db.dart';
import 'package:liftline_app/repo.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// In-process stand-in for the Spring Boot API. It stores exactly the JSON the client sent
/// (after a jsonEncode/jsonDecode round trip, like the real HTTP layer) and answers with the
/// same status codes. Server-side merge rules are covered by the backend tests and by the
/// real-backend integration test.
class FakeWorkoutServer extends http.BaseClient {
  final Map<String, Map<String, dynamic>> items = {};
  int _clock = 0;

  /// Simulates the server being unreachable for uploads (download still works).
  bool failPut = false;

  Map<String, dynamic> _copy(Map<String, dynamic> m) =>
      jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path == '/api/workouts') {
      final page = int.parse(request.url.queryParameters['page'] ?? '0');
      final size = int.parse(request.url.queryParameters['size'] ?? '20');
      final all = items.values.map(_copy).toList()
        ..sort((a, b) {
          final byDate = (b['workoutDate'] as String).compareTo(a['workoutDate'] as String);
          return byDate != 0 ? byDate : (a['id'] as String).compareTo(b['id'] as String);
        });
      final slice = all.skip(page * size).take(size).toList();
      return _json(slice, 200);
    }
    if (request.method == 'POST' && path == '/api/workouts') {
      final body = jsonDecode((request as http.Request).body) as Map<String, dynamic>;
      final id = body['id'] as String;
      if (items.containsKey(id)) {
        return _json(_copy(items[id]!), 201); // idempotent retry
      }
      items[id] = _stored(body, version: 0);
      return _json(_copy(items[id]!), 201);
    }
    if (request.method == 'PUT' && path.startsWith('/api/workouts/')) {
      final id = path.split('/').last;
      final current = items[id];
      if (current == null) {
        return _json({'error': 'not found'}, 404);
      }
      if (failPut) {
        throw const SocketException('offline');
      }
      final body = jsonDecode((request as http.Request).body) as Map<String, dynamic>;
      final sentVersion = body['version'];
      if (sentVersion != null && sentVersion != current['version']) {
        return _json({'error': 'Workout conflict'}, 409);
      }
      items[id] = _stored(body, version: (current['version'] as int) + 1);
      return _json(_copy(items[id]!), 200);
    }
    if (request.method == 'DELETE' && path.startsWith('/api/workouts/')) {
      items.remove(path.split('/').last);
      return http.StreamedResponse(const Stream.empty(), 204);
    }
    return _json({'status': 'ok'}, 200);
  }

  Map<String, dynamic> _stored(Map<String, dynamic> body, {required int version}) {
    final copy = _copy(body);
    copy['status'] ??= 'finished'; // backend default for payloads without a status
    copy['version'] = version;
    copy['updatedAt'] = DateTime.utc(2026, 11, 5, 10, 0, _clock++).toIso8601String();
    return copy;
  }

  http.StreamedResponse _json(Object body, int status) => http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        headers: {'content-type': 'application/json'},
      );
}

/// One local installation: its own SQLite file, logged into the (shared) server account.
class Device {
  Device._(this.userId, this.appDb, this.auth, this.sync);

  final String userId;
  final AppDb appDb;
  final AuthService auth;
  final CloudWorkoutSync sync;

  static Future<String> dbPathFor(String userId) async {
    final dir = await databaseFactoryFfi.getDatabasesPath();
    final safe = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return p.join(dir, 'liftline_user_$safe.db');
  }

  /// Fresh install: deletes any file left by a previous run, then logs in.
  static Future<Device> install(String userId, FakeWorkoutServer server) async {
    await databaseFactoryFfi.deleteDatabase(await dbPathFor(userId));
    final appDb = AppDb.isolated();
    final tokens = InMemoryTokenStorage();
    await tokens.setAccessToken('access-$userId');
    await tokens.setRefreshToken('refresh-$userId');
    await tokens.setUserId(userId);
    await tokens.setUserEmail('$userId@example.com');
    final apiClient = ApiClient(baseUrl: 'http://test.local', tokenStorage: tokens, client: server);
    final auth = AuthService.forTest(tokenStorage: tokens, apiClient: apiClient, appDb: appDb);
    await auth.init(); // opens liftline_user_<userId>.db through the production code path
    final sync = CloudWorkoutSync(apiClient: apiClient, authService: auth, appDb: appDb);
    return Device._(userId, appDb, auth, sync);
  }

  Database get db => appDb.db;
  WorkoutRepo get repo => WorkoutRepo(appDb.db);

  /// Real close + reopen of the SQLite file (what happens on app restart).
  Future<void> restart() async {
    await appDb.db.close();
    final reopened = await openLiftlineDb(await dbPathFor(userId), factory: databaseFactoryFfi);
    appDb.useDatabase(reopened);
  }

  Future<void> dispose() async {
    if (appDb.isOpen) {
      await appDb.db.close();
    }
    await databaseFactoryFfi.deleteDatabase(await dbPathFor(userId));
  }
}

Future<Map<String, Object?>> _row(Database db, String table, String id) async {
  final rows = await db.query(table, where: 'id = ?', whereArgs: [id]);
  expect(rows, hasLength(1), reason: '$table $id');
  return rows.first;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final suffix = DateTime.now().microsecondsSinceEpoch;

  final devices = <Device>[];
  Future<Device> newDevice(String tag, FakeWorkoutServer server) async {
    final d = await Device.install('dev_${tag}_$suffix', server);
    devices.add(d);
    return d;
  }

  tearDown(() async {
    for (final d in devices) {
      await d.dispose();
    }
    devices.clear();
  });

  group('production mapper (upload payload and download columns)', () {
    test('planned workout payload carries status, lifecycle, plan, RIR and catalogue ref', () {
      final payload = buildWorkoutUploadPayload(
        workout: {
          'id': 'w1',
          'title': 'Push',
          'date': '2026-11-04',
          'duration_minutes': null,
          'notes': null,
          'status': 'planned',
          'started_at_utc': null,
          'finished_at_utc': null,
          'server_version': null,
          'server_updated_at': null,
        },
        exercises: [
          {
            'id': 'e1',
            'workout_id': 'w1',
            'exercise_name': 'Bench',
            'sort_order': 1,
            'exercise_ref_id': 'cat-bench',
            'note': 'pause',
            'plan_sets': 4,
            'plan_rep_min': 6,
            'plan_rep_max': 10,
            'plan_rir': 2,
            'plan_rest_sec': 120,
          },
        ],
        sets: {
          'e1': [
            {
              'id': 's1',
              'exercise_id': 'e1',
              'set_number': 1,
              'weight_kg': 80.0,
              'reps': 8,
              'rir': 1,
              'completed': 0,
              'set_type': 'work',
              'note': null,
              'completed_at_utc': null,
            },
          ],
        },
      );

      final wire = jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;
      expect(wire['status'], 'planned');
      expect(wire['startedAtUtc'], isNull);
      expect(wire.containsKey('version'), isFalse, reason: 'never synced: no revision sent');
      final ex = (wire['exercises'] as List).single as Map<String, dynamic>;
      expect(ex['exerciseRefId'], 'cat-bench');
      expect(ex['notes'], 'pause');
      expect(ex['planSets'], 4);
      expect(ex['planRepMin'], 6);
      expect(ex['planRepMax'], 10);
      expect(ex['planRir'], 2);
      expect(ex['planRestSec'], 120);
      final s = (ex['sets'] as List).single as Map<String, dynamic>;
      expect(s['rir'], 1);
      expect(s['completed'], isFalse);
      expect(s['completedAtUtc'], isNull);
    });

    test('lifecycle timestamps are sent as UTC ISO strings and parsed back to the same ms', () {
      const startedMs = 1793800000123;
      final iso = isoUtcFromMs(startedMs)!;
      expect(iso.endsWith('Z'), isTrue);
      expect(msFromIsoUtc(iso), startedMs);
      expect(isoUtcFromMs(null), isNull);
      expect(msFromIsoUtc(null), isNull);
      expect(() => msFromIsoUtc('not-a-date'), throwsFormatException);
    });

    test('download: absent keys are not written, explicit null clears, invalid status ignored', () {
      final partial = serverWorkoutColumns({'id': 'w', 'title': 'T'});
      expect(partial, {'title': 'T'});

      final cleared = serverWorkoutColumns({
        'id': 'w',
        'durationMinutes': null,
        'notes': null,
        'status': 'bogus',
        'startedAtUtc': null,
      });
      expect(cleared, {'duration_minutes': null, 'notes': null, 'started_at_utc': null});

      final exCols = serverExerciseColumns({'id': 'e', 'exerciseName': 'Row'});
      expect(exCols, {'exercise_name': 'Row'});
      final setCols = serverSetColumns({'id': 's', 'setNumber': 2});
      expect(setCols, {'set_number': 2});
      expect(serverSetColumns({'rir': null}), {'rir': null});
    });

    test('download: NOT NULL columns map null to neutral defaults', () {
      expect(serverSetColumns({'weightKg': null, 'reps': null, 'completed': null, 'setType': null}), {
        'weight_kg': 0.0,
        'reps': 0,
        'completed': 1,
        'set_type': 'work',
      });
    });
  });

  group('upload -> backend -> download into a clean local database', () {
    test('planned workout survives the full cycle and keeps its state after restart', () async {
      final server = FakeWorkoutServer();
      final a = await newDevice('a', server);
      final b = await newDevice('b', server);

      final repoA = a.repo;
      final wId = await repoA.createWorkout(
        title: 'Planned Push',
        date: DateTime(2026, 11, 4),
        start: false,
        status: 'planned',
      );
      final exId = await repoA.addExercise(wId, 'Bench Press');
      await repoA.updatePlan(exId, sets: 4, repMin: 6, repMax: 10, rir: 2, restSec: 120, note: 'pause 2s');
      final setId = await repoA.addSet(exId);
      await repoA.updateSet(setId, weight: 80, reps: 8, rir: 1);
      await a.sync.processSyncQueue(a.db);

      final serverItem = server.items[wId]!;
      expect(serverItem['status'], 'planned');
      expect(serverItem['startedAtUtc'], isNull);

      // Device B has an empty database.
      await b.sync.syncFromServer(b.db);
      final w = await _row(b.db, 'workouts', wId);
      expect(w['status'], 'planned');
      expect(w['started_at_utc'], isNull);
      expect(w['finished_at_utc'], isNull);
      expect(w['date'], '2026-11-04');
      expect(w['sync_status'], 'synced');

      final ex = (await b.repo.workoutExercises(wId)).single;
      expect(ex['exercise_name'], 'Bench Press');
      expect(ex['exercise_ref_id'], isNotNull);
      expect(ex['plan_sets'], 4);
      expect(ex['plan_rep_min'], 6);
      expect(ex['plan_rep_max'], 10);
      expect(ex['plan_rir'], 2);
      expect(ex['plan_rest_sec'], 120);
      expect(ex['note'], 'pause 2s');

      final set = (await b.repo.sets(ex['id'] as String)).single;
      expect(set['weight_kg'], 80.0);
      expect(set['reps'], 8);
      expect(set['rir'], 1);
      expect(set['set_type'], 'work');

      // Persisted in the file: close and reopen.
      await b.restart();
      expect((await _row(b.db, 'workouts', wId))['status'], 'planned');

      // A planned workout can be started on the other device.
      await b.repo.startWorkout(wId);
      await b.sync.processSyncQueue(b.db);
      await a.sync.syncFromServer(a.db);
      expect((await _row(a.db, 'workouts', wId))['status'], 'active');
    });

    test('active workout is restored, continued on the other device and finished', () async {
      final server = FakeWorkoutServer();
      final a = await newDevice('a', server);
      final b = await newDevice('b', server);

      final wId = await a.repo.createWorkout(title: 'Pull', date: DateTime(2026, 11, 4), start: true);
      final startedMs = (await _row(a.db, 'workouts', wId))['started_at_utc'] as int;
      final exId = await a.repo.addExercise(wId, 'Row');
      final s1 = await a.repo.addSet(exId);
      await a.repo.updateSet(s1, weight: 60, reps: 10, rir: 2);
      await a.repo.setCompleted(s1, true);
      await a.repo.addSet(exId); // not completed
      await a.sync.processSyncQueue(a.db);

      await b.sync.syncFromServer(b.db);
      final restored = await _row(b.db, 'workouts', wId);
      expect(restored['status'], 'active');
      expect(restored['started_at_utc'], startedMs);
      expect(restored['finished_at_utc'], isNull);

      // Continue: add a set, then finish.
      final exB = (await b.repo.workoutExercises(wId)).single['id'] as String;
      await b.repo.addSet(exB);
      expect(await b.repo.finishWorkout(wId), isTrue);
      final finished = await _row(b.db, 'workouts', wId);
      expect(finished['status'], 'finished');
      expect(finished['finished_at_utc'], isNotNull);
      expect(await b.repo.sets(exB), hasLength(3));

      await b.sync.processSyncQueue(b.db);
      expect(server.items[wId]!['status'], 'finished');

      await a.sync.syncFromServer(a.db);
      final onA = await _row(a.db, 'workouts', wId);
      expect(onA['status'], 'finished');
      expect(onA['finished_at_utc'], finished['finished_at_utc']);
      expect(await a.repo.sets(exId), hasLength(3));
    });

    test('finished stays finished through repeated downloads, and downloads never duplicate rows', () async {
      final server = FakeWorkoutServer();
      final a = await newDevice('a', server);
      final b = await newDevice('b', server);

      final wId = await a.repo.createWorkout(title: 'Legs', date: DateTime(2026, 11, 3), start: true);
      final exId = await a.repo.addExercise(wId, 'Squat');
      final setId = await a.repo.addSet(exId);
      await a.repo.updateSet(setId, weight: 100, reps: 5);
      await a.repo.setCompleted(setId, true);
      await a.repo.finishWorkout(wId);
      await a.sync.processSyncQueue(a.db);

      await b.sync.syncFromServer(b.db);
      final first = await _snapshot(b.db);
      await b.sync.syncFromServer(b.db);
      await b.sync.syncFromServer(b.db);
      expect(await _snapshot(b.db), first);
      expect(first['workouts'], 1);
      expect(first['exercises'], 1);
      expect(first['sets'], 1);
      expect((await _row(b.db, 'workouts', wId))['status'], 'finished');
    });
  });

  group('compatibility and atomicity', () {
    test('old payload without new fields does not erase local lifecycle, plan or RIR', () async {
      final server = FakeWorkoutServer();
      final a = await newDevice('a', server);

      final wId = await a.repo.createWorkout(title: 'Active', date: DateTime(2026, 11, 4), start: true);
      final exId = await a.repo.addExercise(wId, 'Dip');
      await a.repo.updatePlan(exId, sets: 3, repMin: 8, repMax: 12, rir: 1, restSec: 90);
      final setId = await a.repo.addSet(exId);
      await a.repo.updateSet(setId, weight: 20, reps: 10, rir: 2);
      await a.repo.setCompleted(setId, true);
      await a.sync.processSyncQueue(a.db);
      final startedBefore = (await _row(a.db, 'workouts', wId))['started_at_utc'];

      // An older client wrote the server copy: only legacy keys, a new title.
      final legacy = {
        'id': wId,
        'title': 'Renamed by old client',
        'workoutDate': '2026-11-04',
        'durationMinutes': null,
        'notes': null,
        'version': server.items[wId]!['version'],
        'exercises': [
          {
            'id': exId,
            'exerciseName': 'Dip',
            'sortOrder': 1,
            'sets': [
              {'id': setId, 'setNumber': 1, 'weightKg': 25.0, 'reps': 10, 'completed': true, 'setType': 'work'},
            ],
          },
        ],
      };
      server.items[wId] = {...legacy, 'version': (server.items[wId]!['version'] as int) + 1, 'updatedAt': '2026-11-05T11:00:00Z'};

      await a.sync.syncFromServer(a.db);

      final w = await _row(a.db, 'workouts', wId);
      expect(w['title'], 'Renamed by old client');
      expect(w['status'], 'active', reason: 'status absent from payload must be kept');
      expect(w['started_at_utc'], startedBefore);

      final ex = await _row(a.db, 'workout_exercises', exId);
      expect(ex['plan_sets'], 3);
      expect(ex['plan_rep_min'], 8);
      expect(ex['plan_rir'], 1);
      expect(ex['plan_rest_sec'], 90);
      expect(ex['exercise_ref_id'], isNotNull);

      final s = await _row(a.db, 'set_entries', setId);
      expect(s['weight_kg'], 25.0);
      expect(s['rir'], 2, reason: 'RIR absent from payload must be kept');
      expect(s['completed_at_utc'], isNotNull);
    });

    test('old payload for a new workout imports as finished with catalogue reference by name', () async {
      final server = FakeWorkoutServer();
      final b = await newDevice('b', server);
      final wId = 'legacy-$suffix-w';
      server.items[wId] = {
        'id': wId,
        'title': 'Old',
        'workoutDate': '2026-10-01',
        'durationMinutes': 45,
        'notes': null,
        'version': 0,
        'exercises': [
          {
            'id': 'legacy-$suffix-e',
            'exerciseName': 'Deadlift',
            'sortOrder': 1,
            'sets': [
              {'id': 'legacy-$suffix-s', 'setNumber': 1, 'weightKg': 140.0, 'reps': 3, 'completed': true, 'setType': 'work'},
            ],
          },
        ],
      };

      await b.sync.syncFromServer(b.db);
      final w = await _row(b.db, 'workouts', wId);
      expect(w['status'], 'finished');
      expect(w['started_at_utc'], isNull);
      final ex = await _row(b.db, 'workout_exercises', 'legacy-$suffix-e');
      final cat = await b.db.query('exercises', where: 'name = ?', whereArgs: ['Deadlift']);
      expect(cat, hasLength(1));
      expect(ex['exercise_ref_id'], cat.single['id']);
    });

    test('a failing workout import is rolled back as a whole; other workouts are still imported', () async {
      final server = FakeWorkoutServer();
      final a = await newDevice('a', server);
      final b = await newDevice('b', server);

      final wId = await a.repo.createWorkout(title: 'Stable', date: DateTime(2026, 11, 4), start: true);
      final exId = await a.repo.addExercise(wId, 'Press');
      await a.repo.updatePlan(exId, sets: 4, repMin: 5, repMax: 8, rir: 2);
      final setId = await a.repo.addSet(exId);
      await a.repo.updateSet(setId, weight: 50, reps: 6, rir: 1);
      await a.repo.setCompleted(setId, true);
      final otherId = await a.repo.createWorkout(title: 'Other', date: DateTime(2026, 11, 4), start: false, status: 'planned');
      await a.sync.processSyncQueue(a.db);

      // Device B already has both workouts, synced.
      await b.sync.syncFromServer(b.db);
      final before = await _snapshot(b.db);

      // Server copy of the first workout is corrupt: a broken timestamp in a late set,
      // after the title and exercise name were already applied in the same import.
      final corrupt = jsonDecode(jsonEncode(server.items[wId])) as Map<String, dynamic>;
      corrupt['title'] = 'Half-applied title';
      (corrupt['exercises'] as List).first['exerciseName'] = 'Half-applied exercise';
      ((corrupt['exercises'] as List).first['sets'] as List).first['completedAtUtc'] = 'broken';
      corrupt['version'] = (server.items[wId]!['version'] as int) + 1;
      server.items[wId] = corrupt;

      // The other workout changes legitimately on the server.
      server.items[otherId] = {...server.items[otherId]!, 'title': 'Other renamed', 'version': (server.items[otherId]!['version'] as int) + 1};

      await expectLater(
        b.sync.syncFromServer(b.db),
        throwsA(isA<WorkoutImportException>().having((e) => e.failedCount, 'failedCount', 1)),
      );

      final w = await _row(b.db, 'workouts', wId);
      expect(w['title'], 'Stable', reason: 'failed workout must not be partially overwritten');
      final ex = await _row(b.db, 'workout_exercises', exId);
      expect(ex['exercise_name'], 'Press');
      expect(ex['plan_rir'], 2);
      final s = await _row(b.db, 'set_entries', setId);
      expect(s['rir'], 1);
      expect(s['completed_at_utc'], isNotNull);
      expect(await _snapshot(b.db), before, reason: 'row counts unchanged');

      // The other workout in the same pass was applied.
      expect((await _row(b.db, 'workouts', otherId))['title'], 'Other renamed');
    });

    test('local pending edits are not overwritten by a download', () async {
      final server = FakeWorkoutServer();
      final a = await newDevice('a', server);
      final wId = await a.repo.createWorkout(title: 'Mine', date: DateTime(2026, 11, 4), start: false);
      await a.sync.processSyncQueue(a.db);
      await a.repo.renameWorkout(wId, 'Mine (offline edit)');
      server.failPut = true; // upload fails, so the local edit stays pending/error
      server.items[wId] = {...server.items[wId]!, 'title': 'Server title', 'version': 9, 'updatedAt': '2026-11-06T00:00:00Z'};

      await a.sync.syncFromServer(a.db);
      server.failPut = false;
      final w = await _row(a.db, 'workouts', wId);
      expect(w['title'], 'Mine (offline edit)');
      expect(w['sync_status'], 'conflict');

      // "Accept server" goes through the same importer and clears the conflict.
      await a.sync.resolveConflictAcceptServer(a.db, wId);
      final resolved = await _row(a.db, 'workouts', wId);
      expect(resolved['title'], 'Server title');
      expect(resolved['sync_status'], 'synced');
      expect(resolved['server_version'], 9);
      expect(await a.db.query('workout_conflict_drafts'), isEmpty);
    });
  });

  group('catalogue and account isolation', () {
    test('server exercise ref is reused when the same name exists locally under another id', () async {
      final server = FakeWorkoutServer();
      final a = await newDevice('a', server);
      final b = await newDevice('b', server);

      final wId = await a.repo.createWorkout(title: 'Ref', date: DateTime(2026, 11, 4), start: false);
      final exId = await a.repo.addExercise(wId, 'Lateral Raise');
      await a.sync.processSyncQueue(a.db);

      final localId = await b.repo.findOrCreateExercise('Lateral Raise');
      await b.sync.syncFromServer(b.db);

      final ex = await _row(b.db, 'workout_exercises', exId);
      expect(ex['exercise_ref_id'], localId, reason: 'no duplicate catalogue entry');
      final cat = await b.db.query('exercises', where: 'name = ?', whereArgs: ['Lateral Raise']);
      expect(cat, hasLength(1));
    });

    test('a workout downloaded for account A is never visible in account B', () async {
      final server = FakeWorkoutServer();
      final a = await newDevice('iso_a', server);
      await a.repo.createWorkout(title: 'A only', date: DateTime(2026, 11, 4), start: false);
      await a.sync.processSyncQueue(a.db);

      final otherUser = 'dev_iso_b_$suffix';
      await databaseFactoryFfi.deleteDatabase(await Device.dbPathFor(otherUser));
      await a.appDb.switchToUser(otherUser, factory: databaseFactoryFfi);
      expect(await a.repo.listWorkouts(), isEmpty);

      await a.appDb.switchToUser(a.userId, factory: databaseFactoryFfi);
      final mine = await a.repo.listWorkouts();
      expect(mine.map((w) => w['title']), ['A only']);
      await databaseFactoryFfi.deleteDatabase(await Device.dbPathFor(otherUser));
    });
  });
}

Future<Map<String, int>> _snapshot(Database db) async {
  Future<int> count(String sql) async =>
      Sqflite.firstIntValue(await db.rawQuery(sql)) ?? 0;
  return {
    'workouts': await count('SELECT COUNT(*) FROM workouts'),
    'exercises': await count('SELECT COUNT(*) FROM workout_exercises'),
    'sets': await count('SELECT COUNT(*) FROM set_entries'),
  };
}
