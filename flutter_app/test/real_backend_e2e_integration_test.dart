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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const backendBaseUrl = 'http://127.0.0.1:8080';

  test('Real Flutter -> Spring Boot Backend End-to-End Scenario', () async {
    // 0. Check if backend is alive
    bool isBackendRunning = false;
    try {
      final healthCheck = await http
          .get(Uri.parse('$backendBaseUrl/api/workouts'))
          .timeout(const Duration(milliseconds: 500));
      isBackendRunning = healthCheck.statusCode == 401 || healthCheck.statusCode == 403;
    } catch (_) {
      isBackendRunning = false;
    }

    if (!isBackendRunning) {
      final isIntegrationMandatory = Platform.environment['MANDATORY_INTEGRATION'] == 'true';
      if (isIntegrationMandatory) {
        fail('Backend is not running at $backendBaseUrl, but MANDATORY_INTEGRATION is enabled!');
      } else {
        // Explicitly report skip in standard test run
        markTestSkipped('Backend is not running on $backendBaseUrl. Skipping live E2E test. Set MANDATORY_INTEGRATION=true to require server.');
        return;
      }
    }

    final tokenStorage = InMemoryTokenStorage();
    final realHttpClient = http.Client();
    final apiClient = ApiClient(
      baseUrl: backendBaseUrl,
      tokenStorage: tokenStorage,
      client: realHttpClient,
    );
    final appDb = AppDb.isolated();
    final authService = AuthService.forTest(
      tokenStorage: tokenStorage,
      apiClient: apiClient,
      appDb: appDb,
    );

    final syncEngine = CloudWorkoutSync(
      apiClient: apiClient,
      authService: authService,
      appDb: appDb,
    );

    final testEmail = 'flutter_e2e_${DateTime.now().millisecondsSinceEpoch}@example.com';
    const testPassword = 'Password123!';

    // 1. Register and login user on the real backend
    await authService.register(testEmail, testPassword);
    await authService.login(testEmail, testPassword);
    expect(authService.isAuthenticated, isTrue, reason: authService.errorMessage);
    final userId = authService.user!.id;
    expect(userId, isNotEmpty);

    // Active DB is switched to this real user
    expect(appDb.isOpen, isTrue);
    final db = appDb.db;

    // 2. Create Workout locally in SQLite
    final repo = WorkoutRepo(db);
    final workoutId = await repo.createWorkout(
      title: 'Real E2E Heavy Push Day',
      date: DateTime(2026, 11, 4),
      start: true,
    );
    expect(workoutId, isNotEmpty);

    // 3. Add exercises and sets locally
    final exBenchId = await repo.addExercise(workoutId, 'Barbell Bench Press');
    final set1Id = await repo.addSet(exBenchId, warmup: false);
    await repo.updateSet(set1Id, weight: 100.0, reps: 5);
    await repo.setCompleted(set1Id, true);

    final set2Id = await repo.addSet(exBenchId, warmup: false);
    await repo.updateSet(set2Id, weight: 100.0, reps: 5);
    await repo.setCompleted(set2Id, true);

    final exInclineId = await repo.addExercise(workoutId, 'Incline Dumbbell Press');
    final set3Id = await repo.addSet(exInclineId, warmup: false);
    await repo.updateSet(set3Id, weight: 36.0, reps: 8);
    await repo.setCompleted(set3Id, true);

    // Finish workout
    await repo.finishWorkout(workoutId);

    // Verify local status is pending before sync
    final localBefore = (await db.query('workouts', where: 'id = ?', whereArgs: [workoutId])).first;
    expect(localBefore['sync_status'], 'pending');

    // 4. Sync to real backend via CloudWorkoutSync
    await syncEngine.processSyncQueue(db);

    // 5. Verify local SQLite status is updated to 'synced'
    final localAfter = (await db.query('workouts', where: 'id = ?', whereArgs: [workoutId])).first;
    expect(localAfter['sync_status'], 'synced');
    expect(localAfter['server_id'], workoutId); // Client UUID preserved by backend

    // 6. Direct independent HTTP check against the backend
    final accessToken = await tokenStorage.getAccessToken();
    final directResponse = await realHttpClient.get(
      Uri.parse('$backendBaseUrl/api/workouts/$workoutId'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );
    expect(directResponse.statusCode, 200);
    final serverData = jsonDecode(directResponse.body) as Map<String, dynamic>;

    expect(serverData['id'], workoutId);
    expect(serverData['title'], 'Real E2E Heavy Push Day');
    final serverExercises = serverData['exercises'] as List;
    expect(serverExercises.length, 2);

    final benchEx = serverExercises.firstWhere((e) => e['exerciseName'] == 'Barbell Bench Press');
    final benchSets = benchEx['sets'] as List;
    expect(benchSets.length, 2);
    expect(benchSets.first['weightKg'], 100.0);
    expect(benchSets.first['reps'], 5);
    expect(benchSets.first['completed'], isTrue);

    // 7. Update Workout locally: Rename & add new set
    await repo.renameWorkout(workoutId, 'Real E2E Heavy Push Day (PR Edition)');
    final set4Id = await repo.addSet(exInclineId, warmup: false);
    await repo.updateSet(set4Id, weight: 40.0, reps: 6);
    await repo.setCompleted(set4Id, true);

    // Sync changes
    await syncEngine.processSyncQueue(db);

    // Verify updated on backend
    final directUpdated = await realHttpClient.get(
      Uri.parse('$backendBaseUrl/api/workouts/$workoutId'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );
    expect(directUpdated.statusCode, 200);
    final updatedData = jsonDecode(directUpdated.body) as Map<String, dynamic>;
    expect(updatedData['title'], 'Real E2E Heavy Push Day (PR Edition)');
    final updatedExs = updatedData['exercises'] as List;
    final updatedIncline = updatedExs.firstWhere((e) => e['exerciseName'] == 'Incline Dumbbell Press');
    expect((updatedIncline['sets'] as List).length, 2);

    // 8. Delete Workout locally and verify removal on real backend
    await repo.deleteWorkout(workoutId);
    await syncEngine.processSyncQueue(db);

    final deletedCheck = await realHttpClient.get(
      Uri.parse('$backendBaseUrl/api/workouts/$workoutId'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );
    expect(deletedCheck.statusCode, anyOf(404, 403));

    // Close test resources
    if (appDb.isOpen) await appDb.db.close();
    realHttpClient.close();
  });
}
