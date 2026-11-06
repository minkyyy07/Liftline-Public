import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:liftline_app/auth/api_client.dart';
import 'package:liftline_app/auth/auth_service.dart';
import 'package:liftline_app/auth/token_storage.dart';
import 'package:liftline_app/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DelayedTokenStorage extends InMemoryTokenStorage {
  Completer<void>? accessWriteStarted;
  Completer<void>? accessWriteGate;
  Completer<void>? refreshWriteStarted;
  Completer<void>? refreshWriteGate;
  Completer<void>? clearStarted;
  Completer<void>? clearGate;

  @override
  Future<void> setTokens(String? accessToken, String? refreshToken) async {
    final accessGate = accessWriteGate;
    if (accessGate != null) {
      accessWriteGate = null;
      accessWriteStarted?.complete();
      await accessGate.future;
    }
    await setAccessToken(accessToken);

    final refreshGate = refreshWriteGate;
    if (refreshGate != null) {
      refreshWriteGate = null;
      refreshWriteStarted?.complete();
      await refreshGate.future;
    }
    await setRefreshToken(refreshToken);
  }

  @override
  Future<void> clearAll() async {
    final gate = clearGate;
    if (gate != null) {
      clearGate = null;
      clearStarted?.complete();
      await gate.future;
    }
    await super.clearAll();
  }
}

class ControlledHttpClient extends http.BaseClient {
  final Map<String, List<Future<http.Response>>> queuedResponses = {};
  final Map<String, Completer<void>> started = {};
  final List<http.BaseRequest> executedRequests = [];

  void enqueue(String method, String path, Future<http.Response> response) {
    queuedResponses.putIfAbsent('$method:$path', () => []).add(response);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    executedRequests.add(request);
    final key = '${request.method}:${request.url.path}';
    final signal = started[key];
    if (signal != null && !signal.isCompleted) signal.complete();

    final queued = queuedResponses[key];
    final response =
        queued != null && queued.isNotEmpty
            ? await queued.removeAt(0)
            : http.Response(
              '{}',
              200,
              headers: {'content-type': 'application/json'},
            );
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }

  http.Response jsonResponse(int statusCode, Map<String, Object?> body) {
    return http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  }
}

class NoopAppDb extends AppDb {
  NoopAppDb() : super.isolated();

  @override
  Future<void> switchToUser(String? userId, {DatabaseFactory? factory}) async {}
}

Future<int?> commitSession(
  ApiClient apiClient, {
  required String accountId,
  required String accessToken,
  required String refreshToken,
  int? expectedGeneration,
}) async {
  final generation = expectedGeneration ?? apiClient.reserveSessionChange();
  final committed = await apiClient.commitLoginSession(
    expectedGeneration: generation,
    accountId: accountId,
    accessToken: accessToken,
    refreshToken: refreshToken,
    email: '$accountId@example.com',
    displayName: accountId,
  );
  return committed;
}

