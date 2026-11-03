import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'db.dart';
import 'repo.dart';
import 'rest_timer.dart';
import 'theme.dart';
import 'validators.dart';
import 'week_utils.dart';

WorkoutRepo get _repo => WorkoutRepo(AppDb.instance.db);

void _snack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));

Future<bool> _confirm(
  BuildContext c,
  String title,
  String body, {
  String ok = 'Удалить',
}) async {
  final r = await showDialog<bool>(
    context: c,
    builder:
        (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ok),
            ),
          ],
        ),
  );
  return r == true;
}

String _kg(Object? v) {
  final d = (v as num?)?.toDouble() ?? 0;
  return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
}

// ====================== Список тренировок ======================
class WorkoutsScreen extends StatefulWidget {
  final DateTime selectedDate;
  const WorkoutsScreen({super.key, required this.selectedDate});

  @override
  State<WorkoutsScreen> createState() => _WorkoutsScreenState();
}

class _WorkoutsScreenState extends State<WorkoutsScreen> {
  List<Rec> _list = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await _repo.listWorkouts();
      if (mounted) {
        setState(() {
          _list = l;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _open(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WorkoutOverviewScreen(workoutId: id)),
    );
    _load();
  }

  Future<void> _create() async {
    final res = await showDialog<_NewWorkout>(
      context: context,
      builder: (_) => _NewWorkoutDialog(initialDate: widget.selectedDate),
    );
    if (res == null || !mounted) return;
    try {
      final id = await _repo.createWorkout(
        title: res.title,
        date: res.date,
        start: res.start,
      );
      await _load();
      if (mounted) await _open(id);
    } on ActiveWorkoutExists catch (e) {
      if (!mounted) return;
      final go = await _confirm(
        context,
        'Уже есть активная тренировка',
        'Вернитесь к ней или сначала завершите её. Данные не удаляются.',
        ok: 'Продолжить текущую',
      );
      if (go && mounted) _open(e.activeId);
    } catch (e) {
      if (mounted) _snack(context, 'Не удалось сохранить: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _list.where((w) => w['status'] == 'active').toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Тренировки'),
        actions: [
          IconButton(
            tooltip: 'Новая тренировка',
            icon: const Icon(Icons.add),
            onPressed: _create,
          ),
        ],
      ),
      body:
          _error != null
              ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Ошибка загрузки: $_error'),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              )
              : _loading
              ? const Center(child: CircularProgressIndicator())
              : _list.isEmpty
              ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 24,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          color: LlColors.surfaceHigh,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.fitness_center,
                          size: 48,
                          color: LlColors.accent,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Тренировок пока нет',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Создайте первую тренировку, чтобы планировать упражнения и фиксировать рабочие подходы.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: LlColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _create,
                        icon: const Icon(Icons.add),
                        label: const Text('Создать тренировку'),
                      ),
                    ],
                  ),
                ),
              )
              : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    for (final w in active)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          color: LlColors.surfaceHigh,
                          child: ListTile(
                            leading: const Icon(
                              Icons.play_circle,
                              color: LlColors.accent,
                            ),
                            title: Text('Идёт: ${w['title']}'),
                            subtitle: const Text('Нажмите, чтобы продолжить'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _open(w['id'] as String),
                          ),
                        ),
                      ),
                    for (final w in _list.where((w) => w['status'] != 'active'))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            title: Text(
                              w['title'] as String,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${w['date']} • ${_statusLabel(w['status'] as String)} • '
                              'упр.: ${w['ex_count']} • подходов: ${w['done_sets']}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _open(w['id'] as String),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
    );
  }
}

String _statusLabel(String s) => switch (s) {
  'active' => 'идёт',
  'planned' => 'запланирована',
  _ => 'завершена',
};

class _NewWorkout {
  final String title;
  final DateTime date;
  final bool start;
  _NewWorkout(this.title, this.date, this.start);
}

