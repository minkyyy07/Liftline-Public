import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:liftline_app/auth/api_client.dart';
import 'package:liftline_app/auth/auth_service.dart';
import 'package:liftline_app/auth/cloud_workout_sync.dart';
import 'package:liftline_app/auth/sync_queue_runner.dart';
import 'package:liftline_app/auth/token_storage.dart';
import 'package:liftline_app/db.dart';
import 'package:liftline_app/repo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class GatedDatabaseFactory implements DatabaseFactory {
  GatedDatabaseFactory(this.delegate);

  final DatabaseFactory delegate;
  final Map<String, Completer<void>> openGates = {};
  final Map<String, Completer<void>> openStarted = {};
  final Set<String> failOnOpen = {};

  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    for (final userId in openGates.keys.toList()) {
      if (!path.endsWith('liftline_user_$userId.db')) continue;
      final started = openStarted[userId]!;
      if (!started.isCompleted) started.complete();
      await openGates.remove(userId)!.future;
      if (failOnOpen.remove(userId)) {
        throw StateError('Controlled database open failure for $userId');
      }
      break;
    }
    return delegate.openDatabase(path, options: options);
  }

  @override
  Future<String> getDatabasesPath() => delegate.getDatabasesPath();

  @override
  Future<void> setDatabasesPath(String path) => delegate.setDatabasesPath(path);

  @override
  Future<void> deleteDatabase(String path) => delegate.deleteDatabase(path);

  @override
  Future<bool> databaseExists(String path) => delegate.databaseExists(path);

  @override
  Future<void> writeDatabaseBytes(String path, Uint8List bytes) =>
      delegate.writeDatabaseBytes(path, bytes);

  @override
  Future<Uint8List> readDatabaseBytes(String path) =>
      delegate.readDatabaseBytes(path);
}

class ControlledAppDb extends AppDb {
  ControlledAppDb(this.controlledFactory) : super.isolated();

  final DatabaseFactory controlledFactory;

  @override
  Future<void> switchToUser(String? userId, {DatabaseFactory? factory}) =>
      super.switchToUser(userId, factory: controlledFactory);
}

class LoginHttpClient extends http.BaseClient {
  final Map<String, List<http.Response>> _responses = {};
  final List<http.BaseRequest> requests = [];
  Completer<void>? loginResponseDelivered;
  Completer<void>? workoutRequestStarted;
  Completer<void>? workoutResponseGate;

  void enqueue(
    String method,
    String path,
    Map<String, Object?> body, {
    int statusCode = 200,
  }) {
    _responses
        .putIfAbsent('$method:$path', () => [])
        .add(
          http.Response(
            jsonEncode(body),
            statusCode,
            headers: {'content-type': 'application/json'},
          ),
        );
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (request.method == 'POST' && request.url.path == '/api/auth/login') {
      final delivered = loginResponseDelivered;
      if (delivered != null && !delivered.isCompleted) delivered.complete();
    }
    if (request.method == 'POST' && request.url.path == '/api/workouts') {
      final started = workoutRequestStarted;
      if (started != null && !started.isCompleted) started.complete();
      final gate = workoutResponseGate;
      if (gate != null) {
        await gate.future;
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'id': 'server-workout'}))),
          201,
          headers: {'content-type': 'application/json'},
        );
      }
    }
    final responses = _responses['${request.method}:${request.url.path}'];
    final response =
        responses != null && responses.isNotEmpty
            ? responses.removeAt(0)
            : http.Response('{}', 200);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

class DelayedLoginTokenStorage extends InMemoryTokenStorage {
  Completer<void>? accessWriteStarted;
  Completer<void>? accessWriteGate;

  @override
  Future<void> setTokens(String? accessToken, String? refreshToken) async {
    await setAccessToken(accessToken);
    final gate = accessWriteGate;
    if (gate != null) {
      accessWriteGate = null;
      accessWriteStarted?.complete();
      await gate.future;
    }
    await setRefreshToken(refreshToken);
  }
}

class TrackingCloudWorkoutSync extends CloudWorkoutSync {
  TrackingCloudWorkoutSync({
    required super.apiClient,
    required super.authService,
    required super.appDb,
  });

  final Completer<void> started = Completer<void>();
  final Completer<void> finished = Completer<void>();

