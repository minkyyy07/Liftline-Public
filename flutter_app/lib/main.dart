import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'validators.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDb.instance.init();
  runApp(const LiftlineApp());
}

class LiftlineApp extends StatelessWidget {
  const LiftlineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Liftline',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.dark,
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

// ---------------- Database Layer ----------------
class AppDb {
  static final AppDb instance = AppDb._();
  AppDb._();

  Database? _db;
  Database get db => _db!;

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'liftline.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE workouts (
            id TEXT PRIMARY KEY,
            date TEXT NOT NULL,
            title TEXT NOT NULL,
            duration_minutes INTEGER,
            notes TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE workout_exercises (
            id TEXT PRIMARY KEY,
            workout_id TEXT NOT NULL,
            exercise_name TEXT NOT NULL,
            sort_order INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE set_entries (
            id TEXT PRIMARY KEY,
            exercise_id TEXT NOT NULL,
            set_number INTEGER NOT NULL,
            weight_kg REAL NOT NULL,
            reps INTEGER NOT NULL,
            completed INTEGER NOT NULL DEFAULT 1
          )
        ''');

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
          )
        ''');

        await db.execute('''
          CREATE TABLE user_goals (
            id TEXT PRIMARY KEY,
            calories INTEGER,
            protein REAL,
            fat REAL,
            carbs REAL
          )
        ''');
      },
    );
  }
}

// ---------------- Navigation Screen ----------------
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final screens = [
      DayOverviewScreen(
        selectedDate: _selectedDate,
        onDateChanged: (d) => setState(() => _selectedDate = d),
      ),
      WorkoutsScreen(selectedDate: _selectedDate),
      NutritionScreen(selectedDate: _selectedDate),
      const ExerciseHistoryScreen(),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Обзор дня',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: 'Тренировки',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_outlined),
            selectedIcon: Icon(Icons.restaurant),
            label: 'Питание',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart),
            label: 'Прогресс',
          ),
        ],
      ),
    );
  }
}

// ---------------- 1. Обзор дня ----------------
class DayOverviewScreen extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;

  const DayOverviewScreen({
    super.key,
    required this.selectedDate,
    required this.onDateChanged,
  });

  @override
  State<DayOverviewScreen> createState() => _DayOverviewScreenState();
}

