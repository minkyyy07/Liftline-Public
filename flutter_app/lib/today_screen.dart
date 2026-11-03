import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'main.dart';
import 'theme.dart';
import 'week_utils.dart';
import 'repo.dart';
import 'nutrition_calc.dart';
import 'nutrition_repo.dart';
import 'nutrition_ui.dart';
import 'progress_repo.dart';
import 'progress_ui.dart';
import 'workouts_ui.dart';

/// "Сегодня": week strip, nutrition totals and workouts of the selected day.
class TodayScreen extends StatefulWidget {
  final DateTime selectedDate;
  final bool isFollowingToday;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<int> onGoToTab;

  const TodayScreen({
    super.key,
    required this.selectedDate,
    required this.isFollowingToday,
    required this.onDateChanged,
    required this.onGoToTab,
  });

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  bool _loading = true;
  Object? _error;
  Nutrients _totals = Nutrients.zero;
  NutritionGoals _goals = const NutritionGoals(null, null, null, null);
  int _entries = 0;
  List<Map<String, Object?>> _workouts = [];
  Set<String> _workoutDays = {};
  Map<String, Object?>? _active;
  Map<String, Object?>? _weight;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TodayScreen old) {
    super.didUpdateWidget(old);
    if (!isSameDay(old.selectedDate, widget.selectedDate)) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = AppDb.instance.db;
      final key = dateKey(widget.selectedDate);
      final nrepo = NutritionRepo(db);
      final nutrition = await nrepo.day(key);
      final goals = await nrepo.goalsFor(key);
      final workouts = await db.query(
        'workouts',
        where: 'date = ?',
        whereArgs: [key],
      );
      final days = weekDays(widget.selectedDate);
      final weekRows = await db.query(
        'workouts',
        columns: ['date'],
        where: 'date >= ? AND date <= ?',
        whereArgs: [dateKey(days.first), dateKey(days.last)],
      );
      final active = await WorkoutRepo(db).activeWorkout();
      final weight = await ProgressRepo(db).latestUpTo(key);
      final totals = sumNutrients(nutrition.map(entryTotals));
      if (!mounted) return;
      setState(() {
        _totals = totals;
        _goals = goals;
        _entries = nutrition.length;
        _active = active;
        _weight = weight;
        _workouts = workouts;
        _workoutDays = weekRows.map((r) => r['date'] as String).toSet();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _addFood() async {
    final meal = await showMealPickerSheet(context);
    if (meal == null || !mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EntryFormScreen(date: widget.selectedDate, meal: meal),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) widget.onDateChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final isToday = isSameDay(widget.selectedDate, DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt, color: LlColors.secondary, size: 24),
              SizedBox(width: 6),
              Text(
                'Liftspire',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (!isToday || !widget.isFollowingToday)
            TextButton(
              onPressed: () => widget.onDateChanged(DateTime.now()),
              child: const Text('Сегодня'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (_active != null) ...[
              Card(
                color: LlColors.surfaceHigh,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => WorkoutOverviewScreen(
                              workoutId: _active!['id'] as String,
                            ),
                      ),
                    );
                    _load();
                  },
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Идёт тренировка',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: LlColors.textSecondary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _active!['title'] as String? ?? '',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.chevron_right,
                          color: LlColors.accent,
                          size: 24,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _dateHeader(),
            const SizedBox(height: 8),
            _weekStrip(),
            const SizedBox(height: 12),
            if (_error != null)
              _errorCard()
            else if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _nutritionCard(),
              const SizedBox(height: 16),
              _weightCard(),
              const SizedBox(height: 16),
              _workoutsSection(),
            ],
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final textScale = MediaQuery.textScalerOf(context).scale(1.0);
                if (constraints.maxWidth < 380 || textScale > 1.2) {
                  return Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => widget.onGoToTab(1),
                          icon: const Icon(Icons.fitness_center),
                          label: const Text('Тренировки'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _addFood,
                          icon: const Icon(Icons.add),
                          label: const Text('Добавить еду'),
                        ),
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => widget.onGoToTab(1),
                        icon: const Icon(Icons.fitness_center),
                        label: const Text('Тренировки'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addFood,
                        icon: const Icon(Icons.add),
                        label: const Text('Добавить еду'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateHeader() {
    final fmt = DateFormat('d MMMM yyyy, EEEE', 'ru');
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _pickDate,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.event, color: LlColors.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  fmt.format(widget.selectedDate),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_drop_down,
                color: LlColors.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _weekStrip() {
    final days = weekDays(widget.selectedDate);
    final names = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Semantics(
              button: true,
              selected: isSameDay(days[i], widget.selectedDate),
              label:
                  '${names[i]} ${days[i].day}${_workoutDays.contains(dateKey(days[i])) ? ', есть тренировка' : ''}',
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => widget.onDateChanged(days[i]),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color:
                        isSameDay(days[i], widget.selectedDate)
                            ? LlColors.surfaceHigh
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border:
                        isSameDay(days[i], DateTime.now())
                            ? Border.all(color: LlColors.accent)
                            : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          names[i],
                          style: const TextStyle(
                            fontSize: 11,
                            color: LlColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${days[i].day}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Icon(
                        Icons.circle,
                        size: 5,
                        color:
                            _workoutDays.contains(dateKey(days[i]))
                                ? LlColors.accent
                                : Colors.transparent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _errorCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: LlColors.error),
          const SizedBox(height: 8),
          Text(
            'Не удалось загрузить данные: $_error',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _load, child: const Text('Повторить')),
        ],
      ),
    ),
  );

  Widget _nutritionCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Питание',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        NutritionSummaryCard(
          totals: _totals,
          goals: _goals,
          hasEntries: _entries > 0,
          onSetGoals: () async {
            if (await showGoalsDialog(context, widget.selectedDate)) _load();
          },
        ),
        if (_entries == 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: _addFood,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Добавить еду'),
            ),
          ),
      ],
    );
  }

  Widget _weightCard() {
    final w = _weight;
    final isDay = w != null && w['date'] == dateKey(widget.selectedDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Вес тела',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final textScale = MediaQuery.textScalerOf(context).scale(1.0);
                final isNarrow = constraints.maxWidth < 360 || textScale > 1.2;
                final info = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      w == null
                          ? 'Измерений до этой даты нет'
                          : '${fmtG((w['kg'] as num).toDouble())} кг',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (w != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        isDay
                            ? 'Измерение за этот день'
                            : 'Последнее: ${DateFormat('d MMM yyyy', 'ru').format(DateTime.parse(w['date'] as String))}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: LlColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                );
                final btn = TextButton(
                  onPressed: () async {
                    if (await showWeightDialog(
                      context,
                      date: widget.selectedDate,
                    )) {
                      _load();
                    }
                  },
                  child: const Text('Записать вес'),
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      info,
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerRight, child: btn),
                    ],
                  );
                }
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: info),
                    const SizedBox(width: 8),
                    btn,
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _workoutsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Тренировки дня',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_workouts.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    const Text(
                      'На эту дату тренировок нет',
                      style: TextStyle(color: LlColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => widget.onGoToTab(1),
                      child: const Text('Перейти к тренировкам'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          for (final w in _workouts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.fitness_center,
                    color: LlColors.accent,
                  ),
                  title: Text(
                    w['title'] as String,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Длительность: ${w['duration_minutes'] ?? 0} мин',
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