  @override
  Future<void> processSyncQueue(Database db) async {
    if (!started.isCompleted) started.complete();
    try {
      await super.processSyncQueue(db);
    } finally {
      if (!finished.isCompleted) finished.complete();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tempDir;
  late GatedDatabaseFactory factory;
  late AppDb appDb;
  late DelayedLoginTokenStorage storage;
  late ApiClient apiClient;
  late AuthService authService;
  late LoginHttpClient httpClient;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('liftspire_auth_switch_');
    await databaseFactoryFfi.setDatabasesPath(tempDir.path);
    factory = GatedDatabaseFactory(databaseFactoryFfi);

    appDb = ControlledAppDb(factory);
    storage = DelayedLoginTokenStorage();
    httpClient = LoginHttpClient();
    await storage.setTokens('access-A', 'refresh-A');
    await storage.setUserId('A');
    await storage.setUserEmail('A@example.com');
    apiClient = ApiClient(
      baseUrl: 'http://test-server',
      tokenStorage: storage,
      client: httpClient,
    );
    authService = AuthService.forTest(
      tokenStorage: storage,
      apiClient: apiClient,
      appDb: appDb,
    );
    await authService.init();
  });

  tearDown(() async {
    if (appDb.isOpen) await appDb.db.close();
    await tempDir.delete(recursive: true);
  });

  void enqueueLogin(String accountId, {int statusCode = 200}) {
    httpClient.enqueue('POST', '/api/auth/login', {
      'accessToken': 'access-$accountId',
      'refreshToken': 'refresh-$accountId',
      'userId': accountId,
      'email': '$accountId@example.com',
    }, statusCode: statusCode);
  }

  test(
    'successful A to B login switches tokens and SQLite data together',
    () async {
      final workoutA = await WorkoutRepo(appDb.db).createWorkout(
        title: 'Private A',
        date: DateTime(2026, 11, 6),
        start: false,
      );
      enqueueLogin('B');

      await authService.login('b@example.com', 'password');

      expect(apiClient.sessionAccountId, 'B');
      expect(authService.user?.id, 'B');
      expect(appDb.currentUserId, 'B');
      expect(await storage.getAccessToken(), 'access-B');
      expect(await storage.getRefreshToken(), 'refresh-B');
      expect(await WorkoutRepo(appDb.db).listWorkouts(), isEmpty);

      final workoutB = await WorkoutRepo(appDb.db).createWorkout(
        title: 'Private B',
        date: DateTime(2026, 11, 6),
        start: false,
      );
      final databaseA = await openLiftlineDb(
        '${tempDir.path}/liftline_user_A.db',
        factory: databaseFactoryFfi,
      );
      final workoutsA = await WorkoutRepo(databaseA).listWorkouts();
      await databaseA.close();
      expect(workoutsA.map((workout) => workout['id']), contains(workoutA));
      expect(
        workoutsA.map((workout) => workout['id']),
        isNot(contains(workoutB)),
      );
    },
  );

  test(
    'out-of-order SQLite opens leave the latest session and its data active',
    () async {
      final workoutA = await WorkoutRepo(appDb.db).createWorkout(
        title: 'Private A',
        date: DateTime(2026, 11, 6),
        start: false,
      );
      final databaseB = await openLiftlineDb(
        '${tempDir.path}/liftline_user_B.db',
        factory: databaseFactoryFfi,
      );
      final workoutB = await WorkoutRepo(databaseB).createWorkout(
        title: 'Private B',
        date: DateTime(2026, 11, 6),
        start: false,
      );
      await databaseB.close();

      final gateB = Completer<void>();
      factory.openGates['B'] = gateB;
      factory.openStarted['B'] = Completer<void>();
      enqueueLogin('B');
      final loginB = authService.login('b@example.com', 'password');
      await factory.openStarted['B']!.future;

      enqueueLogin('C');
      await authService.login('c@example.com', 'password');
      expect(apiClient.sessionAccountId, 'C');
      expect(authService.user?.id, 'C');
      expect(appDb.currentUserId, 'C');

      final workoutC = await WorkoutRepo(appDb.db).createWorkout(
        title: 'Private C',
        date: DateTime(2026, 11, 6),
        start: false,
      );
      gateB.complete();
      await expectLater(loginB, throwsA(isA<SessionAbortedException>()));

      expect(apiClient.sessionAccountId, 'C');
      expect(authService.user?.id, 'C');
      expect(appDb.currentUserId, 'C');
      final activeWorkouts = await WorkoutRepo(appDb.db).listWorkouts();
      expect(
        activeWorkouts.map((workout) => workout['id']),
        contains(workoutC),
      );
      expect(
        activeWorkouts.map((workout) => workout['id']),
        isNot(contains(workoutA)),
      );
      expect(
        activeWorkouts.map((workout) => workout['id']),
        isNot(contains(workoutB)),
      );
    },
  );

