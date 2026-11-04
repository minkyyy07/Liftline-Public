import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'athletic_components.dart';
import 'auth/auth_service.dart';
import 'auth/cloud_workout_sync.dart';
import 'auth/login_screen.dart';
import 'auth/profile_screen.dart';
import 'calc.dart';
import 'data_events.dart';
import 'db.dart';
import 'repo.dart';
import 'rest_timer.dart';
import 'sync_status_badge.dart';
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
  StreamSubscription? _eventsSub;
  void Function()? _dbListener;

  @override
  void initState() {
    super.initState();
    _dbListener = () {
      if (mounted) _load(fromNetwork: true);
    };
    AppDb.instance.addDatabaseSwitchListener(_dbListener!);
    _eventsSub = AppDataEvents.instance.stream.listen((event) {
      if (event == AppDataCategory.workout && mounted) {
        _load(fromNetwork: false);
      }
    });
    _load(fromNetwork: true);
  }

  @override
  void dispose() {
    if (_dbListener != null) {
      AppDb.instance.removeDatabaseSwitchListener(_dbListener!);
    }
    _eventsSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool fromNetwork = false}) async {
    final accountUserId = AppDb.instance.currentUserId;
    final accountEpoch = AppDb.instance.accountEpoch;

    try {
      if (fromNetwork && AuthService.instance.isAuthenticated) {
        try {
          await CloudWorkoutSync().syncFromServer(AppDb.instance.db);
        } catch (_) {}
      }
      if (!AppDb.instance.isCurrentAccount(accountUserId, accountEpoch)) return;
      if (!mounted) return;

      final l = await _repo.listWorkouts();
      if (!AppDb.instance.isCurrentAccount(accountUserId, accountEpoch)) return;
      if (mounted) {
        setState(() {
          _list = l;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (!AppDb.instance.isCurrentAccount(accountUserId, accountEpoch)) return;
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
    try {
      final id = await showCreateWorkoutDialog(context, initialDate: widget.selectedDate);
      if (id == null || !mounted) return;
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
          ListenableBuilder(
            listenable: AuthService.instance,
            builder: (ctx, _) {
              final isAuth = AuthService.instance.isAuthenticated;
              final user = AuthService.instance.user;
              return IconButton(
                icon: CircleAvatar(
                  radius: 14,
                  backgroundColor: isAuth ? LlColors.secondary : Colors.white24,
                  child: Text(
                    isAuth
                        ? (user?.presentationName.substring(0, 1).toUpperCase() ?? 'U')
                        : '?',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
                tooltip: isAuth ? 'Профиль (${user?.presentationName})' : 'Войти в аккаунт',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => isAuth ? const ProfileScreen() : const LoginScreen(),
                    ),
                  ).then((_) => _load());
                },
              );
            },
          ),
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
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _open(w['id'] as String),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.play_circle,
                                    color: LlColors.accent,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Активная тренировка',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: LlColors.textSecondary,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          w['title'] as String? ?? '',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        SyncStatusBadge(
                                          workoutId: w['id'] as String,
                                          syncStatus: w['sync_status'] as String? ?? 'synced',
                                          syncError: w['sync_error'] as String?,
                                          onRetryFinished: () => _load(fromNetwork: false),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: LlColors.textSecondary,
                                  ),
                                ],
                              ),
                            ),
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
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${w['date']} • ${_statusLabel(w['status'] as String)} • '
                                  'упр.: ${w['ex_count']} • подходов: ${w['done_sets']}',
                                ),
                                SyncStatusBadge(
                                  workoutId: w['id'] as String,
                                  syncStatus: w['sync_status'] as String? ?? 'synced',
                                  syncError: w['sync_error'] as String?,
                                  onRetryFinished: () => _load(fromNetwork: false),
                                ),
                              ],
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

Future<String?> showCreateWorkoutDialog(
  BuildContext context, {
  required DateTime initialDate,
}) async {
  final res = await showDialog<_NewWorkout>(
    context: context,
    builder: (_) => _NewWorkoutDialog(initialDate: initialDate),
  );
  if (res == null) return null;
  final repo = WorkoutRepo(AppDb.instance.db);
  final id = await repo.createWorkout(
    title: res.title,
    date: res.date,
    start: res.status == 'active',
    status: res.status,
  );
  if (AuthService.instance.isAuthenticated) {
    try {
      await CloudWorkoutSync().pushWorkout(AppDb.instance.db, id);
    } catch (_) {}
  }
  return id;
}

