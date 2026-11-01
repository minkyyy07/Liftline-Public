import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const int kDbVersion = 4;

/// Singleton holder of the app database.
class AppDb {
  static final AppDb instance = AppDb._();
  AppDb._();

  Database? _db;
  Database get db => _db!;

  /// Test hook: use an already opened database.
  void useDatabase(Database d) => _db = d;

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    _db = await openLiftlineDb(p.join(dbPath, 'liftline.db'));
  }
}

/// Opens (creating / migrating) the Liftline database at [path].
/// Before migrating an existing older database a consistent backup copy is
/// written next to it with `VACUUM INTO` (safe for WAL databases).
Future<Database> openLiftlineDb(String path, {DatabaseFactory? factory}) async {
  final f = factory ?? databaseFactory;
  if (await f.databaseExists(path)) {
    final probe = await f.openDatabase(path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
    final v = (await probe.rawQuery('PRAGMA user_version')).first.values.first
        as int;
    await probe.close();
    if (v > 0 && v < kDbVersion) {
      final backup = '$path.v$v.bak';
      final bdb = await f.openDatabase(path,
          options: OpenDatabaseOptions(singleInstance: false));
      try {
        if (!await f.databaseExists(backup)) {
          await bdb.execute("VACUUM INTO '${backup.replaceAll("'", "''")}'");
        }
      } finally {
        await bdb.close();
      }
    }
  }
  return f.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: kDbVersion,
      onCreate: (db, version) async {
        await createV1Schema(db);
        await migrateV1ToV2(db);
        await migrateV2ToV3(db);
        await migrateV3ToV4(db);
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) await migrateV1ToV2(db);
        if (oldV < 3) await migrateV2ToV3(db);
        if (oldV < 4) await migrateV3ToV4(db);
      },
    ),
  );
}

/// Original (version 1) schema. Kept so migrations can be tested.
Future<void> createV1Schema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE workouts (
      id TEXT PRIMARY KEY,
      date TEXT NOT NULL,
      title TEXT NOT NULL,
      duration_minutes INTEGER,
      notes TEXT
    )''');
  await db.execute('''
    CREATE TABLE workout_exercises (
      id TEXT PRIMARY KEY,
      workout_id TEXT NOT NULL,
      exercise_name TEXT NOT NULL,
      sort_order INTEGER NOT NULL
    )''');
  await db.execute('''
    CREATE TABLE set_entries (
      id TEXT PRIMARY KEY,
      exercise_id TEXT NOT NULL,
      set_number INTEGER NOT NULL,
      weight_kg REAL NOT NULL,
      reps INTEGER NOT NULL,
      completed INTEGER NOT NULL DEFAULT 1
    )''');
  await db.execute('''
    CREATE TABLE nutrition_entries (
      id TEXT PRIMARY KEY,
      date TEXT NOT NULL,
      name TEXT NOT NULL,
      portion TEXT,
      calories INTEGER NOT NULL,
      protein REAL NOT NULL,
      fat REAL NOT NULL,
      carbs REAL NOT NULL
    )''');
  await db.execute('''
    CREATE TABLE user_goals (
      id TEXT PRIMARY KEY,
      calories INTEGER,
      protein REAL,
      fat REAL,
      carbs REAL
    )''');
}

/// v1 -> v2: exercise catalogue, workout status/UTC times, plans, RIR,
/// set type and notes. Only adds; never drops or rewrites user values.
/// Runs inside sqflite's upgrade transaction (rolled back on error).
Future<void> migrateV1ToV2(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE exercises (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      archived INTEGER NOT NULL DEFAULT 0,
      weight_mode TEXT NOT NULL DEFAULT 'total'
    )''');
  // Old workouts are historical: finished. Old dates/durations untouched.
  await db.execute("ALTER TABLE workouts ADD COLUMN status TEXT NOT NULL DEFAULT 'finished'");
  await db.execute('ALTER TABLE workouts ADD COLUMN started_at_utc INTEGER');
  await db.execute('ALTER TABLE workouts ADD COLUMN finished_at_utc INTEGER');
  await db.execute('ALTER TABLE workout_exercises ADD COLUMN exercise_ref_id TEXT');
  await db.execute('ALTER TABLE workout_exercises ADD COLUMN plan_sets INTEGER');
  await db.execute('ALTER TABLE workout_exercises ADD COLUMN plan_rep_min INTEGER');
  await db.execute('ALTER TABLE workout_exercises ADD COLUMN plan_rep_max INTEGER');
  await db.execute('ALTER TABLE workout_exercises ADD COLUMN plan_rir INTEGER');
  await db.execute('ALTER TABLE workout_exercises ADD COLUMN plan_rest_sec INTEGER');
  await db.execute('ALTER TABLE workout_exercises ADD COLUMN note TEXT');
  await db.execute('ALTER TABLE workout_exercises ADD COLUMN weight_mode TEXT');
  // rir stays NULL for old sets; completed keeps its stored value.
  await db.execute('ALTER TABLE set_entries ADD COLUMN rir INTEGER');
  await db.execute("ALTER TABLE set_entries ADD COLUMN set_type TEXT NOT NULL DEFAULT 'work'");
  await db.execute('ALTER TABLE set_entries ADD COLUMN note TEXT');
  await db.execute('ALTER TABLE set_entries ADD COLUMN completed_at_utc INTEGER');

  // Catalogue: one entry per exact (trimmed) old name; no fuzzy merging.
  await db.execute('''
    INSERT INTO exercises (id, name)
    SELECT lower(hex(randomblob(16))), n FROM (
      SELECT DISTINCT trim(exercise_name) AS n FROM workout_exercises
      WHERE trim(exercise_name) <> '')''');
  await db.execute('''
    UPDATE workout_exercises SET exercise_ref_id =
      (SELECT e.id FROM exercises e WHERE e.name = trim(workout_exercises.exercise_name))''');
  await db.execute('CREATE INDEX idx_we_workout ON workout_exercises(workout_id)');
  await db.execute('CREATE INDEX idx_we_ref ON workout_exercises(exercise_ref_id)');
  await db.execute('CREATE INDEX idx_se_ex ON set_entries(exercise_id)');
}