class _DayOverviewScreenState extends State<DayOverviewScreen> {
  int _calories = 0;
  double _protein = 0;
  double _fat = 0;
  double _carbs = 0;
  List<Map<String, dynamic>> _workouts = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant DayOverviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) {
      _loadData();
    }
  }

  String _dateStr(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _loadData() async {
    final date = _dateStr(widget.selectedDate);
    final nutrition = await AppDb.instance.db.query(
      'nutrition_entries',
      where: 'date = ?',
      whereArgs: [date],
    );

    int cals = 0;
    double p = 0;
    double f = 0;
    double c = 0;
    for (final row in nutrition) {
      cals += (row['calories'] as int? ?? 0);
      p += ((row['protein'] as num?)?.toDouble() ?? 0.0);
      f += ((row['fat'] as num?)?.toDouble() ?? 0.0);
      c += ((row['carbs'] as num?)?.toDouble() ?? 0.0);
    }

    final workouts = await AppDb.instance.db.query(
      'workouts',
      where: 'date = ?',
      whereArgs: [date],
    );

    if (mounted) {
      setState(() {
        _calories = cals;
        _protein = p;
        _fat = f;
        _carbs = c;
        _workouts = workouts;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d MMMM yyyy, EEEE');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Liftline • Обзор дня'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.event, color: Colors.blueAccent),
                title: Text(
                  dateFormat.format(widget.selectedDate),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: const Icon(Icons.arrow_drop_down),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: widget.selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) widget.onDateChanged(picked);
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Питание и калории',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$_calories',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.orangeAccent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('ккал', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _MacroItem(label: 'Белки', value: '${_protein.toStringAsFixed(1)}г', color: Colors.blue),
                        _MacroItem(label: 'Жиры', value: '${_fat.toStringAsFixed(1)}г', color: Colors.amber),
                        _MacroItem(label: 'Углеводы', value: '${_carbs.toStringAsFixed(1)}г', color: Colors.green),
                      ],
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Тренировки за день',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_workouts.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text('На эту дату тренировок нет', style: TextStyle(color: Colors.grey)),
                  ),
                ),
              )
            else
              ..._workouts.map(
                (w) => Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.blueAccent,
                      child: Icon(Icons.fitness_center, color: Colors.white),
                    ),
                    title: Text(w['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Длительность: ${w['duration_minutes'] ?? 0} мин'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MacroItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MacroItem({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

// ---------------- 2. Тренировки ----------------
class WorkoutsScreen extends StatefulWidget {
  final DateTime selectedDate;
  const WorkoutsScreen({super.key, required this.selectedDate});

  @override
  State<WorkoutsScreen> createState() => _WorkoutsScreenState();
}

class _WorkoutsScreenState extends State<WorkoutsScreen> {
  List<Map<String, dynamic>> _workouts = [];

  @override
  void initState() {
    super.initState();
    _loadWorkouts();
  }

  @override
  void didUpdateWidget(covariant WorkoutsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) {
      _loadWorkouts();
    }
  }

  String _dateStr(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _loadWorkouts() async {
    final list = await AppDb.instance.db.query(
      'workouts',
      where: 'date = ?',
      whereArgs: [_dateStr(widget.selectedDate)],
    );
    if (mounted) setState(() => _workouts = list);
  }

  Future<void> _createWorkout() async {
    final formKey = GlobalKey<FormState>();
    final titleCtrl = TextEditingController();
    final durCtrl = TextEditingController(text: '60');

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новая тренировка'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Название (напр. Спина / Бицепс) *'),
                validator: (v) => InputValidators.validateRequiredText(v, 'Название'),
              ),
              TextFormField(
                controller: durCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Длительность (мин) *'),
                validator: (v) => InputValidators.validatePositiveInt(v, 'Длительность'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );

    if (created == true) {
      final id = const Uuid().v4();
      await AppDb.instance.db.insert('workouts', {
        'id': id,
        'date': _dateStr(widget.selectedDate),
        'title': titleCtrl.text.trim(),
        'duration_minutes': InputValidators.parsePositiveInt(durCtrl.text) ?? 60,
      });
      _loadWorkouts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Журнал тренировок'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createWorkout,
          )
        ],
      ),
      body: _workouts.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.fitness_center, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('Нет тренировок за этот день', style: TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _createWorkout,
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить тренировку'),
                  )
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _workouts.length,
              itemBuilder: (ctx, i) {
                final w = _workouts[i];
                return Card(
                  child: ListTile(
                    title: Text(w['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${w['duration_minutes'] ?? 0} мин'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WorkoutDetailScreen(workout: w),
                        ),
                      );
                      _loadWorkouts();
                    },
                  ),
                );
              },
            ),
    );
  }
}

// ---------------- Детали тренировки (Упражнения и подходы) ----------------
class WorkoutDetailScreen extends StatefulWidget {
  final Map<String, dynamic> workout;
  const WorkoutDetailScreen({super.key, required this.workout});

  @override
  State<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen> {
  List<Map<String, dynamic>> _exercises = [];
  Map<String, List<Map<String, dynamic>>> _setsByExercise = {};

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final exercises = await AppDb.instance.db.query(
      'workout_exercises',
      where: 'workout_id = ?',
      whereArgs: [widget.workout['id']],
      orderBy: 'sort_order ASC',
    );

    final Map<String, List<Map<String, dynamic>>> setsMap = {};
    for (final ex in exercises) {
      final sets = await AppDb.instance.db.query(
        'set_entries',
        where: 'exercise_id = ?',
        whereArgs: [ex['id']],
        orderBy: 'set_number ASC',
      );
      setsMap[ex['id'] as String] = sets;
    }

    if (mounted) {
      setState(() {
        _exercises = exercises;
        _setsByExercise = setsMap;
      });
    }
  }

