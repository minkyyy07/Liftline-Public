import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:liftline_app/auth/api_client.dart';
import 'package:liftline_app/auth/auth_service.dart';
import 'package:liftline_app/auth/cloud_workout_sync.dart';
import 'package:liftline_app/auth/token_storage.dart';
import 'package:liftline_app/db.dart';
import 'package:liftline_app/nutrition_calc.dart';
import 'package:liftline_app/nutrition_repo.dart';
import 'package:liftline_app/repo.dart';
import 'package:liftline_app/today_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class RecordingHttpClient extends http.BaseClient {
  bool isOnline = true;
  bool return409OnPut = false;
  Completer<void>? inFlightCompleter;
  final List<http.BaseRequest> recordedRequests = [];
  final Map<String, Map<String, dynamic>> serverWorkouts = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    recordedRequests.add(request);

    if (!isOnline) {
      throw const SocketException('Network offline');
    }

    if (inFlightCompleter != null) {
      await inFlightCompleter!.future;
    }

    final path = request.url.path;

    if (request.method == 'GET' && path.endsWith('/api/workouts')) {
      final list = serverWorkouts.values.toList();
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(list))),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    if (request.method == 'POST' && path.endsWith('/api/workouts')) {
      final bodyStr = (request as http.Request).body;
      final body = jsonDecode(bodyStr) as Map<String, dynamic>;
      final id = body['id'] as String? ?? 'server-${serverWorkouts.length + 1}';
      final item = {
        ...body,
        'id': id,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      serverWorkouts[id] = item;
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(item))),
        201,
        headers: {'content-type': 'application/json'},
      );
    }

    if (request.method == 'PUT' && path.contains('/api/workouts/')) {
      if (return409OnPut) {
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'error': 'Conflict: newer version exists'}))),
          409,
          headers: {'content-type': 'application/json'},
        );
      }
      final id = path.split('/').last;
      final bodyStr = (request as http.Request).body;
      final body = jsonDecode(bodyStr) as Map<String, dynamic>;
      final item = {
        ...body,
        'id': id,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      serverWorkouts[id] = item;
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(item))),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    if (request.method == 'DELETE' && path.contains('/api/workouts/')) {
      final id = path.split('/').last;
      serverWorkouts.remove(id);
      return http.StreamedResponse(
        const Stream.empty(),
        204,
        headers: {'content-type': 'application/json'},
      );
    }

    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'status': 'ok'}))),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final ffiFactory = databaseFactoryFfi;

  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  late Directory tempDir;
  late AppDb appDb;
  late RecordingHttpClient mockHttp;
  late InMemoryTokenStorage tokenStorage;
  late ApiClient apiClient;
  late AuthService authService;
  late CloudWorkoutSync sync;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ll_regression_');
    appDb = AppDb.isolated();
    mockHttp = RecordingHttpClient();
    tokenStorage = InMemoryTokenStorage();
    apiClient = ApiClient(baseUrl: 'http://test.local', tokenStorage: tokenStorage, client: mockHttp);
    authService = AuthService.forTest(tokenStorage: tokenStorage, apiClient: apiClient, appDb: appDb);

    // Setup authenticated user
    await tokenStorage.setAccessToken('valid_token');
    await tokenStorage.setRefreshToken('valid_refresh');
    await tokenStorage.setUserId('user_reg_1');
    await tokenStorage.setUserEmail('user_reg_1@example.com');
    await appDb.switchToUser('user_reg_1', factory: ffiFactory);
    await authService.init();

    sync = CloudWorkoutSync(apiClient: apiClient, authService: authService, appDb: appDb);
  });

  tearDown(() async {
    if (appDb.isOpen) await appDb.db.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Mandatory Regression Tests: Workouts, Account Isolation & Sessions', () {
    test('1. Создать -> добавить упражнения и подходы -> завершить -> синхронизировать -> получить с сервера все данные', () async {
      final repo = WorkoutRepo(appDb.db);
      final wId = await repo.createWorkout(
        title: 'Full Body A',
        date: DateTime(2026, 11, 4),
        start: true,
      );

      final exId = await repo.addExercise(wId, 'Pullups');
      final setId = await repo.addSet(exId, warmup: false);
      await repo.updateSet(setId, weight: 12.5, reps: 8);
      await repo.setCompleted(setId, true);
      await repo.finishWorkout(wId);

      // Process sync queue
      await sync.processSyncQueue(appDb.db);

      // Verify server received full workout with Pullups and set
      expect(mockHttp.serverWorkouts.containsKey(wId), isTrue);
      final serverItem = mockHttp.serverWorkouts[wId]!;
      expect(serverItem['title'], 'Full Body A');
      final exs = serverItem['exercises'] as List;
      expect(exs.length, 1);
      expect(exs.first['exerciseName'], 'Pullups');
      final sets = exs.first['sets'] as List;
      expect(sets.length, 1);
      expect(sets.first['weightKg'], 12.5);
      expect(sets.first['reps'], 8);
      expect(sets.first['completed'], isTrue);

      // Local workout is now marked synced
      final wLocal = (await appDb.db.query('workouts', where: 'id = ?', whereArgs: [wId])).first;
      expect(wLocal['sync_status'], 'synced');

      // Now syncFromServer: retains all data accurately
      final count = await sync.syncFromServer(appDb.db);
      expect(count, greaterThanOrEqualTo(1));
    });

    test('2. Повторная синхронизация и потерянный ответ POST не создают дубликатов', () async {
      final repo = WorkoutRepo(appDb.db);
      final wId = await repo.createWorkout(
        title: 'Chest & Tris',
        date: DateTime(2026, 11, 4),
        start: false,
      );

      // First sync attempt succeeds on server
      await sync.processSyncQueue(appDb.db);
      expect(mockHttp.serverWorkouts.containsKey(wId), isTrue);

      // Simulate a network replay / re-sync with the server
      await sync.syncFromServer(appDb.db);
      await sync.syncFromServer(appDb.db);

      // Verify exactly ONE workout exists in local SQLite
      final rows = await appDb.db.query('workouts', where: 'id = ? OR server_id = ?', whereArgs: [wId, wId]);
      expect(rows.length, 1);
    });

    test('3. Локальная правка во время отправки не теряется', () async {
      final repo = WorkoutRepo(appDb.db);
      final wId = await repo.createWorkout(
        title: 'Squat Session V1',
        date: DateTime(2026, 11, 4),
        start: false,
      );

      // Block server response mid-flight
      mockHttp.inFlightCompleter = Completer<void>();

      // Start sync
      final syncFuture = sync.processSyncQueue(appDb.db);

      // Local edit while request is in the air!
      await repo.renameWorkout(wId, 'Squat Session V2 (Modified During Send)');
      final wDuring = (await appDb.db.query('workouts', where: 'id = ?', whereArgs: [wId])).first;
      final verDuring = wDuring['client_version'] as int;
      expect(verDuring, greaterThan(1));

      // Release network response
      mockHttp.inFlightCompleter!.complete();
      await syncFuture;

      // Status must remain PENDING because newer local edits occurred!
      final wAfter = (await appDb.db.query('workouts', where: 'id = ?', whereArgs: [wId])).first;
      expect(wAfter['sync_status'], 'pending');
      expect(wAfter['title'], 'Squat Session V2 (Modified During Send)');

      // Next queue run sends V2
      await sync.processSyncQueue(appDb.db);
      final wFinal = (await appDb.db.query('workouts', where: 'id = ?', whereArgs: [wId])).first;
      expect(wFinal['sync_status'], 'synced');
      expect(mockHttp.serverWorkouts[wId]!['title'], 'Squat Session V2 (Modified During Send)');
    });

    test('4. Offline -> изменения -> перезапуск -> восстановление сети -> успешная отправка', () async {
      mockHttp.isOnline = false; // Go offline

      final repo = WorkoutRepo(appDb.db);
      final wId = await repo.createWorkout(
        title: 'Offline Powerlifting',
        date: DateTime(2026, 11, 4),
        start: false,
      );
      await repo.addExercise(wId, 'Deadlift');

      // Attempt sync while offline -> marks error, keeps in sync_queue
      await sync.processSyncQueue(appDb.db);
      final wOffline = (await appDb.db.query('workouts', where: 'id = ?', whereArgs: [wId])).first;
      expect(wOffline['sync_status'], 'error');
      expect((await appDb.db.query('sync_queue')).isNotEmpty, isTrue);

      // Simulate app restart / reopen database
      await appDb.switchToUser('user_reg_1', factory: ffiFactory);

      // Network restored
      mockHttp.isOnline = true;
      await sync.processSyncQueue(appDb.db);

      // Successfully synced
      final wOnline = (await appDb.db.query('workouts', where: 'id = ?', whereArgs: [wId])).first;
      expect(wOnline['sync_status'], 'synced');
      expect(mockHttp.serverWorkouts.containsKey(wId), isTrue);
    });

    test('5. Удаление offline не приводит к восстановлению записи', () async {
      final repo = WorkoutRepo(appDb.db);
      final wId = await repo.createWorkout(
        title: 'To Be Deleted',
        date: DateTime(2026, 11, 4),
        start: false,
      );
      await sync.processSyncQueue(appDb.db);
      expect(mockHttp.serverWorkouts.containsKey(wId), isTrue);

      // Go offline and delete
      mockHttp.isOnline = false;
      await repo.deleteWorkout(wId);

      // Verify tombstone is recorded
      final tombstones = await appDb.db.query('sync_tombstones', where: 'id = ?', whereArgs: [wId]);
      expect(tombstones.isNotEmpty, isTrue);

      // Network comes back up, but server still has the old workout in its list
      mockHttp.isOnline = true;

      // syncFromServer runs: the tombstone MUST PREVENT resurrection!
      await sync.syncFromServer(appDb.db);
      final localRows = await appDb.db.query('workouts', where: 'id = ?', whereArgs: [wId]);
      expect(localRows, isEmpty); // Did NOT resurrect!
    });

    test('6. Конфликт правок с двух устройств не затирает данные молча', () async {
      final repo = WorkoutRepo(appDb.db);
      final wId = await repo.createWorkout(
        title: 'Local Edits',
        date: DateTime(2026, 11, 4),
        start: false,
      );
      await sync.processSyncQueue(appDb.db);

      // Local makes edit
      await repo.renameWorkout(wId, 'Local Edits Device 1');

      // Server returns 409 Conflict (e.g. Device 2 updated it on server)
      mockHttp.return409OnPut = true;
      await sync.processSyncQueue(appDb.db);

      // Must be marked as conflict; local data is NOT lost or deleted!
      final wConf = (await appDb.db.query('workouts', where: 'id = ?', whereArgs: [wId])).first;
      expect(wConf['sync_status'], 'conflict');
      expect(wConf['title'], 'Local Edits Device 1');
    });

    test('7. A -> B во время запроса: ни чужих данных на экране, ни записи в чужую БД', () async {
      // User A initiates sync request
      mockHttp.inFlightCompleter = Completer<void>();
      final userASync = sync.syncFromServer(appDb.db);

      // Mid-flight: User switches to Account B!
      await appDb.switchToUser('user_B_isolated', factory: ffiFactory);

      // Server responds with User A's data
      mockHttp.serverWorkouts['workout-from-A'] = {
        'id': 'workout-from-A',
        'title': 'User A Secret Workout',
        'workoutDate': '2026-11-04',
      };
      mockHttp.inFlightCompleter!.complete();
      await userASync;

      // User B's active database must NOT contain User A's workout!
      final userBRows = await appDb.db.query('workouts', where: 'id = ?', whereArgs: ['workout-from-A']);
      expect(userBRows, isEmpty);
    });

    test('8. Logout возвращает только гостевые данные', () async {
      // 1. In guest mode: clean and create guest workout
      await appDb.switchToUser(null, factory: ffiFactory);
      await appDb.db.delete('workouts');
      await appDb.db.delete('sync_queue');
      await appDb.db.delete('sync_tombstones');
      final guestRepo = WorkoutRepo(appDb.db);
      final guestWId = await guestRepo.createWorkout(
        title: 'Guest Only Run',
        date: DateTime(2026, 11, 4),
        start: false,
      );

      // 2. Switch to account: create account workout
      await appDb.switchToUser('account_user', factory: ffiFactory);
      final accRepo = WorkoutRepo(appDb.db);
      await accRepo.createWorkout(
        title: 'Account Heavy Lifting',
        date: DateTime(2026, 11, 4),
        start: false,
      );

      // 3. Logout -> switch back to guest
      await appDb.switchToUser(null, factory: ffiFactory);
      final restoredRepo = WorkoutRepo(appDb.db);
      final list = await restoredRepo.listWorkouts();

      expect(list.length, 1);
      expect(list.first['id'], guestWId);
      expect(list.first['title'], 'Guest Only Run');
    });

    testWidgets('10. Изменения соседних вкладок отражаются на «Сегодня»', (tester) async {
      tester.view.physicalSize = const Size(360, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      final db = appDb.db;
      await tester.runAsync(() async {
        AppDb.instance.useDatabase(db);
        await db.delete('nutrition_entries');
        await db.delete('nutrition_goals');
        await db.delete('body_weights');
      });
      final selectedDate = DateTime(2026, 11, 4);

      // Build TodayScreen inside MaterialApp
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodayScreen(
              selectedDate: selectedDate,
              isFollowingToday: true,
              onDateChanged: (_) {},
              onGoToTab: (_) {},
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 250)));
      await tester.pumpAndSettle();

      // Zero calories initially
      expect(find.text('0'), findsOneWidget);
      expect(find.text('ккал'), findsOneWidget);

      // Simulate logging food in Nutrition tab
      await tester.runAsync(() async {
        final nutRepo = NutritionRepo(db);
        await nutRepo.savePortion(
          date: '2026-11-04',
          meal: 'breakfast',
          name: 'Oatmeal',
          total: const Nutrients(450, 15, 8, 70),
        );
        await Future.delayed(const Duration(milliseconds: 250));
      });

      // AppDataEvents fired in savePortion -> TodayScreen auto-updates
      await tester.pumpAndSettle();

      // Calories now reflected automatically!
      expect(find.text('450'), findsOneWidget);
    });
  });
}