class _NewWorkoutDialog extends StatefulWidget {
  final DateTime initialDate;
  const _NewWorkoutDialog({required this.initialDate});
  @override
  State<_NewWorkoutDialog> createState() => _NewWorkoutDialogState();
}

class _NewWorkoutDialogState extends State<_NewWorkoutDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(text: 'Тренировка');
  late DateTime _date = dateOnly(widget.initialDate);
  String? _dateError;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMMM yyyy', 'ru');
    return AlertDialog(
      title: const Text('Новая тренировка'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Название *'),
              validator:
                  (v) => InputValidators.validateRequiredText(v, 'Название'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text('Дата записи: ${fmt.format(_date)}'),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                );
                if (d != null) {
                  setState(() {
                    _date = dateOnly(d);
                    _dateError = null;
                  });
                }
              },
            ),
            const SizedBox(height: 8),
            const Text(
              '«Начать сейчас» запускает тренировку сегодняшним числом. '
              '«Записать завершённой» вносит прошедшую тренировку на выбранную дату.',
              style: TextStyle(fontSize: 12, color: LlColors.textSecondary),
            ),
            if (_dateError != null)
              Text(_dateError!, style: const TextStyle(color: LlColors.error)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        OutlinedButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            if (_date.isAfter(dateOnly(DateTime.now()))) {
              setState(
                () =>
                    _dateError =
                        'Завершённую тренировку нельзя записать на будущую дату',
              );
              return;
            }
            Navigator.pop(context, _NewWorkout(_title.text, _date, false));
          },
          child: const Text('Записать завершённой'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              _NewWorkout(_title.text, DateTime.now(), true),
            );
          },
          child: const Text('Начать сейчас'),
        ),
      ],
    );
  }
}

// ====================== Обзор занятия ======================
class WorkoutOverviewScreen extends StatefulWidget {
  final String workoutId;
  const WorkoutOverviewScreen({super.key, required this.workoutId});
  @override
  State<WorkoutOverviewScreen> createState() => _WorkoutOverviewScreenState();
}

