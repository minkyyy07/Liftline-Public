import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'api_client.dart';
import 'auth_service.dart';

class CloudWorkoutSync {
  final ApiClient apiClient;
  final AuthService authService;
  final _uuid = const Uuid();

  CloudWorkoutSync({
    ApiClient? apiClient,
    AuthService? authService,
  })  : apiClient = apiClient ?? AuthService.instance.apiClient,
        authService = authService ?? AuthService.instance;

  bool get canSync => authService.isAuthenticated;

  /// Fetches workouts from server and syncs into the active account database.
  Future<int> syncFromServer(Database db) async {
    if (!canSync) return 0;

    final response = await apiClient.request(
      method: 'GET',
      endpoint: '/api/workouts?page=0&size=100',
    );

    if (response is! List) return 0;

    int syncedCount = 0;
    await db.transaction((txn) async {
      for (final item in response) {
        if (item is! Map<String, dynamic>) continue;

        final id = item['id'] as String;
        final date = item['workoutDate'] as String;
        final title = item['title'] as String? ?? 'Тренировка';
        final duration = item['durationMinutes'] as int?;
        final notes = item['notes'] as String?;

        // 1. Insert or update workout
        final existing = await txn.query('workouts', where: 'id = ?', whereArgs: [id]);
        if (existing.isEmpty) {
          await txn.insert('workouts', {
            'id': id,
            'date': date,
            'title': title,
            'status': 'finished',
            'duration_minutes': duration,
            'notes': notes,
          });
        } else {
          await txn.update(
            'workouts',
            {
              'date': date,
              'title': title,
              'duration_minutes': duration,
              'notes': notes,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }

        // Clean existing exercises and sets for this workout to avoid duplicates
        final existingEx = await txn.query('workout_exercises', where: 'workout_id = ?', whereArgs: [id]);
        for (final ex in existingEx) {
          final exId = ex['id'] as String;
          await txn.delete('set_entries', where: 'exercise_id = ?', whereArgs: [exId]);
        }
        await txn.delete('workout_exercises', where: 'workout_id = ?', whereArgs: [id]);

        // 2. Insert exercises and sets
        final exercises = item['exercises'] as List? ?? [];
        for (final ex in exercises) {
          if (ex is! Map<String, dynamic>) continue;
          final exId = ex['id'] as String? ?? _uuid.v4();
          final exName = ex['exerciseName'] as String? ?? 'Упражнение';
          final sortOrder = ex['sortOrder'] as int? ?? 1;

          await txn.insert('workout_exercises', {
            'id': exId,
            'workout_id': id,
            'exercise_name': exName,
            'sort_order': sortOrder,
          });

          final sets = ex['sets'] as List? ?? [];
          for (final s in sets) {
            if (s is! Map<String, dynamic>) continue;
            final setId = s['id'] as String? ?? _uuid.v4();
            final setNum = s['setNumber'] as int? ?? 1;
            final weight = (s['weightKg'] as num?)?.toDouble() ?? 0.0;
            final reps = s['reps'] as int? ?? 0;
            final completed = (s['completed'] as bool? ?? true) ? 1 : 0;
            final setType = s['setType'] as String? ?? 'work';
            final setNote = s['notes'] as String?;

            await txn.insert('set_entries', {
              'id': setId,
              'exercise_id': exId,
              'set_number': setNum,
              'weight_kg': weight,
              'reps': reps,
              'completed': completed,
              'set_type': setType,
              'note': setNote,
            });
          }
        }
        syncedCount++;
      }
    });

    return syncedCount;
  }

  /// Pushes a local workout and all its exercises and sets to the server.
  /// Throws [ApiException] if network or server error occurs.
  Future<void> pushWorkout(Database db, String workoutId) async {
    if (!canSync) return;

    final wRows = await db.query('workouts', where: 'id = ?', whereArgs: [workoutId]);
    if (wRows.isEmpty) return;
    final w = wRows.first;

    final exRows = await db.query(
      'workout_exercises',
      where: 'workout_id = ?',
      whereArgs: [workoutId],
      orderBy: 'sort_order',
    );

    final exercisesPayload = <Map<String, dynamic>>[];
    for (final ex in exRows) {
      final exId = ex['id'] as String;
      final setRows = await db.query(
        'set_entries',
        where: 'exercise_id = ?',
        whereArgs: [exId],
        orderBy: 'set_number',
      );

      final setsPayload = setRows.map((s) => {
        'setNumber': s['set_number'],
        'weightKg': (s['weight_kg'] as num?)?.toDouble() ?? 0.0,
        'reps': s['reps'] ?? 0,
        'completed': s['completed'] == 1,
        'setType': s['set_type'] ?? 'work',
        'notes': s['note'],
      }).toList();

      exercisesPayload.add({
        'exerciseName': ex['exercise_name'],
        'sortOrder': ex['sort_order'],
        'sets': setsPayload,
      });
    }

    final payload = {
      'title': w['title'],
      'workoutDate': w['date'],
      'durationMinutes': w['duration_minutes'],
      'notes': w['notes'],
      'exercises': exercisesPayload,
    };

    // Attempt to create on server
    await apiClient.request(
      method: 'POST',
      endpoint: '/api/workouts',
      body: payload,
    );
  }

  /// Deletes workout on the server.
  Future<void> deleteWorkout(String workoutId) async {
    if (!canSync) return;
    try {
      await apiClient.request(
        method: 'DELETE',
        endpoint: '/api/workouts/$workoutId',
      );
    } catch (_) {}
  }
}
