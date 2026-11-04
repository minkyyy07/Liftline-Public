import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../data_events.dart';
import '../db.dart';
import 'api_client.dart';
import 'auth_service.dart';

enum SyncStatus {
  synced,
  pending,
  syncing,
  error,
  conflict,
}

class CloudWorkoutSync {
  final ApiClient apiClient;
  final AuthService authService;
  final AppDb appDb;
  final _uuid = const Uuid();

  CloudWorkoutSync({
    ApiClient? apiClient,
    AuthService? authService,
    AppDb? appDb,
  })  : apiClient = apiClient ?? AuthService.instance.apiClient,
        authService = authService ?? AuthService.instance,
        appDb = appDb ?? (authService != null ? authService.db : AppDb.instance);

  bool get canSync => authService.isAuthenticated;

  /// Fetches all pages of workouts from server and syncs into the active account database.
  /// Prevents resurrected tombstones, protects uncommitted local edits, and protects
  /// against late responses when account switches mid-request.
  Future<int> syncFromServer(Database db) async {
    if (!canSync) return 0;

    final accountUserId = appDb.currentUserId;
    final accountEpoch = appDb.accountEpoch;

    // First attempt to flush any pending queue operations before downloading
    try {
      await processSyncQueue(db);
    } catch (_) {}

    if (!appDb.isCurrentAccount(accountUserId, accountEpoch)) return 0;

    int syncedCount = 0;
    int page = 0;
    const int pageSize = 50;
    bool hasMore = true;

    while (hasMore) {
      if (!appDb.isCurrentAccount(accountUserId, accountEpoch)) return syncedCount;

      dynamic response;
      try {
        response = await apiClient.request(
          method: 'GET',
          endpoint: '/api/workouts?page=$page&size=$pageSize',
        );
      } catch (e) {
        // Network or server error - preserve local data and return what we have
        break;
      }

      if (!appDb.isCurrentAccount(accountUserId, accountEpoch)) return syncedCount;
      if (response is! List) break;

      await db.transaction((txn) async {
        for (final item in response) {
          if (item is! Map<String, dynamic>) continue;

          final serverId = item['id'] as String;
          final date = item['workoutDate'] as String;
          final title = item['title'] as String? ?? 'Тренировка';
          final duration = item['durationMinutes'] as int?;
          final notes = item['notes'] as String?;
          final serverUpdatedAt = item['updatedAt'] as String?;

          // 1. Tombstone check: record must NOT resurrect if deleted locally offline
          final tombstones = await txn.query(
            'sync_tombstones',
            where: 'id = ? OR server_id = ?',
            whereArgs: [serverId, serverId],
          );
          if (tombstones.isNotEmpty) {
            continue; // Skip resurrecting deleted workout
          }

          // 2. Check existing local workout by ID or server_id
          final existing = await txn.query(
            'workouts',
            where: 'id = ? OR server_id = ?',
            whereArgs: [serverId, serverId],
          );

          String localWorkoutId;
          if (existing.isNotEmpty) {
            final localRow = existing.first;
            localWorkoutId = localRow['id'] as String;
            final localSyncStatus = localRow['sync_status'] as String? ?? 'synced';

            // Never unconditionally overwrite uncommitted local edits!
            if (localSyncStatus == 'pending' || localSyncStatus == 'syncing') {
              // Check for conflict: if server timestamp differs from our last known server timestamp
              final lastKnownServerUpdated = localRow['server_updated_at'] as String?;
              if (lastKnownServerUpdated != null &&
                  serverUpdatedAt != null &&
                  lastKnownServerUpdated != serverUpdatedAt) {
                await txn.update(
                  'workouts',
                  {
                    'sync_status': 'conflict',
                    'sync_error': 'Конфликт: обнаружена новая версия на сервере',
                  },
                  where: 'id = ?',
                  whereArgs: [localWorkoutId],
                );
              }
              // Preserve local pending data intact!
              continue;
            }

            // Synced local row: safe to update with server state
            await txn.update(
              'workouts',
              {
                'server_id': serverId,
                'date': date,
                'title': title,
                'duration_minutes': duration,
                'notes': notes,
                'server_updated_at': serverUpdatedAt,
                'sync_status': 'synced',
                'sync_error': null,
              },
              where: 'id = ?',
              whereArgs: [localWorkoutId],
            );
          } else {
            // Completely new workout from server
            localWorkoutId = serverId;
            await txn.insert('workouts', {
              'id': localWorkoutId,
              'server_id': serverId,
              'date': date,
              'title': title,
              'status': 'finished',
              'duration_minutes': duration,
              'notes': notes,
              'server_updated_at': serverUpdatedAt,
              'sync_status': 'synced',
              'client_version': 1,
              'local_updated_at': DateTime.now().millisecondsSinceEpoch,
            });
          }

          // Clean and populate exercises and sets for this workout
          final existingEx = await txn.query(
            'workout_exercises',
            where: 'workout_id = ?',
            whereArgs: [localWorkoutId],
          );
          for (final ex in existingEx) {
            final exId = ex['id'] as String;
            await txn.delete('set_entries', where: 'exercise_id = ?', whereArgs: [exId]);
          }
          await txn.delete('workout_exercises', where: 'workout_id = ?', whereArgs: [localWorkoutId]);

          final exercises = item['exercises'] as List? ?? [];
          for (final ex in exercises) {
            if (ex is! Map<String, dynamic>) continue;
            final exId = ex['id'] as String? ?? _uuid.v4();
            final exName = ex['exerciseName'] as String? ?? 'Упражнение';
            final sortOrder = ex['sortOrder'] as int? ?? 1;

            await txn.insert('workout_exercises', {
              'id': exId,
              'workout_id': localWorkoutId,
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

      if (response.length < pageSize) {
        hasMore = false;
      } else {
        page++;
      }
    }

    if (syncedCount > 0) {
      AppDataEvents.instance.notifyWorkoutChanged();
    }
    return syncedCount;
  }

  /// Processes all pending operations in `sync_queue` (upserts and deletes).
  /// Enforces version checks: more recent local edits stay pending.
  Future<void> processSyncQueue(Database db) async {
    if (!canSync) return;

    final accountUserId = appDb.currentUserId;
    final accountEpoch = appDb.accountEpoch;

    final queueItems = await db.query(
      'sync_queue',
      orderBy: 'created_at_utc ASC',
    );
    if (queueItems.isEmpty) return;

    for (final item in queueItems) {
      if (!appDb.isCurrentAccount(accountUserId, accountEpoch)) return;

      final queueId = item['id'] as String;
      final workoutId = item['workout_id'] as String;
      final operation = item['operation'] as String;
      final sentVersion = item['client_version'] as int;

      if (operation == 'delete') {
        final tombstones = await db.query(
          'sync_tombstones',
          where: 'id = ?',
          whereArgs: [workoutId],
        );
        final targetServerId = tombstones.isNotEmpty
            ? (tombstones.first['server_id'] as String? ?? workoutId)
            : workoutId;

        try {
          await apiClient.request(
            method: 'DELETE',
            endpoint: '/api/workouts/$targetServerId',
          );
          if (!appDb.isCurrentAccount(accountUserId, accountEpoch)) return;
          await db.delete('sync_queue', where: 'id = ?', whereArgs: [queueId]);
          await db.delete('sync_tombstones', where: 'id = ?', whereArgs: [workoutId]);
        } catch (e) {
          if (!appDb.isCurrentAccount(accountUserId, accountEpoch)) return;
          if (e is ApiException && (e.statusCode == 404 || e.statusCode == 204)) {
            // Already gone on server
            await db.delete('sync_queue', where: 'id = ?', whereArgs: [queueId]);
            await db.delete('sync_tombstones', where: 'id = ?', whereArgs: [workoutId]);
          } else {
            await db.update(
              'sync_queue',
              {
                'attempts': ((item['attempts'] as int?) ?? 0) + 1,
                'last_error': e.toString(),
              },
              where: 'id = ?',
              whereArgs: [queueId],
            );
          }
        }
        continue;
      }

      // Upsert operation
      final wRows = await db.query('workouts', where: 'id = ?', whereArgs: [workoutId]);
      if (wRows.isEmpty) {
        // Workout was deleted locally later
        await db.delete('sync_queue', where: 'id = ?', whereArgs: [queueId]);
        continue;
      }

      final w = wRows.first;
      await db.update(
        'workouts',
        {'sync_status': 'syncing'},
        where: 'id = ?',
        whereArgs: [workoutId],
      );

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
          'id': s['id'],
          'setNumber': s['set_number'],
          'weightKg': (s['weight_kg'] as num?)?.toDouble() ?? 0.0,
          'reps': s['reps'] ?? 0,
          'completed': s['completed'] == 1,
          'setType': s['set_type'] ?? 'work',
          'notes': s['note'],
        }).toList();

        exercisesPayload.add({
          'id': exId,
          'exerciseName': ex['exercise_name'],
          'sortOrder': ex['sort_order'],
          'sets': setsPayload,
        });
      }

      final payload = {
        'id': workoutId,
        'title': w['title'],
        'workoutDate': w['date'],
        'durationMinutes': w['duration_minutes'],
        'notes': w['notes'],
        if (w['server_updated_at'] != null) 'clientUpdatedAt': w['server_updated_at'],
        'exercises': exercisesPayload,
      };

      try {
        dynamic result;
        final serverId = w['server_id'] as String?;
        if (serverId != null && serverId.isNotEmpty) {
          try {
            result = await apiClient.request(
              method: 'PUT',
              endpoint: '/api/workouts/$serverId',
              body: payload,
            );
          } on ApiException catch (ae) {
            if (ae.statusCode == 404) {
              // Fallback to POST with client UUID
              result = await apiClient.request(
                method: 'POST',
                endpoint: '/api/workouts',
                body: payload,
              );
            } else {
              rethrow;
            }
          }
        } else {
          result = await apiClient.request(
            method: 'POST',
            endpoint: '/api/workouts',
            body: payload,
          );
        }

        if (!appDb.isCurrentAccount(accountUserId, accountEpoch)) return;

        final newServerId = (result is Map ? result['id'] as String? : null) ?? serverId ?? workoutId;
        final newUpdatedAt = result is Map ? result['updatedAt'] as String? : null;

        await db.transaction((txn) async {
          final cur = await txn.query('workouts', where: 'id = ?', whereArgs: [workoutId]);
          if (cur.isEmpty) {
            await txn.delete('sync_queue', where: 'id = ?', whereArgs: [queueId]);
            return;
          }
          final currentVersion = cur.first['client_version'] as int? ?? sentVersion;

          if (currentVersion == sentVersion) {
            // No new local edits occurred during the request
            await txn.update(
              'workouts',
              {
                'server_id': newServerId,
                'server_updated_at': newUpdatedAt,
                'sync_status': 'synced',
                'sync_error': null,
              },
              where: 'id = ?',
              whereArgs: [workoutId],
            );
            await txn.delete('sync_queue', where: 'id = ?', whereArgs: [queueId]);
          } else {
            // More recent local edits exist: keep pending with current version
            await txn.update(
              'workouts',
              {
                'server_id': newServerId,
                'server_updated_at': newUpdatedAt,
                'sync_status': 'pending',
              },
              where: 'id = ?',
              whereArgs: [workoutId],
            );
            await txn.update(
              'sync_queue',
              {
                'client_version': currentVersion,
                'attempts': 0,
              },
              where: 'id = ?',
              whereArgs: [queueId],
            );
          }
        });
      } on ApiException catch (e) {
        if (!appDb.isCurrentAccount(accountUserId, accountEpoch)) return;

        if (e.statusCode == 409) {
          // Conflict detected! Preserve local data, mark conflict
          await db.update(
            'workouts',
            {
              'sync_status': 'conflict',
              'sync_error': 'Конфликт правок: тренировка изменена на сервере',
            },
            where: 'id = ?',
            whereArgs: [workoutId],
          );
          // Remove from sync queue so it doesn't repeatedly retry failing conflict
          await db.delete('sync_queue', where: 'id = ?', whereArgs: [queueId]);
        } else {
          await db.update(
            'workouts',
            {
              'sync_status': 'error',
              'sync_error': e.toString(),
            },
            where: 'id = ?',
            whereArgs: [workoutId],
          );
          await db.update(
            'sync_queue',
            {
              'attempts': ((item['attempts'] as int?) ?? 0) + 1,
              'last_error': e.toString(),
            },
            where: 'id = ?',
            whereArgs: [queueId],
          );
        }
      } catch (e) {
        if (!appDb.isCurrentAccount(accountUserId, accountEpoch)) return;
        await db.update(
          'workouts',
          {
            'sync_status': 'error',
            'sync_error': e.toString(),
          },
          where: 'id = ?',
          whereArgs: [workoutId],
        );
        await db.update(
          'sync_queue',
          {
            'attempts': ((item['attempts'] as int?) ?? 0) + 1,
            'last_error': e.toString(),
          },
          where: 'id = ?',
          whereArgs: [queueId],
        );
      }
    }
  }

  /// Pushes a local workout: triggers immediate processing of the sync queue.
  Future<void> pushWorkout(Database db, String workoutId) async {
    await processSyncQueue(db);
  }

  /// Deletes workout on the server: triggers immediate processing of the sync queue.
  Future<void> deleteWorkout(String workoutId) async {
    if (appDb.isOpen) {
      await processSyncQueue(appDb.db);
    }
  }
}
