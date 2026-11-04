import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:liftline_app/auth/api_client.dart';
import 'package:liftline_app/auth/auth_service.dart';
import 'package:liftline_app/auth/login_screen.dart';
import 'package:liftline_app/auth/profile_screen.dart';
import 'package:liftline_app/auth/register_screen.dart';
import 'package:liftline_app/auth/token_storage.dart';
import 'package:liftline_app/db.dart';
import 'package:liftline_app/repo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockHttpClient extends http.BaseClient {
  int refreshCallCount = 0;
  int protectedCallCount = 0;
  bool shouldFailRefresh = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;

    if (path.endsWith('/api/auth/refresh')) {
      refreshCallCount++;
      if (shouldFailRefresh) {
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'error': 'Invalid refresh token'}))),
          401,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({
          'accessToken': 'new_access_token',
          'refreshToken': 'new_refresh_token',
          'expiresIn': 900,
        }))),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    if (path.endsWith('/api/workouts')) {
      protectedCallCount++;
      final authHeader = request.headers['authorization'] ?? '';
      if (!authHeader.contains('new_access_token')) {
        // First attempt with old/expired token triggers 401
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'error': 'Token expired'}))),
          401,
          headers: {'content-type': 'application/json'},
        );
      }
      // Retry with new token succeeds
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode([]))),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    if (path.endsWith('/api/auth/login')) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({
          'accessToken': 'jwt_access_123',
          'refreshToken': 'refresh_xyz',
          'userId': 'uuid-user-a',
          'email': 'user@example.com',
          'displayName': 'Alex',
        }))),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    if (path.endsWith('/api/auth/logout')) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'message': 'Logged out successfully'}))),
        200,
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

  group('TokenStorage & ApiClient Concurrent Refresh', () {
    test('TokenStorage stores and clears tokens in memory', () async {
      final storage = InMemoryTokenStorage();
      await storage.setAccessToken('access_1');
      await storage.setRefreshToken('refresh_1');
      await storage.setUserId('user_1');
      await storage.setUserEmail('test@test.com');
      await storage.setUserDisplayName('Tester');

      expect(await storage.getAccessToken(), 'access_1');
      expect(await storage.getRefreshToken(), 'refresh_1');
      expect(await storage.getUserId(), 'user_1');
      expect(await storage.getUserEmail(), 'test@test.com');
      expect(await storage.getUserDisplayName(), 'Tester');

      await storage.clearAll();
      expect(await storage.getAccessToken(), isNull);
      expect(await storage.getRefreshToken(), isNull);
      expect(await storage.getUserId(), isNull);
    });

    test('Parallel requests with expired access token trigger exactly ONE refresh', () async {
      final mockClient = MockHttpClient();
      final storage = InMemoryTokenStorage();
      await storage.setAccessToken('expired_access_token');
      await storage.setRefreshToken('valid_refresh_token');

      final apiClient = ApiClient(
        baseUrl: 'http://test.local',
        tokenStorage: storage,
        client: mockClient,
      );

      // Launch 5 parallel requests that all hit 401 simultaneously
      final futures = List.generate(
        5,
        (_) => apiClient.request(method: 'GET', endpoint: '/api/workouts'),
      );

      final results = await Future.wait(futures);

      // All 5 requests succeeded
      expect(results.length, 5);

      // Exactly ONE call to /api/auth/refresh was made
      expect(mockClient.refreshCallCount, 1);

      // Tokens in storage updated
      expect(await storage.getAccessToken(), 'new_access_token');
      expect(await storage.getRefreshToken(), 'new_refresh_token');
    });

    test('Failed refresh clears tokens and triggers onSessionExpired without infinite loop', () async {
      final mockClient = MockHttpClient();
      mockClient.shouldFailRefresh = true;

      final storage = InMemoryTokenStorage();
      await storage.setAccessToken('expired_token');
      await storage.setRefreshToken('revoked_refresh_token');

      bool sessionExpiredFired = false;
      final apiClient = ApiClient(
        baseUrl: 'http://test.local',
        tokenStorage: storage,
        client: mockClient,
        onSessionExpired: () => sessionExpiredFired = true,
      );

      await expectLater(
        () => apiClient.request(method: 'GET', endpoint: '/api/workouts'),
        throwsA(isA<ApiException>()),
      );

      // Tokens wiped
      expect(await storage.getAccessToken(), isNull);
      expect(await storage.getRefreshToken(), isNull);
      expect(sessionExpiredFired, isTrue);
    });
  });

  group('Local Database Isolation: Guest vs User A vs User B', () {
    test('Workouts and catalogue are 100% physically isolated between Guest, User A, and User B', () async {
      final appDb = AppDb.isolated();
      final nonce = DateTime.now().microsecondsSinceEpoch;
      final userAId = 'user_A_$nonce';
      final userBId = 'user_B_$nonce';

      // 1. GUEST MODE
      await appDb.switchToUser(null, factory: ffiFactory);
      expect(appDb.isGuest, isTrue);

      final guestRepo = WorkoutRepo(appDb.db);
      final initialGuestCount = (await guestRepo.listWorkouts()).length;

      final guestWId = await guestRepo.createWorkout(
        title: 'Guest Morning Run',
        date: DateTime.now(),
        start: false,
      );
      await guestRepo.addExercise(guestWId, 'Pushups');

      expect((await guestRepo.listWorkouts()).length, initialGuestCount + 1);
      expect((await guestRepo.listWorkouts()).map((w) => w['title']), contains('Guest Morning Run'));

      // 2. USER A MODE
      await appDb.switchToUser(userAId, factory: ffiFactory);
      expect(appDb.isGuest, isFalse);
      expect(appDb.currentUserId, userAId);

      final userARepo = WorkoutRepo(appDb.db);
      // User A's DB starts empty (guest data is NOT automatically merged!)
      expect(await userARepo.listWorkouts(), isEmpty);

      final userAWId = await userARepo.createWorkout(
        title: 'User A Heavy Bench',
        date: DateTime.now(),
        start: false,
      );
      await userARepo.addExercise(userAWId, 'Bench Press');

      expect((await userARepo.listWorkouts()).length, 1);
      expect((await userARepo.listWorkouts()).first['title'], 'User A Heavy Bench');

      // 3. USER B MODE
      await appDb.switchToUser(userBId, factory: ffiFactory);
      expect(appDb.isGuest, isFalse);
      expect(appDb.currentUserId, userBId);

      final userBRepo = WorkoutRepo(appDb.db);
      // User B cannot see User A's workout or Guest's workout!
      expect(await userBRepo.listWorkouts(), isEmpty);

      final userBWId = await userBRepo.createWorkout(
        title: 'User B Leg Day',
        date: DateTime.now(),
        start: false,
      );
      await userBRepo.addExercise(userBWId, 'Squat');

      expect((await userBRepo.listWorkouts()).length, 1);
      expect((await userBRepo.listWorkouts()).first['title'], 'User B Leg Day');

      // 4. SWITCH BACK TO GUEST MODE (e.g. on logout)
      await appDb.switchToUser(null, factory: ffiFactory);
      expect(appDb.isGuest, isTrue);

      final restoredGuestRepo = WorkoutRepo(appDb.db);
      final guestList = await restoredGuestRepo.listWorkouts();
      // Neither User A nor User B data leaked into Guest DB!
      expect(guestList.length, initialGuestCount + 1);
      expect(guestList.map((w) => w['title']).toList(), contains('Guest Morning Run'));

      // 5. Explicit guest data copy into User A
      await appDb.switchToUser(userAId, factory: ffiFactory);
      final copiedCount = await appDb.copyGuestDataToCurrentAccount(factory: ffiFactory);
      expect(copiedCount, initialGuestCount + 1);

      final userAAfterImport = await WorkoutRepo(appDb.db).listWorkouts();
      expect(userAAfterImport.length, 1 + initialGuestCount + 1);
      expect(userAAfterImport.map((w) => w['title']).toList(), containsAll(['User A Heavy Bench', 'Guest Morning Run']));

      // User B remains isolated and unaffected
      await appDb.switchToUser(userBId, factory: ffiFactory);
      final userBCheck = await WorkoutRepo(appDb.db).listWorkouts();
      expect(userBCheck.length, 1);
      expect(userBCheck.first['title'], 'User B Leg Day');
    });
  });

  group('AuthService State Flow', () {
    test('Login sets auth state and switches DB; logout clears tokens and switches to guest', () async {
      final mockClient = MockHttpClient();
      final storage = InMemoryTokenStorage();
      final appDb = AppDb.isolated();

      final authService = AuthService.forTest(
        tokenStorage: storage,
        apiClient: ApiClient(baseUrl: 'http://test.local', tokenStorage: storage, client: mockClient),
        appDb: appDb,
      );

      expect(authService.isAuthenticated, isFalse);
      expect(authService.isGuest, isTrue);

      await authService.login('user@example.com', 'password123');

      expect(authService.isAuthenticated, isTrue);
      expect(authService.user?.email, 'user@example.com');
      expect(authService.user?.displayName, 'Alex');
      expect(await storage.getAccessToken(), 'jwt_access_123');
      expect(await storage.getRefreshToken(), 'refresh_xyz');

      // Logout
      await authService.logout();

      expect(authService.isAuthenticated, isFalse);
      expect(authService.isGuest, isTrue);
      expect(authService.user, isNull);
      expect(await storage.getAccessToken(), isNull);
      expect(await storage.getRefreshToken(), isNull);
    });
  });

  group('Auth Widget Tests', () {
    testWidgets('LoginScreen renders inputs and validates email format', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: LoginScreen()),
      );

      expect(find.text('Вход в Liftspire'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2)); // Email & Password
      expect(find.text('Войти'), findsOneWidget);
      expect(find.text('Создать аккаунт'), findsOneWidget);

      // Tap submit with empty fields
      await tester.tap(find.text('Войти'));
      await tester.pumpAndSettle();

      expect(find.text('Введите email'), findsOneWidget);

      // Enter invalid email
      await tester.enterText(find.byType(TextFormField).first, 'invalid-email');
      await tester.tap(find.text('Войти'));
      await tester.pumpAndSettle();

      expect(find.text('Введите корректный email'), findsOneWidget);
    });

    testWidgets('RegisterScreen validates password min length', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: RegisterScreen()),
      );

      expect(find.text('Создание аккаунта'), findsOneWidget);
      expect(find.text('Зарегистрироваться'), findsOneWidget);

      // Enter valid email and short password (5 chars)
      await tester.enterText(find.byType(TextFormField).at(0), 'valid@example.com');
      await tester.enterText(find.byType(TextFormField).at(2), '12345');
      await tester.enterText(find.byType(TextFormField).at(3), '12345');

      await tester.tap(find.text('Зарегистрироваться'));
      await tester.pumpAndSettle();

      expect(find.text('Пароль должен быть не менее 8 символов'), findsOneWidget);
    });

    testWidgets('ProfileScreen renders guest state and account login button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ProfileScreen()),
      );

      expect(find.text('Профиль'), findsOneWidget);
      expect(find.text('Гостевой режим'), findsOneWidget);
      expect(find.text('Данные хранятся только локально'), findsOneWidget);
      expect(find.text('Войти или создать аккаунт'), findsOneWidget);
    });
  });
}
