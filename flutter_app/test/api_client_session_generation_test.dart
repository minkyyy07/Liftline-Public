import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:liftline_app/auth/api_client.dart';
import 'package:liftline_app/auth/token_storage.dart';

class DelayControllableHttpClient extends http.BaseClient {
  final Map<String, Completer<http.Response>> pendingRequests = {};
  final List<http.BaseRequest> executedRequests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    executedRequests.add(request);
    final key = '${request.method}:${request.url.path}';

    if (pendingRequests.containsKey(key)) {
      final res = await pendingRequests[key]!.future;
      return http.StreamedResponse(
        Stream.value(res.bodyBytes),
        res.statusCode,
        headers: res.headers,
      );
    }

    return http.StreamedResponse(
      Stream.value(utf8.encode('{}')),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  group('ApiClient Session Generation & Isolation Tests', () {
    late InMemoryTokenStorage tokenStorage;
    late DelayControllableHttpClient mockHttp;
    late ApiClient apiClient;

    setUp(() {
      tokenStorage = InMemoryTokenStorage();
      mockHttp = DelayControllableHttpClient();
      apiClient = ApiClient(
        baseUrl: 'http://test-server',
        tokenStorage: tokenStorage,
        client: mockHttp,
      );
    });

    test('Scenario 1: Request A -> Login B -> Late 401 A does not refresh B token or retry A with B token', () async {
      // 1. Session A starts
      apiClient.switchSession('account_A');
      await tokenStorage.setAccessToken('token_A');
      await tokenStorage.setRefreshToken('refresh_A');

      final getWorkoutCompleter = Completer<http.Response>();
      mockHttp.pendingRequests['GET:/api/workouts'] = getWorkoutCompleter;

      // Start Request A
      final futureRequestA = apiClient.request(method: 'GET', endpoint: '/api/workouts');
      expect(
        futureRequestA,
        throwsA(isA<SessionAbortedException>()),
      );

      // 2. User switches to Account B while Request A is in-flight
      apiClient.switchSession('account_B');
      await tokenStorage.setAccessToken('token_B');
      await tokenStorage.setRefreshToken('refresh_B');

      // 3. Late 401 arrives for Request A
      getWorkoutCompleter.complete(http.Response('{"error":"Unauthorized"}', 401, headers: {'content-type': 'application/json'}));

      await pumpEventQueue();

      // Verify token in storage remains token_B
      expect(await tokenStorage.getAccessToken(), 'token_B');
      expect(await tokenStorage.getRefreshToken(), 'refresh_B');

      // Ensure no refresh request was sent using refresh_B for the old A request
      final refreshCalls = mockHttp.executedRequests.where((r) => r.url.path.contains('/refresh')).toList();
      expect(refreshCalls, isEmpty);
    });

    test('Scenario 2: Refresh A -> Login B -> Late success A does not overwrite B tokens', () async {
      // 1. Session A starts and gets 401, triggering refresh
      apiClient.switchSession('account_A');
      await tokenStorage.setAccessToken('token_A_expired');
      await tokenStorage.setRefreshToken('refresh_A');

      final refreshCompleter = Completer<http.Response>();
      mockHttp.pendingRequests['POST:/api/auth/refresh'] = refreshCompleter;

      // Trigger request that gets 401
      mockHttp.pendingRequests['GET:/api/profile'] = Completer<http.Response>()
        ..complete(http.Response('{"error":"Expired"}', 401, headers: {'content-type': 'application/json'}));

      final reqA = apiClient.request(method: 'GET', endpoint: '/api/profile');

      // Allow request to reach refresh
      await Future.delayed(const Duration(milliseconds: 10));

      // 2. Account switches to B
      apiClient.switchSession('account_B');
      await tokenStorage.setAccessToken('token_B_active');
      await tokenStorage.setRefreshToken('refresh_B_active');

      // 3. Late refresh success for A arrives
      refreshCompleter.complete(http.Response(
        jsonEncode({'accessToken': 'new_token_A', 'refreshToken': 'new_refresh_A'}),
        200,
        headers: {'content-type': 'application/json'},
      ));

      // reqA must be aborted
      expect(
        reqA,
        throwsA(isA<SessionAbortedException>()),
      );

      // Account B tokens MUST NOT be overwritten!
      expect(await tokenStorage.getAccessToken(), 'token_B_active');
      expect(await tokenStorage.getRefreshToken(), 'refresh_B_active');
    });

    test('Scenario 3: Refresh A -> Login B -> Late error A does not clear B tokens or fire onSessionExpired for B', () async {
      // 1. Session A starts and gets 401
      apiClient.switchSession('account_A');
      await tokenStorage.setAccessToken('token_A_expired');
      await tokenStorage.setRefreshToken('refresh_A');

      bool sessionExpiredCallbackFired = false;
      apiClient.onSessionExpired = () {
        sessionExpiredCallbackFired = true;
      };

      final refreshCompleter = Completer<http.Response>();
      mockHttp.pendingRequests['POST:/api/auth/refresh'] = refreshCompleter;

      mockHttp.pendingRequests['GET:/api/profile'] = Completer<http.Response>()
        ..complete(http.Response('{"error":"Expired"}', 401, headers: {'content-type': 'application/json'}));

      final reqA = apiClient.request(method: 'GET', endpoint: '/api/profile');
      await Future.delayed(const Duration(milliseconds: 10));

      // 2. Account switches to B
      apiClient.switchSession('account_B');
      await tokenStorage.setAccessToken('token_B_valid');
      await tokenStorage.setRefreshToken('refresh_B_valid');

      // 3. Late refresh failure arrives for A (e.g. 401/invalid token)
      refreshCompleter.complete(http.Response('{"error":"Invalid refresh token"}', 401, headers: {'content-type': 'application/json'}));

      // reqA must be aborted
      expect(
        reqA,
        throwsA(isA<SessionAbortedException>()),
      );

      // onSessionExpired must NOT have fired for Account B!
      expect(sessionExpiredCallbackFired, isFalse);

      // B tokens must remain intact
      expect(await tokenStorage.getAccessToken(), 'token_B_valid');
      expect(await tokenStorage.getRefreshToken(), 'refresh_B_valid');
    });
  });
}