/// v2 -> v3: nutrition. Product catalogue, entry snapshots (mode, mass, per-100 g
/// values, meal) and dated goals. Existing entries become mode 'portion' with
/// their stored totals untouched (per-100 values are NOT guessed).
Future<void> migrateV2ToV3(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE foods (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      kcal100 REAL NOT NULL,
      protein100 REAL NOT NULL,
      fat100 REAL NOT NULL,
      carbs100 REAL NOT NULL,
      archived INTEGER NOT NULL DEFAULT 0
    )''');
  await db.execute("ALTER TABLE nutrition_entries ADD COLUMN mode TEXT NOT NULL DEFAULT 'portion'");
  await db.execute('ALTER TABLE nutrition_entries ADD COLUMN meal TEXT');
  await db.execute('ALTER TABLE nutrition_entries ADD COLUMN grams REAL');
  await db.execute('ALTER TABLE nutrition_entries ADD COLUMN per100_kcal REAL');
  await db.execute('ALTER TABLE nutrition_entries ADD COLUMN per100_protein REAL');
  await db.execute('ALTER TABLE nutrition_entries ADD COLUMN per100_fat REAL');
  await db.execute('ALTER TABLE nutrition_entries ADD COLUMN per100_carbs REAL');
  await db.execute('ALTER TABLE nutrition_entries ADD COLUMN food_id TEXT');
  await db.execute('''
    CREATE TABLE nutrition_goals (
      id TEXT PRIMARY KEY,
      effective_from TEXT NOT NULL,
      calories REAL,
      protein REAL,
      fat REAL,
      carbs REAL
    )''');
  // The old single (undated) goal row keeps applying to all past days,
  // exactly as before; new goals get explicit effective dates.
  await db.execute('''
    INSERT INTO nutrition_goals (id, effective_from, calories, protein, fat, carbs)
    SELECT id, '1970-01-01',
      CASE WHEN calories > 0 THEN calories END,
      CASE WHEN protein > 0 THEN protein END,
      CASE WHEN fat > 0 THEN fat END,
      CASE WHEN carbs > 0 THEN carbs END
    FROM user_goals ORDER BY rowid DESC LIMIT 1''');
  await db.execute('CREATE INDEX idx_ne_date ON nutrition_entries(date)');
}

/// v3 -> v4: body weight measurements. Several rows per day are allowed by the
/// schema (nothing is merged or replaced silently); exactly one row per day is
/// flagged is_primary and used in calculations.
Future<void> migrateV3ToV4(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE body_weights (
      id TEXT PRIMARY KEY,
      date TEXT NOT NULL,
      kg REAL NOT NULL,
      is_primary INTEGER NOT NULL DEFAULT 1
    )''');
  await db.execute('CREATE INDEX idx_bw_date ON body_weights(date)');
}