  test(
    'database open failure restores A when its SQLite session is still active',
    () async {
      final workoutA = await WorkoutRepo(appDb.db).createWorkout(
        title: 'Private A',
        date: DateTime(2026, 11, 6),
        start: false,
      );
      final gateB = Completer<void>();
      factory.openGates['B'] = gateB;
      factory.openStarted['B'] = Completer<void>();
      factory.failOnOpen.add('B');
      enqueueLogin('B');

      final loginB = authService.login('b@example.com', 'password');
      await factory.openStarted['B']!.future;
      gateB.complete();
      await expectLater(loginB, throwsA(isA<StateError>()));

      expect(authService.isAuthenticated, isTrue);
      expect(authService.user?.id, 'A');
      expect(apiClient.sessionAccountId, 'A');
      expect(await storage.getAccessToken(), 'access-A');
      expect(await storage.getRefreshToken(), 'refresh-A');
      expect(appDb.currentUserId, 'A');
      expect(appDb.isOpen, isTrue);
      final workoutsA = await WorkoutRepo(appDb.db).listWorkouts();
      expect(workoutsA.map((workout) => workout['id']), contains(workoutA));
    },
  );

  test(
    'logout during an account database open cannot restore that account later',
    () async {
      final databaseB = await openLiftlineDb(
        '${tempDir.path}/liftline_user_B.db',
        factory: databaseFactoryFfi,
      );
      await WorkoutRepo(databaseB).createWorkout(
        title: 'Private B',
        date: DateTime(2026, 11, 6),
        start: false,
      );
      await databaseB.close();

      final gateB = Completer<void>();
      factory.openGates['B'] = gateB;
      factory.openStarted['B'] = Completer<void>();
      enqueueLogin('B');

      final loginB = authService.login('b@example.com', 'password');
      await factory.openStarted['B']!.future;
      await authService.logout();
      expect(apiClient.sessionAccountId, isNull);
      expect(appDb.currentUserId, isNull);

      gateB.complete();
      await expectLater(loginB, throwsA(isA<SessionAbortedException>()));

      expect(authService.isAuthenticated, isFalse);
      expect(apiClient.sessionAccountId, isNull);
      expect(appDb.currentUserId, isNull);
      expect(await storage.getAccessToken(), isNull);
      expect(await WorkoutRepo(appDb.db).listWorkouts(), isEmpty);
    },
  );

  test(
    'a failed overlapping login cannot leave delayed B token writes active',
    () async {
      final workoutA = await WorkoutRepo(appDb.db).createWorkout(
        title: 'Private A',
        date: DateTime(2026, 11, 6),
        start: false,
      );
      final writeGate = Completer<void>();
      storage.accessWriteStarted = Completer<void>();
      storage.accessWriteGate = writeGate;

      enqueueLogin('B');
      final loginB = authService.login('b@example.com', 'password');
      await storage.accessWriteStarted!.future;

      enqueueLogin('C', statusCode: 401);
      httpClient.loginResponseDelivered = Completer<void>();
      final loginC = authService.login('c@example.com', 'wrong-password');
      await httpClient.loginResponseDelivered!.future;
      writeGate.complete();

      await expectLater(loginB, throwsA(isA<SessionAbortedException>()));
      await expectLater(loginC, throwsA(isA<ApiException>()));

      expect(authService.isAuthenticated, isFalse);
      expect(authService.user, isNull);
      expect(apiClient.sessionAccountId, isNull);
      expect(appDb.currentUserId, isNull);
      expect(await storage.getAccessToken(), isNull);
      expect(await storage.getRefreshToken(), isNull);
      expect(authService.errorMessage, contains('войдите снова'));

      await apiClient.request(method: 'GET', endpoint: '/api/protected');
      final protectedRequest = httpClient.requests.last;
      expect(protectedRequest.url.path, '/api/protected');
      expect(protectedRequest.headers.containsKey('authorization'), isFalse);

      final databaseA = await openLiftlineDb(
        '${tempDir.path}/liftline_user_A.db',
        factory: databaseFactoryFfi,
      );
      expect(
        (await WorkoutRepo(databaseA).listWorkouts()).map((w) => w['id']),
        contains(workoutA),
      );
      await databaseA.close();
    },
  );