class _WorkoutOverviewScreenState extends State<WorkoutOverviewScreen> {
  Rec? _w;
  List<Rec> _exercises = [];
  Map<String, List<Rec>> _sets = {};
  bool _busy = false;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = _repo;
    final w = await r.workout(widget.workoutId);
    final ex = await r.workoutExercises(widget.workoutId);
    final m = {
      for (final e in ex) e['id'] as String: await r.sets(e['id'] as String),
    };
    if (mounted && !_gone) {
      setState(() {
        _w = w;
        _exercises = ex;
        _sets = m;
      });
    }
  }

  Future<void> _openExercise(int i) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ExerciseScreen(
              workoutId: widget.workoutId,
              exerciseIds: _exercises.map((e) => e['id'] as String).toList(),
              initialIndex: i,
            ),
      ),
    );
    _load();
  }

  Future<void> _addExercise() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _AddExerciseDialog(),
    );
    if (name == null) return;
    await _repo.addExercise(widget.workoutId, name);
    _load();
  }

  Future<void> _finish() async {
    if (_busy) return;
    _busy = true;
    try {
      final s = await _repo.summary(widget.workoutId);
      if (!mounted) return;
      final extra =
          s.done == 0
              ? '\nНет выполненных подходов: такая тренировка не создаст силовых результатов.'
              : '';
      final ok = await _confirm(
        context,
        'Завершить тренировку?',
        'Выполнено подходов: ${s.done}, осталось: ${s.remaining}.\n'
            'Невыполненные подходы не станут выполненными и сохранятся.$extra',
        ok: 'Завершить',
      );
      if (!ok) return;
      await _repo.finishWorkout(widget.workoutId);
      await RestTimerController.instance.stop();
      await _load();
    } finally {
      _busy = false;
    }
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: _w!['title'] as String);
    final t = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Название'),
            content: TextField(controller: c, autofocus: true),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () {
                  if (c.text.trim().isNotEmpty) Navigator.pop(ctx, c.text);
                },
                child: const Text('Сохранить'),
              ),
            ],
          ),
    );
    if (t != null) {
      await _repo.renameWorkout(widget.workoutId, t);
      _load();
    }
  }

  Future<void> _changeDate() async {
    final cur = DateTime.parse(_w!['date'] as String);
    final d = await showDatePicker(
      context: context,
      initialDate: cur,
      firstDate: DateTime(2020),
      lastDate: dateOnly(DateTime.now()),
    );
    if (d != null) {
      await _repo.changeWorkoutDate(widget.workoutId, d);
      _load();
    }
  }

  Future<void> _delete() async {
    final n = _sets.values.fold<int>(0, (a, l) => a + l.length);
    final ok = await _confirm(
      context,
      'Удалить тренировку?',
      'Будут удалены упражнения этой тренировки (${_exercises.length}) и все её подходы ($n). '
          'Справочник упражнений и другие тренировки не затрагиваются.',
    );
    if (!ok) return;
    _gone = true;
    await _repo.deleteWorkout(widget.workoutId);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _repeat() async {
    final id = await _repo.repeatWorkout(
      widget.workoutId,
      date: DateTime.now(),
    );
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => WorkoutOverviewScreen(workoutId: id)),
    );
  }

  Future<void> _start() async {
    try {
      await _repo.startWorkout(widget.workoutId);
      _load();
    } on ActiveWorkoutExists catch (e) {
      if (!mounted) return;
      final go = await _confirm(
        context,
        'Уже есть активная тренировка',
        'Вернитесь к ней или завершите её.',
        ok: 'Продолжить текущую',
      );
      if (go && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => WorkoutOverviewScreen(workoutId: e.activeId),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = _w;
    if (w == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final status = w['status'] as String;
    final dur = w['duration_minutes'];
    return Scaffold(
      appBar: AppBar(
        title: Text(w['title'] as String, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'rename':
                  _rename();
                case 'date':
                  _changeDate();
                case 'repeat':
                  _repeat();
                case 'delete':
                  _delete();
              }
            },
            itemBuilder:
                (_) => [
                  const PopupMenuItem(
                    value: 'rename',
                    child: Text('Переименовать'),
                  ),
                  if (status != 'active')
                    const PopupMenuItem(
                      value: 'date',
                      child: Text('Изменить дату'),
                    ),
                  const PopupMenuItem(
                    value: 'repeat',
                    child: Text('Повторить тренировку'),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Удалить тренировку'),
                  ),
                ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Text(
            '${w['date']} • ${_statusLabel(status)}'
            '${dur != null ? ' • $dur мин' : ''}',
            style: const TextStyle(color: LlColors.textSecondary),
          ),
          const SizedBox(height: 12),
          if (_exercises.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text('В занятии пока нет упражнений'),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _addExercise,
                      child: const Text('Добавить упражнение'),
                    ),
                  ],
                ),
              ),
            ),
          for (var i = 0; i < _exercises.length; i++) _exerciseCard(i),
        ],
      ),
      floatingActionButton:
          _exercises.isEmpty
              ? null
              : FloatingActionButton.extended(
                onPressed: _addExercise,
                icon: const Icon(Icons.add),
                label: const Text('Упражнение'),
              ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: switch (status) {
            'active' => FilledButton(
              onPressed: _finish,
              child: const Text('Завершить тренировку'),
            ),
            'planned' => FilledButton(
              onPressed: _start,
              child: const Text('Начать сейчас'),
            ),
            _ => OutlinedButton(
              onPressed: _repeat,
              child: const Text('Повторить тренировку'),
            ),
          },
        ),
      ),
    );
  }

  Widget _exerciseCard(int i) {
    final e = _exercises[i];
    final sets = _sets[e['id']] ?? [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openExercise(i),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e['exercise_name'] as String,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Выше',
                      icon: const Icon(Icons.arrow_upward),
                      onPressed:
                          i == 0
                              ? null
                              : () async {
                                await _repo.moveExercise(e['id'] as String, -1);
                                _load();
                              },
                    ),
                    IconButton(
                      tooltip: 'Ниже',
                      icon: const Icon(Icons.arrow_downward),
                      onPressed:
                          i == _exercises.length - 1
                              ? null
                              : () async {
                                await _repo.moveExercise(e['id'] as String, 1);
                                _load();
                              },
                    ),
                    IconButton(
                      tooltip: 'Убрать из занятия',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await _confirm(
                          context,
                          'Убрать упражнение?',
                          'Будут удалены подходы этого упражнения в данной тренировке (${sets.length}). '
                              'История других занятий не меняется.',
                        );
                        if (ok) {
                          await _repo.removeExercise(e['id'] as String);
                          _load();
                        }
                      },
                    ),
                  ],
                ),
                if (sets.isEmpty)
                  const Text(
                    'Подходов нет',
                    style: TextStyle(color: LlColors.textSecondary),
                  )
                else
                  for (final s in sets)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            child: Text(
                              s['set_type'] == 'warmup'
                                  ? 'Р'
                                  : '${s['set_number']}',
                              style: const TextStyle(
                                color: LlColors.textSecondary,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${_kg(s['weight_kg'])} кг × ${s['reps']}'
                              '${s['rir'] != null ? '  RIR ${s['rir']}' : ''}',
                            ),
                          ),
                          Icon(
                            s['completed'] == 1
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 20,
                            color:
                                s['completed'] == 1
                                    ? LlColors.accent
                                    : LlColors.textSecondary,
                          ),
                          const SizedBox(width: 12),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddExerciseDialog extends StatefulWidget {
  const _AddExerciseDialog();
  @override
  State<_AddExerciseDialog> createState() => _AddExerciseDialogState();
}

