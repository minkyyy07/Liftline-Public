import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../data_events.dart';
import '../db.dart';
import '../week_utils.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'workout_sync_mapper.dart';

enum SyncStatus {
  synced,
  pending,
  syncing,
  error,
  conflict,
}

/// Raised after a download pass when one or more workouts could not be imported.
/// Each failed workout was rolled back as a whole; the rest of the pass was applied.
class WorkoutImportException implements Exception {
  final int failedCount;
  final Object cause;
  WorkoutImportException(this.failedCount, this.cause);
  @override
  String toString() => 'Не удалось импортировать тренировок: $failedCount ($cause)';
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
    int failedCount = 0;
    Object? firstFailure;
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

      for (final item in response) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        if (!appDb.isCurrentAccount(accountUserId, accountEpoch)) {
          return syncedCount;
        }
        try {
          // One transaction per workout: a failed import leaves that workout untouched.
          final imported = await db.transaction((txn) => _importFromServerItem(txn, item));
          if (imported) {
            syncedCount++;
          }
        } catch (e) {
          failedCount++;
          firstFailure ??= e;
        }
      }

      if (response.length < pageSize) {
        hasMore = false;
      } else {
        page++;
      }
    }

    if (syncedCount > 0) {
      AppDataEvents.instance.notifyWorkoutChanged();
    }
    if (firstFailure != null) {
      throw WorkoutImportException(failedCount, firstFailure);
    }
    return syncedCount;
  }

  /// Imports one server workout inside [txn]. Returns true when the local row was written.
  /// Tombstoned and locally-dirty rows are never overwritten.
  Future<bool> _importFromServerItem(Transaction txn, Map<String, dynamic> item) async {
    final serverId = item['id'] as String;

    // 1. Tombstone check: record must NOT resurrect if deleted locally offline
    final tombstones = await txn.query(
      'sync_tombstones',
      where: 'id = ? OR server_id = ?',
      whereArgs: [serverId, serverId],
    );
    if (tombstones.isNotEmpty) {
      return false; // Skip resurrecting deleted workout
    }

    // 2. Check existing local workout by ID or server_id
    final existing = await txn.query(
      'workouts',
      where: 'id = ? OR server_id = ?',
      whereArgs: [serverId, serverId],
    );
    if (existing.isEmpty) {
      // Completely new workout from server
      await _writeServerWorkout(txn, item, localId: serverId, isNew: true);
      return true;
    }

    final localRow = existing.first;
    final localWorkoutId = localRow['id'] as String;
    final localSyncStatus = localRow['sync_status'] as String? ?? 'synced';
    final serverVersion = item['version'] as int? ?? 0;
    final serverUpdatedAt = item['updatedAt'] as String?;

    // Never unconditionally overwrite uncommitted local edits, conflicts, or errors!
    if (localSyncStatus == 'pending' ||
        localSyncStatus == 'syncing' ||
        localSyncStatus == 'error' ||
        localSyncStatus == 'conflict') {
      // Check for conflict: if server revision or timestamp differs
      final lastKnownServerVer = localRow['server_version'] as int? ?? 0;
      final lastKnownServerUpdated = localRow['server_updated_at'] as String?;
      final isConflict = (serverVersion > lastKnownServerVer) ||
          (lastKnownServerUpdated != null &&
              serverUpdatedAt != null &&
              lastKnownServerUpdated != serverUpdatedAt);

      if (isConflict) {
        // Snapshot local data
        final localEx = await txn.query('workout_exercises', where: 'workout_id = ?', whereArgs: [localWorkoutId]);
        final List<Map<String, dynamic>> localExList = [];
        for (final e in localEx) {
          final sets = await txn.query('set_entries', where: 'exercise_id = ?', whereArgs: [e['id']]);
          localExList.add({
            ...Map<String, dynamic>.from(e),
            'sets': sets.map((s) => Map<String, dynamic>.from(s)).toList(),
          });
        }
        final localSnapshot = {
          'workout': Map<String, dynamic>.from(localRow),
          'exercises': localExList,
        };

        await txn.insert(
          'workout_conflict_drafts',
          {
            'workout_id': localWorkoutId,
            'server_id': serverId,
            'server_version': serverVersion,
            'server_updated_at': serverUpdatedAt,
            'server_data_json': jsonEncode(item),
            'local_data_json': jsonEncode(localSnapshot),
            'detected_at_utc': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        await txn.update(
          'workouts',
          {
            'sync_status': 'conflict',
            'sync_error': 'Конфликт правок: тренировка изменена на сервере',
          },
          where: 'id = ?',
          whereArgs: [localWorkoutId],
        );
      }
      // Preserve local data intact! Do not overwrite local exercises/sets!
      return false;
    }

    // Synced local row: safe to update with server state
    await _writeServerWorkout(txn, item, localId: localWorkoutId, isNew: false);
    return true;
  }

  /// Writes a server workout (with its exercises and sets) into [txn].
  /// Keys missing from [item] keep their stored values; sets and exercises are upserted by id
  /// and rows absent from a sent list are removed. Replaying the same payload never duplicates rows.
  Future<void> _writeServerWorkout(
    DatabaseExecutor txn,
    Map<String, dynamic> item, {
    required String localId,
    required bool isNew,
  }) async {
    final serverId = item['id'] as String;
    final workoutCols = serverWorkoutColumns(item);
    if (isNew) {
      await txn.insert('workouts', {
        'title': 'Тренировка',
        'date': dateKey(DateTime.now()),
        'status': 'finished', // payloads without a status are historical (legacy)
        'client_version': 1,
        'local_updated_at': DateTime.now().millisecondsSinceEpoch,
        ...workoutCols,
        'id': localId,
        'server_id': serverId,
        'sync_status': 'synced',
        'sync_error': null,
      });
    } else {
      await txn.update(
        'workouts',
        {
          ...workoutCols,
          'server_id': serverId,
          'sync_status': 'synced',
          'sync_error': null,
        },
        where: 'id = ?',
        whereArgs: [localId],
      );
    }

    final exercises = item['exercises'];
    if (exercises is! List) {
      return; // no exercise list in payload: keep local exercises
    }

    final keptExerciseIds = <String>[];
    for (final raw in exercises) {
      if (raw is! Map<String, dynamic>) {
        continue;
      }
      final exId = raw['id'] as String? ?? _uuid.v4();
      keptExerciseIds.add(exId);
      await _writeServerExercise(txn, raw, exerciseId: exId, workoutId: localId);
    }
    // The server list is authoritative: drop exercises (and their sets) that are no longer in it.
    await _deleteExercisesNotIn(txn, localId, keptExerciseIds);
  }

  Future<void> _writeServerExercise(
    DatabaseExecutor txn,
    Map<String, dynamic> raw, {
    required String exerciseId,
    required String workoutId,
  }) async {
    final existing = await txn.query('workout_exercises', where: 'id = ?', whereArgs: [exerciseId]);
    if (existing.isNotEmpty && existing.first['workout_id'] != workoutId) {
      throw StateError('Exercise $exerciseId belongs to another workout');
    }

    final cols = serverExerciseColumns(raw);
    final name = (cols['exercise_name'] as String?) ??
        (existing.isEmpty ? 'Упражнение' : existing.first['exercise_name'] as String);

    // Catalogue reference: take the server's when sent, otherwise keep the local one
    // and only fill it in (by name) when there is none yet.
    final serverRef = raw['exerciseRefId'] as String?;
    final localRef = existing.isEmpty ? null : existing.first['exercise_ref_id'] as String?;
    if (serverRef != null && serverRef.isNotEmpty) {
      cols['exercise_ref_id'] = await _resolveServerCatalogueRef(txn, serverRef, name: name);
    } else if (localRef == null) {
      cols['exercise_ref_id'] = await _findOrCreateCatalogueByName(txn, name);
    }

    if (existing.isEmpty) {
      await txn.insert('workout_exercises', {
        'exercise_name': 'Упражнение',
        'sort_order': 1,
        ...cols,
        'id': exerciseId,
        'workout_id': workoutId,
      });
    } else if (cols.isNotEmpty) {
      await txn.update('workout_exercises', cols, where: 'id = ?', whereArgs: [exerciseId]);
    }

    final sets = raw['sets'];
    if (sets is! List) {
      return; // no set list in payload: keep local sets
    }
    final keptSetIds = <String>[];
    for (final s in sets) {
      if (s is! Map<String, dynamic>) {
        continue;
      }
      final setId = s['id'] as String? ?? _uuid.v4();
      keptSetIds.add(setId);
      final setExisting = await txn.query('set_entries', where: 'id = ?', whereArgs: [setId]);
      if (setExisting.isNotEmpty && setExisting.first['exercise_id'] != exerciseId) {
        throw StateError('Set $setId belongs to another exercise');
      }
      final setCols = serverSetColumns(s);
      if (setExisting.isEmpty) {
        await txn.insert('set_entries', {
          'set_number': 1,
          'weight_kg': 0.0,
          'reps': 0,
          'completed': 1,
          'set_type': 'work',
          ...setCols,
          'id': setId,
          'exercise_id': exerciseId,
        });
      } else if (setCols.isNotEmpty) {
        await txn.update('set_entries', setCols, where: 'id = ?', whereArgs: [setId]);
      }
    }
    await _deleteSetsNotIn(txn, exerciseId, keptSetIds);
  }

  Future<void> _deleteExercisesNotIn(DatabaseExecutor txn, String workoutId, List<String> keep) async {
    final notIn = keep.isEmpty ? '' : ' AND id NOT IN (${List.filled(keep.length, '?').join(',')})';
    final args = [workoutId, ...keep];
    await txn.rawDelete(
      'DELETE FROM set_entries WHERE exercise_id IN (SELECT id FROM workout_exercises WHERE workout_id = ?$notIn)',
      args,
    );
    await txn.rawDelete('DELETE FROM workout_exercises WHERE workout_id = ?$notIn', args);
  }

  Future<void> _deleteSetsNotIn(DatabaseExecutor txn, String exerciseId, List<String> keep) async {
    final notIn = keep.isEmpty ? '' : ' AND id NOT IN (${List.filled(keep.length, '?').join(',')})';
    await txn.rawDelete(
      'DELETE FROM set_entries WHERE exercise_id = ?$notIn',
      [exerciseId, ...keep],
    );
  }

  /// Server reference id -> local catalogue id. Known id: use it. Unknown id: reuse the local
  /// catalogue entry with the same name (catalogue is name-unique), otherwise create it with
  /// the server id so both devices share the same reference.
  Future<String> _resolveServerCatalogueRef(DatabaseExecutor txn, String serverRef, {required String name}) async {
    final byId = await txn.query('exercises', columns: ['id'], where: 'id = ?', whereArgs: [serverRef], limit: 1);
    if (byId.isNotEmpty) {
      return serverRef;
    }
    final byName = await _catalogueIdByName(txn, name);
    if (byName != null) {
      return byName;
    }
    await txn.insert('exercises', {'id': serverRef, 'name': name.trim()});
    return serverRef;
  }

  Future<String> _findOrCreateCatalogueByName(DatabaseExecutor txn, String name) async {
    final byName = await _catalogueIdByName(txn, name);
    if (byName != null) {
      return byName;
    }
    final id = _uuid.v4();
    await txn.insert('exercises', {'id': id, 'name': name.trim()});
    return id;
  }

  Future<String?> _catalogueIdByName(DatabaseExecutor txn, String name) async {
    final rows = await txn.query('exercises', columns: ['id'], where: 'name = ?', whereArgs: [name.trim()], limit: 1);
    return rows.isEmpty ? null : rows.first['id'] as String;
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

      // Upsert operation.
      // A successful upload of a newer revision may already have removed this (superseded)
      // entry, and the list above is a snapshot: do not replay it.
      final stillQueued = await db.query('sync_queue', columns: ['id'], where: 'id = ?', whereArgs: [queueId]);
      if (stillQueued.isEmpty) {
        continue;
      }
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
      final setsByExercise = <String, List<Map<String, Object?>>>{};
      for (final ex in exRows) {
        final exId = ex['id'] as String;
        setsByExercise[exId] = await db.query(
          'set_entries',
          where: 'exercise_id = ?',
          whereArgs: [exId],
          orderBy: 'set_number',
        );
      }

      final payload = buildWorkoutUploadPayload(
        workout: Map<String, Object?>.from(w),
        exercises: exRows.map((r) => Map<String, Object?>.from(r)).toList(),
        sets: setsByExercise,
      );

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
        final newVersion = result is Map ? (result['version'] as int?) : null;

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
                if (newVersion != null) 'server_version': newVersion,
                'sync_status': 'synced',
                'sync_error': null,
              },
              where: 'id = ?',
              whereArgs: [workoutId],
            );
            // This upload carried the full state, so every upsert queued up to this revision is done.
            await txn.delete(
              'sync_queue',
              where: "workout_id = ? AND operation = 'upsert' AND client_version <= ?",
              whereArgs: [workoutId, sentVersion],
            );
          } else {
            // More recent local edits exist: keep pending with current version
            await txn.update(
              'workouts',
              {
                'server_id': newServerId,
                'server_updated_at': newUpdatedAt,
                if (newVersion != null) 'server_version': newVersion,
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
          // Conflict detected! Preserve local data, record draft if possible, mark conflict
          await db.transaction((txn) async {
            // Snapshot local data
            final localRow = (await txn.query('workouts', where: 'id = ?', whereArgs: [workoutId])).firstOrNull;
            if (localRow != null) {
              final localEx = await txn.query('workout_exercises', where: 'workout_id = ?', whereArgs: [workoutId]);
              final List<Map<String, dynamic>> localExList = [];
              for (final e in localEx) {
                final sets = await txn.query('set_entries', where: 'exercise_id = ?', whereArgs: [e['id']]);
                localExList.add({
                  ...Map<String, dynamic>.from(e),
                  'sets': sets.map((s) => Map<String, dynamic>.from(s)).toList(),
                });
              }
              final localSnapshot = {
                'workout': Map<String, dynamic>.from(localRow),
                'exercises': localExList,
              };

              await txn.insert(
                'workout_conflict_drafts',
                {
                  'workout_id': workoutId,
                  'server_id': w['server_id'] as String? ?? workoutId,
                  'server_version': (w['server_version'] as int? ?? 0) + 1,
                  'server_updated_at': w['server_updated_at'] as String?,
                  'server_data_json': jsonEncode({'id': w['server_id'] ?? workoutId, 'conflict': true}),
                  'local_data_json': jsonEncode(localSnapshot),
                  'detected_at_utc': DateTime.now().millisecondsSinceEpoch,
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }

            await txn.update(
              'workouts',
              {
                'sync_status': 'conflict',
                'sync_error': 'Конфликт правок: тренировка изменена на сервере',
              },
              where: 'id = ?',
              whereArgs: [workoutId],
            );
            // Remove queued uploads so the failing conflict is not retried in a loop
            await txn.delete(
              'sync_queue',
              where: "workout_id = ? AND operation = 'upsert'",
              whereArgs: [workoutId],
            );
          });
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

  /// Resolves conflict by explicitly keeping local version and queuing it for upload
  /// with latest known server revision so it safely updates server state.
  Future<void> resolveConflictKeepLocal(Database db, String workoutId) async {
    final conflictDrafts = await db.query('workout_conflict_drafts', where: 'workout_id = ?', whereArgs: [workoutId]);
    int targetServerVersion = 0;
    String? targetServerUpdated;

    if (conflictDrafts.isNotEmpty) {
      targetServerVersion = conflictDrafts.first['server_version'] as int? ?? 0;
      targetServerUpdated = conflictDrafts.first['server_updated_at'] as String?;
    }

    final cur = await db.query('workouts', where: 'id = ?', whereArgs: [workoutId]);
    if (cur.isEmpty) return;

    final nextVer = ((cur.first['client_version'] as int?) ?? 1) + 1;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      await txn.update(
        'workouts',
        {
          'sync_status': 'pending',
          'sync_error': null,
          'server_version': targetServerVersion,
          if (targetServerUpdated != null) 'server_updated_at': targetServerUpdated,
          'client_version': nextVer,
          'local_updated_at': nowMs,
        },
        where: 'id = ?',
        whereArgs: [workoutId],
      );

      await txn.delete('workout_conflict_drafts', where: 'workout_id = ?', whereArgs: [workoutId]);

      await txn.insert(
        'sync_queue',
        {
          'id': _uuid.v4(),
          'workout_id': workoutId,
          'operation': 'upsert',
          'client_version': nextVer,
          'created_at_utc': nowMs,
          'attempts': 0,
          'last_error': null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    AppDataEvents.instance.notifyWorkoutChanged();
  }

  /// Resolves conflict by accepting server version, overwriting local workout with server state.
  Future<void> resolveConflictAcceptServer(Database db, String workoutId) async {
    final conflictDrafts = await db.query('workout_conflict_drafts', where: 'workout_id = ?', whereArgs: [workoutId]);
    if (conflictDrafts.isEmpty) return;

    final draft = conflictDrafts.first;
    final serverJsonStr = draft['server_data_json'] as String;
    final serverData = jsonDecode(serverJsonStr) as Map<String, dynamic>;

    if (serverData['exercises'] == null) {
      // If server_data_json didn't contain full exercise list, re-fetch from server
      await syncFromServer(db);
      return;
    }

    final item = Map<String, dynamic>.from(serverData)
      ..putIfAbsent('id', () => workoutId)
      ..putIfAbsent('version', () => draft['server_version'])
      ..putIfAbsent('updatedAt', () => draft['server_updated_at']);

    await db.transaction((txn) async {
      await _writeServerWorkout(txn, item, localId: workoutId, isNew: false);
      await txn.delete('workout_conflict_drafts', where: 'workout_id = ?', whereArgs: [workoutId]);
      await txn.delete('sync_queue', where: 'workout_id = ?', whereArgs: [workoutId]);
    });

    AppDataEvents.instance.notifyWorkoutChanged();
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