  Future<void> _addExercise() async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить упражнение'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'Название упражнения (напр. Жим лежа) *'),
            validator: (v) => InputValidators.validateRequiredText(v, 'Название упражнения'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );

    if (res == true) {
      final id = const Uuid().v4();
      await AppDb.instance.db.insert('workout_exercises', {
        'id': id,
        'workout_id': widget.workout['id'],
        'exercise_name': nameCtrl.text.trim(),
        'sort_order': _exercises.length + 1,
      });
      _loadDetails();
    }
  }

  Future<void> _addSet(String exerciseId) async {
    final formKey = GlobalKey<FormState>();
    final currentSets = _setsByExercise[exerciseId] ?? [];
    final weightCtrl = TextEditingController(text: currentSets.isNotEmpty ? currentSets.last['weight_kg'].toString() : '60');
    final repsCtrl = TextEditingController(text: currentSets.isNotEmpty ? currentSets.last['reps'].toString() : '10');

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Подход #${currentSets.length + 1}'),
        content: Form(
          key: formKey,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: weightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Вес (кг) *'),
                  validator: (v) => InputValidators.validateNonNegativeDouble(v, 'Вес'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: repsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Повторения *'),
                  validator: (v) => InputValidators.validatePositiveInt(v, 'Повторения'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (res == true) {
      final id = const Uuid().v4();
      await AppDb.instance.db.insert('set_entries', {
        'id': id,
        'exercise_id': exerciseId,
        'set_number': currentSets.length + 1,
        'weight_kg': InputValidators.parseNonNegativeDouble(weightCtrl.text)!,
        'reps': InputValidators.parsePositiveInt(repsCtrl.text)!,
        'completed': 1,
      });
      _loadDetails();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.workout['title'] as String),
      ),
      body: _exercises.isEmpty
          ? Center(
              child: ElevatedButton.icon(
                onPressed: _addExercise,
                icon: const Icon(Icons.add),
                label: const Text('Добавить первое упражнение'),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _exercises.length,
              itemBuilder: (ctx, i) {
                final ex = _exercises[i];
                final sets = _setsByExercise[ex['id']] ?? [];

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              ex['exercise_name'] as String,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            TextButton.icon(
                              onPressed: () => _addSet(ex['id'] as String),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Подход'),
                            ),
                          ],
                        ),
                        const Divider(),
                        if (sets.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('Подходов пока нет', style: TextStyle(color: Colors.grey)),
                          )
                        else
                          ...sets.map(
                            (s) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundColor: Colors.blueGrey,
                                    child: Text(
                                      '${s['set_number']}',
                                      style: const TextStyle(fontSize: 12, color: Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Text('${s['weight_kg']} кг  ×  ${s['reps']} повт.'),
                                  const Spacer(),
                                  const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addExercise,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ---------------- 3. Питание ----------------
class NutritionScreen extends StatefulWidget {
  final DateTime selectedDate;
  const NutritionScreen({super.key, required this.selectedDate});

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  List<Map<String, dynamic>> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  @override
  void didUpdateWidget(covariant NutritionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) {
      _loadEntries();
    }
  }

  String _dateStr(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _loadEntries() async {
    final list = await AppDb.instance.db.query(
      'nutrition_entries',
      where: 'date = ?',
      whereArgs: [_dateStr(widget.selectedDate)],
    );
    if (mounted) setState(() => _entries = list);
  }

  Future<void> _addFood() async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final portionCtrl = TextEditingController(text: '100г');
    final calsCtrl = TextEditingController();
    final pCtrl = TextEditingController();
    final fCtrl = TextEditingController();
    final carbCtrl = TextEditingController();

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить прием пищи / продукт'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Название (напр. Овсянка) *'),
                  validator: (v) => InputValidators.validateRequiredText(v, 'Название'),
                ),
                TextFormField(
                  controller: portionCtrl,
                  decoration: const InputDecoration(labelText: 'Порция (напр. 150г, необязательно)'),
                ),
                TextFormField(
                  controller: calsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Калории (ккал) *'),
                  validator: (v) => InputValidators.validateNonNegativeInt(v, 'Калории'),
                ),
                TextFormField(
                  controller: pCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Белки (г, необязательно)'),
                  validator: (v) => InputValidators.validateNonNegativeDouble(v, 'Белки', required: false),
                ),
                TextFormField(
                  controller: fCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Жиры (г, необязательно)'),
                  validator: (v) => InputValidators.validateNonNegativeDouble(v, 'Жиры', required: false),
                ),
                TextFormField(
                  controller: carbCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Углеводы (г, необязательно)'),
                  validator: (v) => InputValidators.validateNonNegativeDouble(v, 'Углеводы', required: false),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );

    if (res == true) {
      final id = const Uuid().v4();
      await AppDb.instance.db.insert('nutrition_entries', {
        'id': id,
        'date': _dateStr(widget.selectedDate),
        'name': nameCtrl.text.trim(),
        'portion': InputValidators.parseOptionalText(portionCtrl.text),
        'calories': InputValidators.parseNonNegativeInt(calsCtrl.text)!,
        'protein': InputValidators.parseNonNegativeDouble(pCtrl.text, defaultValue: 0.0)!,
        'fat': InputValidators.parseNonNegativeDouble(fCtrl.text, defaultValue: 0.0)!,
        'carbs': InputValidators.parseNonNegativeDouble(carbCtrl.text, defaultValue: 0.0)!,
      });
      _loadEntries();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Учёт питания'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addFood,
          ),
        ],
      ),
      body: _entries.isEmpty
          ? Center(
              child: ElevatedButton.icon(
                onPressed: _addFood,
                icon: const Icon(Icons.add),
                label: const Text('Записать приём пищи'),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _entries.length,
              itemBuilder: (ctx, i) {
                final item = _entries[i];
                return Card(
                  child: ListTile(
                    title: Text(item['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      '${item['portion'] ?? ''} • ${item['calories']} ккал (Б:${item['protein']}г, Ж:${item['fat']}г, У:${item['carbs']}г)',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () async {
                        await AppDb.instance.db.delete('nutrition_entries', where: 'id = ?', whereArgs: [item['id']]);
                        _loadEntries();
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ---------------- 4. Прогресс и история ----------------
class ExerciseHistoryScreen extends StatefulWidget {
  const ExerciseHistoryScreen({super.key});

  @override
  State<ExerciseHistoryScreen> createState() => _ExerciseHistoryScreenState();
}

class _ExerciseHistoryScreenState extends State<ExerciseHistoryScreen> {
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final list = await AppDb.instance.db.rawQuery('''
      SELECT e.exercise_name, w.date, s.weight_kg, s.reps, s.set_number
      FROM set_entries s
      JOIN workout_exercises e ON s.exercise_id = e.id
      JOIN workouts w ON e.workout_id = w.id
      ORDER BY e.exercise_name ASC, w.date DESC, s.set_number ASC
    ''');
    if (mounted) setState(() => _history = list);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Прогресс по упражнениям'),
      ),
      body: _history.isEmpty
          ? const Center(
              child: Text(
                'История пуста. Добавьте подходы в тренировках!',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _history.length,
              itemBuilder: (ctx, i) {
                final row = _history[i];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.trending_up, color: Colors.blueAccent),
                    title: Text(row['exercise_name'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Дата: ${row['date']} • Подход #${row['set_number']}'),
                    trailing: Text(
                      '${row['weight_kg']} кг × ${row['reps']}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
