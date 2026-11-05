/// Lifecycle states of a workout (same values as `workouts.status` in SQLite and on the server).
const Set<String> kWorkoutStatuses = {'planned', 'active', 'finished'};

/// Epoch milliseconds (local column format) -> ISO-8601 UTC string (wire format).
String? isoUtcFromMs(int? ms) =>
    ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
          ms,
          isUtc: true,
        ).toIso8601String();

/// ISO-8601 string (wire format) -> epoch milliseconds (local column format).
/// Malformed values throw, so the import of that workout is rolled back instead of
/// silently dropping a lifecycle timestamp.
int? msFromIsoUtc(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('Timestamp must be a string', value);
  }
  return DateTime.parse(value).toUtc().millisecondsSinceEpoch;
}

int? _asInt(Object? v) => v is num ? v.toInt() : null;

// ---------------------------------------------------------------------------
// Upload: local rows -> wire payload for POST/PUT /api/workouts
// ---------------------------------------------------------------------------

/// Builds the workout upsert payload from SQLite rows.
/// [exercises] are `workout_exercises` rows ordered by sort_order.
/// [sets] maps exercise id -> `set_entries` rows ordered by set_number.
Map<String, Object?> buildWorkoutUploadPayload({
  required Map<String, Object?> workout,
  required List<Map<String, Object?>> exercises,
  required Map<String, List<Map<String, Object?>>> sets,
}) {
  final serverVersion = workout['server_version'];
  final serverUpdatedAt = workout['server_updated_at'];
  return {
    'id': workout['id'],
    'title': workout['title'],
    'workoutDate': workout['date'],
    'durationMinutes': workout['duration_minutes'],
    'notes': workout['notes'],
    'status': workout['status'] ?? 'finished',
    'startedAtUtc': isoUtcFromMs(_asInt(workout['started_at_utc'])),
    'finishedAtUtc': isoUtcFromMs(_asInt(workout['finished_at_utc'])),
    if (serverVersion != null) 'version': serverVersion,
    if (serverUpdatedAt != null) 'clientUpdatedAt': serverUpdatedAt,
    'exercises': [
      for (final ex in exercises)
        _exercisePayload(ex, sets[ex['id'] as String] ?? const []),
    ],
  };
}

Map<String, Object?> _exercisePayload(
  Map<String, Object?> ex,
  List<Map<String, Object?>> setRows,
) {
  return {
    'id': ex['id'],
    'exerciseName': ex['exercise_name'],
    'sortOrder': ex['sort_order'],
    'exerciseRefId': ex['exercise_ref_id'],
    'notes': ex['note'],
    'planSets': ex['plan_sets'],
    'planRepMin': ex['plan_rep_min'],
    'planRepMax': ex['plan_rep_max'],
    'planRir': ex['plan_rir'],
    'planRestSec': ex['plan_rest_sec'],
    'sets': [for (final s in setRows) _setPayload(s)],
  };
}

Map<String, Object?> _setPayload(Map<String, Object?> s) {
  return {
    'id': s['id'],
    'setNumber': s['set_number'],
    'weightKg': (s['weight_kg'] as num?)?.toDouble() ?? 0.0,
    'reps': s['reps'] ?? 0,
    'completed': s['completed'] == 1,
    'rir': s['rir'],
    'setType': s['set_type'] ?? 'work',
    'notes': s['note'],
    'completedAtUtc': isoUtcFromMs(_asInt(s['completed_at_utc'])),
  };
}

// ---------------------------------------------------------------------------
// Download: wire JSON -> SQLite column maps.
//
// Presence matters: a key that is ABSENT from the payload is not written (the stored value
// stays), while an explicit null clears a nullable column. Required NOT NULL columns map
// null to their neutral default. Old payloads without the newer keys therefore never
// overwrite local data.
// ---------------------------------------------------------------------------

/// Workout-level columns present in [item]. Does not include server_id / sync bookkeeping.
Map<String, Object?> serverWorkoutColumns(Map<String, dynamic> item) {
  final out = <String, Object?>{};
  final date = item['workoutDate'];
  if (date is String) {
    out['date'] = date;
  }
  final title = item['title'];
  if (title is String) {
    out['title'] = title;
  }
  if (item.containsKey('durationMinutes')) {
    out['duration_minutes'] = _asInt(item['durationMinutes']);
  }
  if (item.containsKey('notes')) {
    out['notes'] = item['notes'] as String?;
  }
  final status = item['status'];
  if (status is String && kWorkoutStatuses.contains(status)) {
    out['status'] = status;
  }
  if (item.containsKey('startedAtUtc')) {
    out['started_at_utc'] = msFromIsoUtc(item['startedAtUtc']);
  }
  if (item.containsKey('finishedAtUtc')) {
    out['finished_at_utc'] = msFromIsoUtc(item['finishedAtUtc']);
  }
  if (item.containsKey('updatedAt')) {
    out['server_updated_at'] = item['updatedAt'] as String?;
  }
  final version = item['version'];
  if (version is num) {
    out['server_version'] = version.toInt();
  }
  return out;
}

/// Exercise-level columns present in [ex]. The catalogue reference is resolved by the
/// importer (it needs the database), so `exercise_ref_id` is not produced here.
Map<String, Object?> serverExerciseColumns(Map<String, dynamic> ex) {
  final out = <String, Object?>{};
  final name = ex['exerciseName'];
  if (name is String) {
    out['exercise_name'] = name;
  }
  if (ex.containsKey('sortOrder')) {
    out['sort_order'] = _asInt(ex['sortOrder']) ?? 1;
  }
  if (ex.containsKey('notes')) {
    out['note'] = ex['notes'] as String?;
  }
  if (ex.containsKey('planSets')) {
    out['plan_sets'] = _asInt(ex['planSets']);
  }
  if (ex.containsKey('planRepMin')) {
    out['plan_rep_min'] = _asInt(ex['planRepMin']);
  }
  if (ex.containsKey('planRepMax')) {
    out['plan_rep_max'] = _asInt(ex['planRepMax']);
  }
  if (ex.containsKey('planRir')) {
    out['plan_rir'] = _asInt(ex['planRir']);
  }
  if (ex.containsKey('planRestSec')) {
    out['plan_rest_sec'] = _asInt(ex['planRestSec']);
  }
  return out;
}

/// Set-level columns present in [s].
Map<String, Object?> serverSetColumns(Map<String, dynamic> s) {
  final out = <String, Object?>{};
  if (s.containsKey('setNumber')) {
    out['set_number'] = _asInt(s['setNumber']) ?? 1;
  }
  if (s.containsKey('weightKg')) {
    final w = s['weightKg'];
    out['weight_kg'] = w is num ? w.toDouble() : 0.0; // NOT NULL column
  }
  if (s.containsKey('reps')) {
    out['reps'] = _asInt(s['reps']) ?? 0; // NOT NULL column
  }
  if (s.containsKey('completed')) {
    out['completed'] = (s['completed'] as bool? ?? true) ? 1 : 0;
  }
  if (s.containsKey('setType')) {
    out['set_type'] = s['setType'] as String? ?? 'work';
  }
  if (s.containsKey('notes')) {
    out['note'] = s['notes'] as String?;
  }
  if (s.containsKey('rir')) {
    out['rir'] = _asInt(s['rir']);
  }
  if (s.containsKey('completedAtUtc')) {
    out['completed_at_utc'] = msFromIsoUtc(s['completedAtUtc']);
  }
  return out;
}