class _AddExerciseDialogState extends State<_AddExerciseDialog> {
  final _form = GlobalKey<FormState>();
  final _c = TextEditingController();
  List<String> _names = [];

  @override
  void initState() {
    super.initState();
    _repo.activeExercises().then((l) {
      if (mounted) {
        setState(() => _names = l.map((r) => r['name'] as String).toList());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Добавить упражнение'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _c,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Название упражнения *',
              ),
              validator:
                  (v) => InputValidators.validateRequiredText(v, 'Название'),
            ),
            if (_names.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Из справочника:',
                  style: TextStyle(fontSize: 12, color: LlColors.textSecondary),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (final n in _names)
                        ActionChip(
                          label: Text(n),
                          onPressed: () => setState(() => _c.text = n),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            if (_form.currentState!.validate()) {
              Navigator.pop(context, _c.text.trim());
            }
          },
          child: const Text('Добавить'),
        ),
      ],
    );
  }
}

// ====================== Активное упражнение ======================
class ExerciseScreen extends StatefulWidget {
  final String workoutId;
  final List<String> exerciseIds;
  final int initialIndex;
  const ExerciseScreen({
    super.key,
    required this.workoutId,
    required this.exerciseIds,
    required this.initialIndex,
  });
  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> {
  late int _index = widget.initialIndex;
  Rec? _workout;
  Rec? _we;
  List<Rec> _sets = [];
  List<Rec> _prev = [];
  Timer? _clock;

  String get _weId => widget.exerciseIds[_index];
  bool get _active => _workout?['status'] == 'active';

  @override
  void initState() {
    super.initState();
    _load();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final r = _repo;
    final w = await r.workout(widget.workoutId);
    final exs = await r.workoutExercises(widget.workoutId);
    final we = exs.firstWhere((e) => e['id'] == _weId, orElse: () => exs.first);
    final sets = await r.sets(_weId);
    final ref = we['exercise_ref_id'] as String?;
    final prev =
        ref == null ? <Rec>[] : await r.previousSets(ref, widget.workoutId);
    if (mounted) {
      setState(() {
        _workout = w;
        _we = we;
        _sets = sets;
        _prev = prev;
      });
    }
  }

  void _go(int delta) {
    final n = _index + delta;
    if (n < 0 || n >= widget.exerciseIds.length) return;
    setState(() {
      _index = n;
      _sets = [];
    });
    _load(); // values are saved on every valid edit; nothing is lost
  }

  int get _restSec => (_we?['plan_rest_sec'] as int?) ?? kDefaultRestSec;

  Future<void> _toggle(String setId, bool value) async {
    final newly = await _repo.setCompleted(setId, value);
    if (newly && _active && _restSec > 0) {
      await RestTimerController.instance.start(_restSec);
    }
    _load();
  }

  Future<void> _addSet() async {
    await _repo.addSet(_weId);
    _load();
  }

  String _planText() {
    final e = _we!;
    final parts = <String>[];
    if (e['plan_sets'] != null) parts.add('${e['plan_sets']} подх.');
    if (e['plan_rep_min'] != null) {
      parts.add(
        e['plan_rep_max'] != null && e['plan_rep_max'] != e['plan_rep_min']
            ? '${e['plan_rep_min']}–${e['plan_rep_max']} повт.'
            : '${e['plan_rep_min']} повт.',
      );
    }
    if (e['plan_rir'] != null) parts.add('RIR ${e['plan_rir']}');
    if (e['plan_rest_sec'] != null) {
      parts.add(
        e['plan_rest_sec'] == 0
            ? 'без таймера'
            : 'отдых ${e['plan_rest_sec']} с',
      );
    }
    return parts.isEmpty ? 'План не задан' : parts.join(' • ');
  }

  Future<void> _editPlan() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _PlanDialog(we: _we!),
    );
    if (ok == true) _load();
  }

  Future<void> _history() async {
    final ref = _we!['exercise_ref_id'] as String?;
    if (ref == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ExerciseHistoryDetailScreen(
              refId: ref,
              title: _we!['exercise_name'] as String,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final we = _we, w = _workout;
    if (we == null || w == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    String elapsed = '';
    final st = w['started_at_utc'] as int?;
    if (_active && st != null) {
      final d = DateTime.now().toUtc().difference(
        DateTime.fromMillisecondsSinceEpoch(st, isUtc: true),
      );
      elapsed = '${d.inMinutes} мин';
    }
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              w['title'] as String,
              style: const TextStyle(
                fontSize: 12,
                color: LlColors.textSecondary,
              ),
            ),
            Text(
              we['exercise_name'] as String,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'history':
                  _history();
                case 'plan':
                  _editPlan();
              }
            },
            itemBuilder:
                (_) => const [
                  PopupMenuItem(
                    value: 'history',
                    child: Text('История упражнения'),
                  ),
                  PopupMenuItem(value: 'plan', child: Text('План и заметка')),
                ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (elapsed.isNotEmpty)
            Text(
              'Длительность тренировки: $elapsed',
              style: const TextStyle(color: LlColors.textSecondary),
            ),
          Text(
            _planText(),
            style: const TextStyle(color: LlColors.textSecondary),
          ),
          if ((we['note'] as String?)?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Заметка: ${we['note']}'),
            ),
          const SizedBox(height: 12),
          const Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  '№',
                  style: TextStyle(color: LlColors.textSecondary),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Вес, кг',
                  style: TextStyle(color: LlColors.textSecondary),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Text(
                  'Повторы',
                  style: TextStyle(color: LlColors.textSecondary),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Text(
                  'RIR',
                  style: TextStyle(color: LlColors.textSecondary),
                ),
              ),
              SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < _sets.length; i++)
            _SetRow(
              key: ValueKey(_sets[i]['id']),
              row: _sets[i],
              prev: _prevFor(i),
              onToggle: _toggle,
              onChanged: _load,
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _addSet,
            icon: const Icon(Icons.add),
            label: const Text('Добавить подход'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TimerBar(restSec: _restSec),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: _index > 0 ? () => _go(-1) : null,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Предыдущее'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed:
                        _index < widget.exerciseIds.length - 1
                            ? () => _go(1)
                            : null,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Следующее'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// N-th working set vs N-th previous working set (warm-ups not counted).
  String? _prevFor(int i) {
    if (_sets[i]['set_type'] == 'warmup') return null;
    final n =
        _sets.take(i + 1).where((s) => s['set_type'] != 'warmup').length - 1;
    if (n < _prev.length) {
      final p = _prev[n];
      return 'Пред.: ${_kg(p['weight_kg'])}×${p['reps']}';
    }
    return null;
  }
}

class _TimerBar extends StatelessWidget {
  final int restSec;
  const _TimerBar({required this.restSec});

  @override
  Widget build(BuildContext context) {
    final t = RestTimerController.instance;
    return ListenableBuilder(
      listenable: t,
      builder: (_, __) {
        final rem = t.remaining;
        if (rem == Duration.zero) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 18,
                  color: LlColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  restSec == 0 ? 'Таймер отдыха выключен' : 'Отдых: $restSec с',
                  style: const TextStyle(color: LlColors.textSecondary),
                ),
              ],
            ),
          );
        }
        final mm = rem.inMinutes.toString().padLeft(2, '0');
        final ss = (rem.inSeconds % 60).toString().padLeft(2, '0');
        return Container(
          color: LlColors.surfaceHigh,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.timer, color: LlColors.accent),
              const SizedBox(width: 8),
              Text(
                '$mm:$ss',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '−15 с',
                icon: const Icon(Icons.remove),
                onPressed: () => t.adjust(-15),
              ),
              IconButton(
                tooltip: '+15 с',
                icon: const Icon(Icons.add),
                onPressed: () => t.adjust(15),
              ),
              IconButton(
                tooltip: 'Остановить',
                icon: const Icon(Icons.stop),
                onPressed: t.stop,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SetRow extends StatefulWidget {
  final Rec row;
  final String? prev;
  final Future<void> Function(String id, bool value) onToggle;
  final VoidCallback onChanged;
  const _SetRow({
    super.key,
    required this.row,
    required this.prev,
    required this.onToggle,
    required this.onChanged,
  });
  @override
  State<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<_SetRow> {
  late final _w = TextEditingController(text: _kg(widget.row['weight_kg']));
  late final _r = TextEditingController(text: '${widget.row['reps']}');
  late final _i = TextEditingController(
    text: widget.row['rir']?.toString() ?? '',
  );
  String? _wErr, _rErr, _iErr;
  bool _toggling = false;

  String get _id => widget.row['id'] as String;
  bool get _done => widget.row['completed'] == 1;
  bool get _warm => widget.row['set_type'] == 'warmup';

  @override
  void didUpdateWidget(covariant _SetRow old) {
    super.didUpdateWidget(old);
    // keep user's text; only sync when DB value differs and field is valid-equal
  }

  /// Validates all fields; saves each valid one immediately (never overwrites
  /// the last valid saved value with an invalid input).
  Future<bool> _save() async {
    final we = InputValidators.validateNonNegativeDouble(_w.text, 'Вес');
    final re = InputValidators.validatePositiveInt(_r.text, 'Повторы');
    String? ie;
    if (_i.text.trim().isNotEmpty) {
      final v = int.tryParse(_i.text.trim());
      if (v == null || v < 0 || v > 10) ie = 'RIR 0–10';
    }
    setState(() {
      _wErr = we == null ? null : 'Вес ≥ 0';
      _rErr = re == null ? null : 'Повторы ≥ 1';
      _iErr = ie;
    });
    await _repo.updateSet(
      _id,
      weight:
          we == null ? InputValidators.parseNonNegativeDouble(_w.text) : null,
      reps: re == null ? InputValidators.parsePositiveInt(_r.text) : null,
      rir:
          ie == null
              ? (_i.text.trim().isEmpty ? null : int.parse(_i.text.trim()))
              : kUnset,
    );
    return we == null && re == null && ie == null;
  }

  Future<void> _tapDone() async {
    if (_toggling) return;
    _toggling = true;
    try {
      if (!_done) {
        final ok = await _save();
        if (!ok) {
          if (mounted) {
            _snack(
              context,
              'Исправьте значения: вес ≥ 0, повторы ≥ 1, RIR 0–10',
            );
          }
          return;
        }
      }
      await widget.onToggle(_id, !_done);
    } finally {
      _toggling = false;
    }
  }

  Future<void> _menu() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.whatshot),
                  title: Text(
                    _warm ? 'Сделать рабочим' : 'Сделать разминочным',
                  ),
                  onTap: () => Navigator.pop(ctx, 'type'),
                ),
                ListTile(
                  leading: const Icon(Icons.notes),
                  title: const Text('Заметка к подходу'),
                  onTap: () => Navigator.pop(ctx, 'note'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Удалить подход'),
                  onTap: () => Navigator.pop(ctx, 'del'),
                ),
              ],
            ),
          ),
    );
    if (!mounted || v == null) return;
    if (v == 'type') {
      await _repo.updateSet(_id, type: _warm ? 'work' : 'warmup');
    } else if (v == 'note') {
      final c = TextEditingController(
        text: widget.row['note'] as String? ?? '',
      );
      final t = await showDialog<String>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Заметка к подходу'),
              content: TextField(controller: c, autofocus: true, maxLines: 3),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, c.text),
                  child: const Text('Сохранить'),
                ),
              ],
            ),
      );
      if (t == null) return;
      await _repo.updateSet(_id, note: t.trim().isEmpty ? null : t.trim());
    } else if (v == 'del') {
      final nonEmpty = _done || _w.text != '0' || _r.text != '1';
      if (nonEmpty) {
        final ok = await _confirm(
          context,
          'Удалить подход?',
          'Введённые значения будут потеряны.',
        );
        if (!ok) return;
      }
      await _repo.deleteSet(_id);
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.row['note'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: InkWell(
                  onTap: _menu,
                  child: Center(
                    child: Semantics(
                      label:
                          _warm
                              ? 'Разминочный подход'
                              : 'Подход ${widget.row['set_number']}',
                      child: Text(
                        _warm ? 'Р' : '${widget.row['set_number']}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _warm ? LlColors.warning : LlColors.text,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(flex: 3, child: _field(_w, _wErr, true)),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: _field(_r, _rErr, false)),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: _field(_i, _iErr, false)),
              SizedBox(
                width: 48,
                height: 48,
                child: Checkbox(
                  value: _done,
                  onChanged: (_) => _tapDone(),
                  activeColor: LlColors.accent,
                ),
              ),
            ],
          ),
          if (widget.prev != null || note != null)
            Padding(
              padding: const EdgeInsets.only(left: 48, top: 2),
              child: Text(
                [
                  if (widget.prev != null) widget.prev!,
                  if (note != null) 'Заметка: $note',
                ].join(' • '),
                style: const TextStyle(
                  fontSize: 12,
                  color: LlColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String? err, bool decimal) =>
      TextField(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'),
          ),
        ],
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 18,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        decoration: InputDecoration(
          errorText: err,
          errorStyle: const TextStyle(fontSize: 10),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 12,
            horizontal: 4,
          ),
          isDense: true,
        ),
        onChanged: (_) => _save(),
        onEditingComplete: () {
          _save();
          FocusScope.of(context).nextFocus();
        },
      );
}

// ---------- план упражнения ----------
class _PlanDialog extends StatefulWidget {
  final Rec we;
  const _PlanDialog({required this.we});
  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<_PlanDialog> {
  final _form = GlobalKey<FormState>();
  late final _sets = TextEditingController(
    text: '${widget.we['plan_sets'] ?? ''}',
  );
  late final _min = TextEditingController(
    text: '${widget.we['plan_rep_min'] ?? ''}',
  );
  late final _max = TextEditingController(
    text: '${widget.we['plan_rep_max'] ?? ''}',
  );
  late final _rir = TextEditingController(
    text: '${widget.we['plan_rir'] ?? ''}',
  );
  late final _rest = TextEditingController(
    text: '${widget.we['plan_rest_sec'] ?? ''}',
  );
  late final _note = TextEditingController(
    text: widget.we['note'] as String? ?? '',
  );

  String? _rirV(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = int.tryParse(v.trim());
    return (n == null || n < 0 || n > 10) ? 'RIR 0–10' : null;
  }

  Widget _f(
    String label,
    TextEditingController c,
    String? Function(String?) v,
  ) => TextFormField(
    controller: c,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    validator: v,
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('План и заметка'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _f(
                'Рабочих подходов',
                _sets,
                (v) => InputValidators.validatePositiveInt(
                  v,
                  'Подходы',
                  required: false,
                ),
              ),
              _f(
                'Повторов от',
                _min,
                (v) => InputValidators.validatePositiveInt(
                  v,
                  'Повторов от',
                  required: false,
                ),
              ),
              _f('Повторов до', _max, (v) {
                final e = InputValidators.validatePositiveInt(
                  v,
                  'Повторов до',
                  required: false,
                );
                if (e != null) return e;
                final a = int.tryParse(_min.text.trim()),
                    b = int.tryParse((v ?? '').trim());
                if (a != null && b != null && a > b) {
                  return 'Минимум больше максимума';
                }
                return null;
              }),
              _f('Целевой RIR (0–10)', _rir, _rirV),
              _f(
                'Отдых, с (0 — таймер выключен)',
                _rest,
                (v) => InputValidators.validateNonNegativeInt(
                  v,
                  'Отдых',
                  required: false,
                ),
              ),
              TextFormField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Заметка (техника, тренажёр)',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () async {
            if (!_form.currentState!.validate()) return;
            int? i(TextEditingController c) => int.tryParse(c.text.trim());
            await _repo.updatePlan(
              widget.we['id'] as String,
              sets: i(_sets),
              repMin: i(_min),
              repMax: i(_max),
              rir: i(_rir),
              restSec: i(_rest),
              note: InputValidators.parseOptionalText(_note.text),
            );
            if (context.mounted) Navigator.pop(context, true);
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

// ====================== История упражнения ======================
class ExerciseHistoryDetailScreen extends StatelessWidget {
  final String refId;
  final String title;
  const ExerciseHistoryDetailScreen({
    super.key,
    required this.refId,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('История: $title', overflow: TextOverflow.ellipsis),
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _repo.exerciseHistory(refId),
        builder: (ctx, snap) {
          if (snap.hasError) {
            return Center(child: Text('Ошибка: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return const Center(child: Text('Истории пока нет'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Вес в кг; «Р» — разминка (не входит в статистику). '
                'Объём = Σ вес × повторы выполненных рабочих подходов, кг·повт.',
                style: TextStyle(fontSize: 12, color: LlColors.textSecondary),
              ),
              const SizedBox(height: 8),
              for (final s in list)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${s['date']} • ${s['title']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if ((s['note'] as String?)?.isNotEmpty == true)
                          Text('Заметка: ${s['note']}'),
                        for (final st in (s['sets'] as List<Rec>))
                          Text(
                            '${st['set_type'] == 'warmup' ? 'Р' : st['set_number']}.  '
                            '${_kg(st['weight_kg'])} × ${st['reps']}'
                            '${st['rir'] != null ? '  RIR ${st['rir']}' : ''}'
                            '${st['completed'] == 1 ? '  ✓' : '  (не выполнен)'}'
                            '${st['note'] != null ? '  — ${st['note']}' : ''}',
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