class _NewWorkout {
  final String title;
  final DateTime date;
  final String status;
  _NewWorkout(this.title, this.date, {required this.status});
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
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMMM yyyy', 'ru');
    final isSelectedToday = isSameDay(_date, DateTime.now());
    return AlertDialog(
      title: const Text('Новая тренировка'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                label: Text('Дата: ${fmt.format(_date)}'),
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
                '«Запланировать» создает тренировку на выбранную дату.\n'
                '«Начать сейчас» запускает сессию сегодня.\n'
                '«Записать завершённой» вносит итоги прошедшей тренировки.',
                style: TextStyle(fontSize: 12, color: LlColors.textSecondary),
              ),
              if (_dateError != null) ...[
                const SizedBox(height: 6),
                Text(_dateError!, style: const TextStyle(color: LlColors.error, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        OutlinedButton(
          onPressed: _submitting ? null : () {
            if (!_form.currentState!.validate()) return;
            if (_date.isAfter(dateOnly(DateTime.now()))) {
              setState(
                () =>
                    _dateError =
                        'Завершённую тренировку нельзя записать на будущую дату',
              );
              return;
            }
            setState(() => _submitting = true);
            Navigator.pop(
              context,
              _NewWorkout(_title.text, _date, status: 'finished'),
            );
          },
          child: const Text('Завершённая'),
        ),
        FilledButton(
          onPressed: _submitting ? null : () {
            if (!_form.currentState!.validate()) return;
            setState(() => _submitting = true);
            Navigator.pop(
              context,
              _NewWorkout(
                _title.text,
                isSelectedToday ? DateTime.now() : _date,
                status: isSelectedToday ? 'active' : 'planned',
              ),
            );
          },
          child: Text(isSelectedToday ? 'Начать сейчас' : 'Запланировать'),
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
      builder: (_) => const AddExerciseDialog(),
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
    if (AuthService.instance.isAuthenticated) {
      await CloudWorkoutSync().deleteWorkout(widget.workoutId);
    }
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

  Future<void> _viewResult() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkoutResultScreen(workoutId: widget.workoutId),
      ),
    );
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
                case 'result':
                  _viewResult();
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
                  if (status == 'finished')
                    const PopupMenuItem(
                      value: 'result',
                      child: Text('Посмотреть результат'),
                    ),
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
          if (_exercises.isNotEmpty) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addExercise,
              icon: const Icon(Icons.add),
              label: const Text('Добавить упражнение'),
            ),
          ],
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
            _ => Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _viewResult,
                    icon: const Icon(Icons.insights),
                    label: const Text('Посмотреть результат'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Повторить тренировку',
                  onPressed: _repeat,
                  icon: const Icon(Icons.replay),
                ),
              ],
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
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      'Подходов нет',
                      style: TextStyle(color: LlColors.textSecondary),
                    ),
                  )
                else ...[
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
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      await _repo.addSet(e['id'] as String);
                      _load();
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Добавить подход', style: TextStyle(fontSize: 13)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
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

class AddExerciseDialog extends StatefulWidget {
  const AddExerciseDialog({super.key});
  @override
  State<AddExerciseDialog> createState() => _AddExerciseDialogState();
}

class _AddExerciseDialogState extends State<AddExerciseDialog> {
  final _form = GlobalKey<FormState>();
  final _c = TextEditingController();
  List<String> _names = [];
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      final text = _c.text.trim();
      if (_filter != text) {
        setState(() => _filter = text);
      }
    });
    _repo.activeExercises().then((l) {
      if (mounted) {
        setState(() => _names = l.map((r) => r['name'] as String).toList());
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filter.isEmpty
        ? _names
        : _names.where((n) => n.toLowerCase().contains(_filter.toLowerCase())).toList();

    return AlertDialog(
      title: const Text('Добавить упражнение'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _c,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Название упражнения *',
                  hintText: 'Поиск или ввод нового',
                  prefixIcon: Icon(Icons.search),
                ),
                validator:
                    (v) => InputValidators.validateRequiredText(v, 'Название'),
              ),
              if (_names.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Каталог упражнений:',
                      style: TextStyle(fontSize: 12, color: LlColors.textSecondary),
                    ),
                    if (filtered.length != _names.length)
                      Text(
                        'Найдено: ${filtered.length}',
                        style: const TextStyle(fontSize: 11, color: LlColors.accent),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: filtered.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: LlColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'В каталоге нет «$_filter». Будет создано новое упражнение.',
                            style: const TextStyle(fontSize: 12, color: LlColors.textSecondary),
                          ),
                        )
                      : SingleChildScrollView(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final n in filtered)
                                ActionChip(
                                  label: Text(n),
                                  avatar: const Icon(Icons.fitness_center, size: 14),
                                  onPressed: () {
                                    _c.text = n;
                                    _c.selection = TextSelection.fromPosition(
                                      TextPosition(offset: n.length),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                ),
              ],
            ],
          ),
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
              const Icon(Icons.timer, color: LlColors.secondary),
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
        final currentWeight = InputValidators.parseNonNegativeDouble(_w.text);
        final currentReps = InputValidators.parsePositiveInt(_r.text);
        final isFilled = ok && currentWeight != null && currentReps != null && currentReps > 0;
        if (!isFilled) {
          if (mounted) {
            _snack(
              context,
              'Заполните подход перед отметкой (вес ≥ 0, повторы ≥ 1)',
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
                  activeColor: LlColors.success,
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

// ====================== Экран результатов тренировки ======================
class WorkoutResultScreen extends StatefulWidget {
  final String workoutId;
  const WorkoutResultScreen({super.key, required this.workoutId});

  @override
  State<WorkoutResultScreen> createState() => _WorkoutResultScreenState();
}

class _WorkoutResultScreenState extends State<WorkoutResultScreen> {
  bool _loading = true;
  Object? _error;
  Rec? _workout;
  List<Rec> _exercises = [];
  Map<String, List<Rec>> _sets = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = _repo;
      final w = await r.workout(widget.workoutId);
      final ex = await r.workoutExercises(widget.workoutId);
      final setsMap = <String, List<Rec>>{};
      for (final e in ex) {
        setsMap[e['id'] as String] = await r.sets(e['id'] as String);
      }
      if (mounted) {
        setState(() {
          _workout = w;
          _exercises = ex;
          _sets = setsMap;
          _loading = false;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _workout == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Результаты тренировки')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Не удалось загрузить тренировку: $_error'),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }

    final w = _workout!;
    final title = w['title'] as String? ?? 'Тренировка';
    final dateStr = w['date'] as String? ?? '';
    final durationMinutes = w['duration_minutes'] as int?;

    // Сбор всех рабочих подходов и расчет реальных показателей
    final allSetData = <SetData>[];
    int completedExercisesCount = 0;
    int completedSetsCount = 0;
    int totalSetsCount = 0;

    final exerciseStats = <Map<String, Object?>>[];

    for (final e in _exercises) {
      final sList = _sets[e['id'] as String] ?? [];
      totalSetsCount += sList.length;
      final eSetData = <SetData>[];
      int exDoneSets = 0;

      for (final s in sList) {
        final completed = s['completed'] == 1;
        final warmup = s['set_type'] == 'warmup';
        final weight = (s['weight_kg'] as num?)?.toDouble() ?? 0.0;
        final reps = (s['reps'] as int?) ?? 0;
        final sd = SetData(weight, reps, completed: completed, warmup: warmup);
        eSetData.add(sd);
        allSetData.add(sd);
        if (completed) {
          completedSetsCount++;
          exDoneSets++;
        }
      }

      if (exDoneSets > 0) completedExercisesCount++;

      final exVol = workingVolume(eSetData);
      final bestE1rm = sessionE1rm(eSetData);

      exerciseStats.add({
        'exercise': e,
        'sets': sList,
        'volume': exVol,
        'bestE1rm': bestE1rm,
        'doneSets': exDoneSets,
      });
    }

    final totalVolume = workingVolume(allSetData);
    final bestSessionE1rm = sessionE1rm(allSetData);

    return Scaffold(
      backgroundColor: AthleticTokens.midnight,
      appBar: AppBar(
        title: const Text('Результаты тренировки'),
        backgroundColor: AthleticTokens.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // Header Card
          AthleticCard(
            padding: const EdgeInsets.all(20),
            borderColor: AthleticTokens.electricBlue.withValues(alpha: 0.4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const AthleticBadge(
                      label: 'ЗАВЕРШЕНА',
                      color: AthleticTokens.success,
                      icon: Icons.check_circle_outline,
                    ),
                    Text(
                      dateStr,
                      style: const TextStyle(
                        color: AthleticTokens.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AthleticTokens.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                if (durationMinutes != null && durationMinutes > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        size: 16,
                        color: AthleticTokens.electricBlue,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Время: $durationMinutes мин',
                        style: const TextStyle(
                          color: AthleticTokens.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Key metrics row
          const AthleticSectionHeader(
            title: 'Итоги тренировки',
            icon: Icons.analytics_outlined,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AthleticMetricBox(
                  label: 'ОБЪЁМ НАГРУЗКИ',
                  value: totalVolume > 0 ? _kg(totalVolume) : '0',
                  unit: 'кг',
                  accentColor: AthleticTokens.electricBlue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AthleticMetricBox(
                  label: 'ВЫПОЛНЕНО',
                  value: '$completedSetsCount / $totalSetsCount',
                  unit: 'подходов',
                  accentColor: AthleticTokens.electricOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AthleticMetricBox(
                  label: 'УПРАЖНЕНИЙ',
                  value: '$completedExercisesCount / ${_exercises.length}',
                  unit: 'завершено',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AthleticMetricBox(
                  label: 'ЛУЧШИЙ 1ПМ',
                  value: bestSessionE1rm != null ? _kg(bestSessionE1rm.roundToDouble()) : '—',
                  unit: 'кг (e1RM)',
                  accentColor: AthleticTokens.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Exercises Breakdown
          const AthleticSectionHeader(
            title: 'Выполненные упражнения',
            icon: Icons.fitness_center,
          ),
          const SizedBox(height: 8),
          if (_exercises.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'Упражнения не были добавлены',
                  style: TextStyle(color: AthleticTokens.textSecondary),
                ),
              ),
            )
          else
            for (final stat in exerciseStats) ...[
              _buildExerciseResultCard(stat),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Widget _buildExerciseResultCard(Map<String, Object?> stat) {
    final e = stat['exercise'] as Rec;
    final sets = stat['sets'] as List<Rec>;
    final vol = stat['volume'] as double;
    final bestE1rm = stat['bestE1rm'] as double?;
    final doneSets = stat['doneSets'] as int;

    return AthleticCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  e['exercise_name'] as String,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AthleticTokens.textPrimary,
                  ),
                ),
              ),
              Text(
                'Подходов: $doneSets/${sets.length}',
                style: const TextStyle(
                  color: AthleticTokens.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          if (vol > 0 || bestE1rm != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (vol > 0)
                  Text(
                    'Тоннаж: ${_kg(vol)} кг',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AthleticTokens.electricBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (vol > 0 && bestE1rm != null)
                  const Text('  •  ', style: TextStyle(color: AthleticTokens.textSecondary)),
                if (bestE1rm != null)
                  Text(
                    'e1RM: ${_kg(bestE1rm.roundToDouble())} кг',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AthleticTokens.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1, color: AthleticTokens.borderSubtle),
          const SizedBox(height: 8),
          for (final s in sets)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      s['set_type'] == 'warmup' ? 'Р' : '${s['set_number']}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: s['set_type'] == 'warmup'
                            ? LlColors.warning
                            : AthleticTokens.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${_kg(s['weight_kg'])} кг × ${s['reps']}'
                      '${s['rir'] != null ? '  (RIR ${s['rir']})' : ''}',
                      style: TextStyle(
                        fontSize: 13,
                        color: s['completed'] == 1
                            ? AthleticTokens.textPrimary
                            : AthleticTokens.textSecondary,
                      ),
                    ),
                  ),
                  Icon(
                    s['completed'] == 1
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: s['completed'] == 1
                        ? AthleticTokens.success
                        : AthleticTokens.textSecondary,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