  test(
    'background sync pauses while B opens and does not upload A queue with B tokens',
    () async {
      final workoutA = await WorkoutRepo(appDb.db).createWorkout(
        title: 'Private A',
        date: DateTime(2026, 11, 6),
        start: false,
      );
      final gateB = Completer<void>();
      factory.openGates['B'] = gateB;
      factory.openStarted['B'] = Completer<void>();
      enqueueLogin('B');

      final loginB = authService.login('b@example.com', 'password');
      await factory.openStarted['B']!.future;
      expect(apiClient.sessionAccountId, 'B');
      expect(await storage.getAccessToken(), 'access-B');
      expect(appDb.currentUserId, 'A');

      final syncEngine = CloudWorkoutSync(
        apiClient: apiClient,
        authService: authService,
        appDb: appDb,
      );
      final runner = SyncQueueRunner.isolated(
        authService: authService,
        syncEngine: syncEngine,
        appDb: appDb,
      );
      runner.scheduleSync(immediate: true);
      await syncEngine.processSyncQueue(appDb.db);

      expect(
        httpClient.requests.where(
          (request) => request.url.path.startsWith('/api/workouts'),
        ),
        isEmpty,
      );
      expect(await appDb.db.query('sync_queue'), hasLength(1));
      expect(
        (await appDb.db.query('workouts')).single['sync_status'],
        'pending',
      );

      gateB.complete();
      await loginB;
      runner.dispose();

      expect(authService.isAuthenticated, isTrue);
      expect(apiClient.sessionAccountId, 'B');
      expect(appDb.currentUserId, 'B');
      expect(await appDb.db.query('sync_queue'), isEmpty);

      final databaseA = await openLiftlineDb(
        '${tempDir.path}/liftline_user_A.db',
        factory: databaseFactoryFfi,
      );
      expect(
        (await WorkoutRepo(databaseA).listWorkouts()).map((w) => w['id']),
        contains(workoutA),
      );
      expect(await databaseA.query('sync_queue'), hasLength(1));
      await databaseA.close();
    },
  );

  test('in-flight A sync response is discarded after switching to B', () async {
    final workoutA = await WorkoutRepo(appDb.db).createWorkout(
      title: 'Private A',
      date: DateTime(2026, 11, 6),
      start: false,
    );
    final responseGate = Completer<void>();
    httpClient.workoutRequestStarted = Completer<void>();
    httpClient.workoutResponseGate = responseGate;
    final syncEngine = TrackingCloudWorkoutSync(
      apiClient: apiClient,
      authService: authService,
      appDb: appDb,
    );
    final runner = SyncQueueRunner.isolated(
      authService: authService,
      syncEngine: syncEngine,
      appDb: appDb,
    );
    runner.scheduleSync(immediate: true);
    await syncEngine.started.future;
    await httpClient.workoutRequestStarted!.future;
    expect(
      httpClient.requests.last.headers.keys.any(
        (key) => key.toLowerCase() == 'authorization',
      ),
      isTrue,
    );

    final gateB = Completer<void>();
    factory.openGates['B'] = gateB;
    factory.openStarted['B'] = Completer<void>();
    enqueueLogin('B');
    final loginB = authService.login('b@example.com', 'password');
    await factory.openStarted['B']!.future;

    responseGate.complete();
    await syncEngine.finished.future;
    runner.dispose();
    final queueAWhileOpening = await appDb.db.query('sync_queue');
    expect(queueAWhileOpening, hasLength(1));
    expect((await appDb.db.query('workouts')).single['sync_status'], 'pending');

    gateB.complete();
    await loginB;
    expect(appDb.currentUserId, 'B');
    expect(await appDb.db.query('sync_queue'), isEmpty);

    final databaseA = await openLiftlineDb(
      '${tempDir.path}/liftline_user_A.db',
      factory: databaseFactoryFfi,
    );
    expect(
      (await WorkoutRepo(databaseA).listWorkouts()).map((w) => w['id']),
      contains(workoutA),
    );
    expect(await databaseA.query('sync_queue'), hasLength(1));
    expect(
      (await databaseA.query('workouts')).single['sync_status'],
      'pending',
    );
    await databaseA.close();
  });
}