Future<void> expectAccountBTokens(DelayedTokenStorage storage) async {
  expect(await storage.getAccessToken(), 'access-B');
  expect(await storage.getRefreshToken(), 'refresh-B');
  expect(await storage.getUserId(), 'B');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('ApiClient session token race protection', () {
    late DelayedTokenStorage storage;
    late ControlledHttpClient httpClient;
    late ApiClient apiClient;
    var sessionExpiredCallbacks = 0;

    setUp(() {
      storage = DelayedTokenStorage();
      httpClient = ControlledHttpClient();
      sessionExpiredCallbacks = 0;
      apiClient = ApiClient(
        baseUrl: 'http://test-server',
        tokenStorage: storage,
        client: httpClient,
        onSessionExpired: () => sessionExpiredCallbacks++,
      );
    });

    test(
      'A -> B while access-token write is pending keeps B pair and header',
      () async {
        storage.accessWriteStarted = Completer<void>();
        final accessGate = Completer<void>();
        storage.accessWriteGate = accessGate;

        final generationA = apiClient.reserveSessionChange();
        final commitA = commitSession(
          apiClient,
          accountId: 'A',
          accessToken: 'access-A',
          refreshToken: 'refresh-A',
          expectedGeneration: generationA,
        );
        await storage.accessWriteStarted!.future;

        final generationB = apiClient.reserveSessionChange();
        final commitB = commitSession(
          apiClient,
          accountId: 'B',
          accessToken: 'access-B',
          refreshToken: 'refresh-B',
          expectedGeneration: generationB,
        );
        accessGate.complete();

        expect(await commitA, isNull);
        await commitB;
        await expectAccountBTokens(storage);

        await apiClient.request(method: 'GET', endpoint: '/api/protected');
        expect(
          httpClient.executedRequests.last.headers['authorization'],
          'Bearer access-B',
        );
        expect(sessionExpiredCallbacks, 0);
      },
    );

    test(
      'A -> B while refresh-token write is pending keeps B pair and header',
      () async {
        storage.refreshWriteStarted = Completer<void>();
        final refreshGate = Completer<void>();
        storage.refreshWriteGate = refreshGate;

        final generationA = apiClient.reserveSessionChange();
        final commitA = commitSession(
          apiClient,
          accountId: 'A',
          accessToken: 'access-A',
          refreshToken: 'refresh-A',
          expectedGeneration: generationA,
        );
        await storage.refreshWriteStarted!.future;

        final generationB = apiClient.reserveSessionChange();
        final commitB = commitSession(
          apiClient,
          accountId: 'B',
          accessToken: 'access-B',
          refreshToken: 'refresh-B',
          expectedGeneration: generationB,
        );
        refreshGate.complete();

        expect(await commitA, isNull);
        await commitB;
        await expectAccountBTokens(storage);

        await apiClient.request(method: 'GET', endpoint: '/api/protected');
        expect(
          httpClient.executedRequests.last.headers['authorization'],
          'Bearer access-B',
        );
        expect(sessionExpiredCallbacks, 0);
      },
    );

    test(
      'A refresh -> B while access-token write is pending keeps B pair',
      () async {
        await storage.setTokens('expired-A', 'refresh-A');
        apiClient.switchSession('A');
        storage.accessWriteStarted = Completer<void>();
        final accessGate = Completer<void>();
        storage.accessWriteGate = accessGate;
        httpClient.enqueue(
          'GET',
          '/api/protected',
          Future.value(http.Response('{"error":"expired"}', 401)),
        );
        httpClient.enqueue(
          'POST',
          '/api/auth/refresh',
          Future.value(
            httpClient.jsonResponse(200, {
              'accessToken': 'access-A-refreshed',
              'refreshToken': 'refresh-A-refreshed',
            }),
          ),
        );

        final oldRequest = apiClient.request(
          method: 'GET',
          endpoint: '/api/protected',
        );
        await storage.accessWriteStarted!.future;
        final generationB = apiClient.reserveSessionChange();
        final commitB = commitSession(
          apiClient,
          accountId: 'B',
          accessToken: 'access-B',
          refreshToken: 'refresh-B',
          expectedGeneration: generationB,
        );
        accessGate.complete();

        await expectLater(oldRequest, throwsA(isA<SessionAbortedException>()));
        await commitB;
        await expectAccountBTokens(storage);
        await apiClient.request(method: 'GET', endpoint: '/api/protected');
        expect(
          httpClient.executedRequests.last.headers['authorization'],
          'Bearer access-B',
        );
      },
    );

    test(
      'A refresh -> B while refresh-token write is pending keeps B pair',
      () async {
        await storage.setTokens('expired-A', 'refresh-A');
        apiClient.switchSession('A');
        storage.refreshWriteStarted = Completer<void>();
        final refreshGate = Completer<void>();
        storage.refreshWriteGate = refreshGate;
        httpClient.enqueue(
          'GET',
          '/api/protected',
          Future.value(http.Response('{"error":"expired"}', 401)),
        );
        httpClient.enqueue(
          'POST',
          '/api/auth/refresh',
          Future.value(
            httpClient.jsonResponse(200, {
              'accessToken': 'access-A-refreshed',
              'refreshToken': 'refresh-A-refreshed',
            }),
          ),
        );

        final oldRequest = apiClient.request(
          method: 'GET',
          endpoint: '/api/protected',
        );
        await storage.refreshWriteStarted!.future;
        final generationB = apiClient.reserveSessionChange();
        final commitB = commitSession(
          apiClient,
          accountId: 'B',
          accessToken: 'access-B',
          refreshToken: 'refresh-B',
          expectedGeneration: generationB,
        );
        refreshGate.complete();

        await expectLater(oldRequest, throwsA(isA<SessionAbortedException>()));
        await commitB;
        await expectAccountBTokens(storage);
        await apiClient.request(method: 'GET', endpoint: '/api/protected');
        expect(
          httpClient.executedRequests.last.headers['authorization'],
          'Bearer access-B',
        );
      },
    );

    test(
      'A -> B during clearAll after 401 cannot clear B or invoke expiration callback',
      () async {
        await storage.setTokens('expired-A', 'refresh-A');
        apiClient.switchSession('A');
        storage.clearStarted = Completer<void>();
        final clearGate = Completer<void>();
        storage.clearGate = clearGate;
        httpClient.enqueue(
          'GET',
          '/api/protected',
          Future.value(http.Response('{"error":"expired"}', 401)),
        );
        httpClient.enqueue(
          'POST',
          '/api/auth/refresh',
          Future.value(http.Response('{"error":"invalid"}', 401)),
        );

        final oldRequest = apiClient.request(
          method: 'GET',
          endpoint: '/api/protected',
        );
        final oldRequestFailure = expectLater(
          oldRequest,
          throwsA(isA<SessionAbortedException>()),
        );
        await storage.clearStarted!.future;

        final generationB = apiClient.reserveSessionChange();
        final commitB = commitSession(
          apiClient,
          accountId: 'B',
          accessToken: 'access-B',
          refreshToken: 'refresh-B',
          expectedGeneration: generationB,
        );
        clearGate.complete();

        await oldRequestFailure;
        await commitB;
        await expectAccountBTokens(storage);
        expect(sessionExpiredCallbacks, 0);

        await apiClient.request(method: 'GET', endpoint: '/api/protected');
        expect(
          httpClient.executedRequests.last.headers['authorization'],
          'Bearer access-B',
        );
      },
    );

    test(
      'late refresh success after A -> B cannot overwrite or authenticate with A',
      () async {
        await storage.setTokens('expired-A', 'refresh-A');
        apiClient.switchSession('A');
        final refreshStarted = Completer<void>();
        httpClient.started['POST:/api/auth/refresh'] = refreshStarted;
        final refreshResponse = Completer<http.Response>();
        httpClient.enqueue(
          'GET',
          '/api/protected',
          Future.value(http.Response('{"error":"expired"}', 401)),
        );
        httpClient.enqueue('POST', '/api/auth/refresh', refreshResponse.future);

        final oldRequest = apiClient.request(
          method: 'GET',
          endpoint: '/api/protected',
        );
        await refreshStarted.future;

        final generationB = apiClient.reserveSessionChange();
        await commitSession(
          apiClient,
          accountId: 'B',
          accessToken: 'access-B',
          refreshToken: 'refresh-B',
          expectedGeneration: generationB,
        );
        refreshResponse.complete(
          httpClient.jsonResponse(200, {
            'accessToken': 'access-A-refreshed',
            'refreshToken': 'refresh-A-refreshed',
          }),
        );

        await expectLater(oldRequest, throwsA(isA<SessionAbortedException>()));
        await expectAccountBTokens(storage);
        expect(sessionExpiredCallbacks, 0);
        await apiClient.request(method: 'GET', endpoint: '/api/protected');
        expect(
          httpClient.executedRequests.last.headers['authorization'],
          'Bearer access-B',
        );
      },
    );

    test(
      'ordinary refresh commits the new pair and retries with the new access token',
      () async {
        await storage.setTokens('expired-A', 'refresh-A');
        apiClient.switchSession('A');
        httpClient.enqueue(
          'GET',
          '/api/protected',
          Future.value(http.Response('{"error":"expired"}', 401)),
        );
        httpClient.enqueue(
          'POST',
          '/api/auth/refresh',
          Future.value(
            httpClient.jsonResponse(200, {
              'accessToken': 'access-A-new',
              'refreshToken': 'refresh-A-new',
            }),
          ),
        );

        await apiClient.request(method: 'GET', endpoint: '/api/protected');

        expect(await storage.getAccessToken(), 'access-A-new');
        expect(await storage.getRefreshToken(), 'refresh-A-new');
        expect(
          httpClient.executedRequests.last.headers['authorization'],
          'Bearer access-A-new',
        );
        expect(sessionExpiredCallbacks, 0);
      },
    );

    test('ordinary logout clears only the logged-in session', () async {
      await storage.setTokens('access-A', 'refresh-A');
      apiClient.switchSession('A');
      final authService = AuthService.forTest(
        tokenStorage: storage,
        apiClient: apiClient,
        appDb: NoopAppDb(),
      );

      await authService.logout();

      expect(await storage.getAccessToken(), isNull);
      expect(await storage.getRefreshToken(), isNull);
      expect(apiClient.sessionAccountId, isNull);
      expect(sessionExpiredCallbacks, 0);
      expect(
        httpClient.executedRequests.single.headers['authorization'],
        'Bearer access-A',
      );
    });

    test(
      'late logout response from A cannot clear B or invoke expiration callback',
      () async {
        await storage.setTokens('access-A', 'refresh-A');
        apiClient.switchSession('A');
        final logoutStarted = Completer<void>();
        httpClient.started['POST:/api/auth/logout'] = logoutStarted;
        final logoutResponse = Completer<http.Response>();
        httpClient.enqueue('POST', '/api/auth/logout', logoutResponse.future);
        final authService = AuthService.forTest(
          tokenStorage: storage,
          apiClient: apiClient,
          appDb: NoopAppDb(),
        );

        final logout = authService.logout();
        await logoutStarted.future;
        final generationB = apiClient.reserveSessionChange();
        await commitSession(
          apiClient,
          accountId: 'B',
          accessToken: 'access-B',
          refreshToken: 'refresh-B',
          expectedGeneration: generationB,
        );
        logoutResponse.complete(http.Response('{}', 200));

        await logout;
        await expectAccountBTokens(storage);
        expect(apiClient.sessionAccountId, 'B');
        expect(sessionExpiredCallbacks, 0);
        await apiClient.request(method: 'GET', endpoint: '/api/protected');
        expect(
          httpClient.executedRequests.last.headers['authorization'],
          'Bearer access-B',
        );
      },
    );

    test(
      'failed B login logs out safely if A token cleanup finishes afterward',
      () async {
        await storage.setTokens('access-A', 'refresh-A');
        await storage.setUserId('A');
        await storage.setUserEmail('A@example.com');
        apiClient.switchSession('A');
        final authService = AuthService.forTest(
          tokenStorage: storage,
          apiClient: apiClient,
          appDb: NoopAppDb(),
        );
        await authService.init();

        storage.clearStarted = Completer<void>();
        final clearGate = Completer<void>();
        storage.clearGate = clearGate;
        httpClient.enqueue(
          'GET',
          '/api/protected',
          Future.value(http.Response('{"error":"expired"}', 401)),
        );
        httpClient.enqueue(
          'POST',
          '/api/auth/refresh',
          Future.value(http.Response('{"error":"invalid"}', 401)),
        );
        httpClient.enqueue(
          'POST',
          '/api/auth/login',
          Future.value(http.Response('{"error":"bad credentials"}', 401)),
        );
        final loginStarted = Completer<void>();
        httpClient.started['POST:/api/auth/login'] = loginStarted;

        final oldRequest = apiClient.request(
          method: 'GET',
          endpoint: '/api/protected',
        );
        final clearRaceRequestFailure = expectLater(
          oldRequest,
          throwsA(isA<SessionAbortedException>()),
        );
        await storage.clearStarted!.future;
        final failedLogin = authService.login(
          'b@example.com',
          'wrong-password',
        );
        await loginStarted.future;
        clearGate.complete();
        await expectLater(
          failedLogin,
          throwsA(anyOf(isA<ApiException>(), isA<SessionAbortedException>())),
        );
        await clearRaceRequestFailure;

        expect(authService.isAuthenticated, isFalse);
        expect(authService.user, isNull);
        expect(apiClient.sessionAccountId, isNull);
        expect(await storage.getAccessToken(), isNull);
        expect(await storage.getRefreshToken(), isNull);
        expect(authService.errorMessage, contains('сессия завершена'));
        await apiClient.request(method: 'GET', endpoint: '/api/protected');
        expect(
          httpClient.executedRequests.last.headers.containsKey('authorization'),
          isFalse,
        );
      },
    );

    test(
      'failed B login restores A after its delayed refresh-token update',
      () async {
        await storage.setTokens('expired-A', 'refresh-A');
        await storage.setUserId('A');
        await storage.setUserEmail('A@example.com');
        apiClient.switchSession('A');
        final authService = AuthService.forTest(
          tokenStorage: storage,
          apiClient: apiClient,
          appDb: NoopAppDb(),
        );
        await authService.init();

        storage.refreshWriteStarted = Completer<void>();
        final refreshGate = Completer<void>();
        storage.refreshWriteGate = refreshGate;
        httpClient.enqueue(
          'GET',
          '/api/protected',
          Future.value(http.Response('{"error":"expired"}', 401)),
        );
        httpClient.enqueue(
          'POST',
          '/api/auth/refresh',
          Future.value(
            httpClient.jsonResponse(200, {
              'accessToken': 'access-A-refreshed',
              'refreshToken': 'refresh-A-refreshed',
            }),
          ),
        );
        httpClient.enqueue(
          'POST',
          '/api/auth/login',
          Future.value(http.Response('{"error":"bad credentials"}', 401)),
        );
        final loginStarted = Completer<void>();
        httpClient.started['POST:/api/auth/login'] = loginStarted;

        final oldRequest = apiClient.request(
          method: 'GET',
          endpoint: '/api/protected',
        );
        final oldRequestFailure = expectLater(
          oldRequest,
          throwsA(isA<SessionAbortedException>()),
        );
        await storage.refreshWriteStarted!.future;
        final failedLogin = authService.login(
          'b@example.com',
          'wrong-password',
        );
        await loginStarted.future;
        refreshGate.complete();
        await expectLater(
          failedLogin,
          throwsA(anyOf(isA<ApiException>(), isA<SessionAbortedException>())),
        );
        await oldRequestFailure;

        expect(authService.isAuthenticated, isTrue);
        expect(authService.user?.id, 'A');
        expect(apiClient.sessionAccountId, 'A');
        expect(await storage.getAccessToken(), 'access-A-refreshed');
        expect(await storage.getRefreshToken(), 'refresh-A-refreshed');
        await apiClient.request(method: 'GET', endpoint: '/api/protected');
        expect(
          httpClient.executedRequests.last.headers['authorization'],
          isNotNull,
        );
      },
    );
  });
}
