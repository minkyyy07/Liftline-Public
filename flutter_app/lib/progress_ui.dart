import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'chart.dart';
import 'db.dart';
import 'nutrition_calc.dart';
import 'progress_calc.dart';
import 'progress_repo.dart';
import 'repo.dart' show Rec;
import 'theme.dart';
import 'week_utils.dart';

ProgressRepo get _repo => ProgressRepo(AppDb.instance.db);

void _snack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));

final _dFmt = DateFormat('d MMM yyyy', 'ru');

/// Add/edit a body-weight measurement. Returns true when saved/deleted.
Future<bool> showWeightDialog(
  BuildContext context, {
  required DateTime date,
  Rec? existing,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => _WeightDialog(date: date, existing: existing),
  );
  return r == true;
}

class _WeightDialog extends StatefulWidget {
  final DateTime date;
  final Rec? existing;
  const _WeightDialog({required this.date, this.existing});
  @override
  State<_WeightDialog> createState() => _WeightDialogState();
}

class _WeightDialogState extends State<_WeightDialog> {
  late DateTime _date =
      widget.existing == null
          ? dateOnly(widget.date)
          : DateTime.parse(widget.existing!['date'] as String);
  late final _kg = TextEditingController(
    text:
        widget.existing == null
            ? ''
            : fmtG((widget.existing!['kg'] as num).toDouble()),
  );
  String? _err;
  bool _busy = false;

  Future<void> _save() async {
    if (_busy) return;
    final v = parseDecimal(_kg.text);
    if (v == null || v <= 0) {
      setState(() => _err = 'Введите число больше 0');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      if (widget.existing != null) {
        await _repo.updateWeight(widget.existing!['id'] as String, _date, v);
      } else {
        try {
          await _repo.saveWeight(_date, v);
        } on WeightExists {
          if (!mounted) return;
          final ok = await showDialog<bool>(
            context: context,
            builder:
                (ctx) => AlertDialog(
                  title: const Text('Измерение уже есть'),
                  content: const Text(
                    'На эту дату уже записан вес. Изменить существующую запись?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Отмена'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Изменить'),
                    ),
                  ],
                ),
          );
          if (ok != true) {
            if (mounted) setState(() => _busy = false);
            return;
          }
          await _repo.saveWeight(_date, v, replaceExisting: true);
        }
      }
      if (mounted) Navigator.pop(context, true);
    } on WeightExists {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = 'На эту дату уже есть другое измерение';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(context, 'Не удалось сохранить: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Записать вес' : 'Изменить измерение',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text(_dFmt.format(_date)),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
              );
              if (d != null) setState(() => _date = dateOnly(d));
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _kg,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Вес, кг', errorText: _err),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder:
                    (ctx) => AlertDialog(
                      title: const Text('Удалить измерение?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Отмена'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Удалить'),
                        ),
                      ],
                    ),
              );
              if (ok == true) {
                await _repo.deleteWeight(widget.existing!['id'] as String);
                if (context.mounted) Navigator.pop(context, true);
              }
            },
            child: const Text('Удалить'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

// ====================== Прогресс ======================
class ProgressScreen extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<int>? onGoToTab;
  const ProgressScreen({super.key, required this.selectedDate, this.onGoToTab});
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  String _tab = 'strength';
  final ScrollController _tabScroll = ScrollController();

  @override
  void dispose() {
    _tabScroll.dispose();
    super.dispose();
  }

  void _onTabChanged(String tab) {
    setState(() => _tab = tab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_tabScroll.hasClients) return;
      final max = _tabScroll.position.maxScrollExtent;
      if (max <= 0) return;
      double target = 0;
      if (tab == 'strength') {
        target = 0;
      } else if (tab == 'weight') {
        target = max / 2;
      } else if (tab == 'nutrition') {
        target = max;
      }
      _tabScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Прогресс')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  controller: _tabScroll,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                      ),
                      segments: const [
                        ButtonSegment(value: 'strength', label: Text('Силовые')),
                        ButtonSegment(value: 'weight', label: Text('Вес тела')),
                        ButtonSegment(value: 'nutrition', label: Text('Питание')),
                      ],
                      selected: {_tab},
                      onSelectionChanged: (s) => _onTabChanged(s.first),
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: switch (_tab) {
              'weight' => WeightTab(
                key: ValueKey(widget.selectedDate),
                end: widget.selectedDate,
                onGoToTab: widget.onGoToTab,
              ),
              'nutrition' => NutritionWeekTab(
                key: ValueKey(widget.selectedDate),
                end: widget.selectedDate,
                onGoToTab: widget.onGoToTab,
              ),
              _ => StrengthTab(
                key: ValueKey(widget.selectedDate),
                end: widget.selectedDate,
                onGoToTab: widget.onGoToTab,
              ),
            },
          ),
        ],
      ),
    );
  }
}

Widget _periodChips(String sel, ValueChanged<String> on) =>
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final p in kPeriods)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(p),
                selected: p == sel,
                onSelected: (_) => on(p),
              ),
            ),
        ],
      ),
    );

const _periodHint =
    'Периоды — окна в днях, заканчивающиеся выбранным днём: 1Н = 7, 1М = 30, 3М = 90, 6М = 180, 1Г = 365 дней.';

// ---------- силовые ----------
class StrengthTab extends StatefulWidget {
  final DateTime end;
  final ValueChanged<int>? onGoToTab;
  const StrengthTab({super.key, required this.end, this.onGoToTab});
  @override
  State<StrengthTab> createState() => _StrengthTabState();
}

class _StrengthTabState extends State<StrengthTab> {
  List<Rec> _exs = [];
  String? _ref;
  List<SessionPoint> _sessions = [];
  String _metric = 'e1rm';
  String _period = '3М';
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final e = await _repo.exercisesWithHistory();
      _exs = e;
      _ref = e.isEmpty ? null : e.first['id'] as String;
      await _loadSessions();
    } catch (er) {
      if (mounted) {
        setState(() {
          _error = er;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadSessions() async {
    final s =
        _ref == null ? <SessionPoint>[] : await _repo.strengthSessions(_ref!);
    if (mounted) {
      setState(() {
        _sessions = s;
        _loading = false;
        _error = null;
      });
    }
  }

  double? _val(SessionPoint s) => switch (_metric) {
    'best' => s.bestWeight,
    'vol' => s.volume,
    _ => s.e1rm,
  };

  String get _unit => _metric == 'vol' ? 'кг·повт.' : 'кг';

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ошибка: $_error'),
            FilledButton(onPressed: _init, child: const Text('Повторить')),
          ],
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_exs.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
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
                  Icons.show_chart,
                  size: 48,
                  color: LlColors.accent,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Нет данных для силового прогресса',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Завершите тренировку с выполненными рабочими подходами — после этого здесь появятся графики. Активные тренировки в историю не входят.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: LlColors.textSecondary),
              ),
              if (widget.onGoToTab != null) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => widget.onGoToTab!(1),
                  icon: const Icon(Icons.fitness_center),
                  label: const Text(
                    'Перейти к тренировкам',
                    textAlign: TextAlign.center,
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final start = periodStart(_period, widget.end);
    final inPeriod =
        _sessions.where((s) => inWindow(s.date, start, widget.end)).toList();
    final pts = [
      for (final s in inPeriod)
        if (_val(s) != null) ChartPt(s.date, _val(s)!),
    ];
    ChartPt? best;
    for (final p in pts) {
      if (best == null || p.value > best.value) best = p;
    }
    final change =
        _metric == 'e1rm'
            ? changePercent(pts.map((p) => p.value).toList())
            : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        DropdownButtonFormField<String>(
          value: _ref,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Упражнение'),
          items: [
            for (final e in _exs)
              DropdownMenuItem(
                value: e['id'] as String,
                child: Text(
                  e['name'] as String,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) {
            setState(() {
              _ref = v;
              _loading = true;
            });
            _loadSessions();
          },
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'e1rm', label: Text('e1RM')),
              ButtonSegment(value: 'best', label: Text('Вес')),
              ButtonSegment(value: 'vol', label: Text('Объём')),
            ],
            selected: {_metric},
            onSelectionChanged: (s) => setState(() => _metric = s.first),
          ),
        ),
        const SizedBox(height: 8),
        _periodChips(_period, (p) => setState(() => _period = p)),
        const SizedBox(height: 12),
        if (pts.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _metric == 'vol'
                        ? 'В выбранном периоде нет завершённых тренировок с рабочими подходами.'
                        : 'Нет подходящих данных за период. Для e1RM и лучшего веса нужны выполненные рабочие подходы '
                            'с внешним весом (e1RM — до 10 повторений).',
                    style: const TextStyle(color: LlColors.textSecondary),
                  ),
                  if (widget.onGoToTab != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => widget.onGoToTab!(1),
                      icon: const Icon(Icons.fitness_center, size: 18),
                      label: const Text(
                        'Перейти к тренировкам',
                        textAlign: TextAlign.center,
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        minimumSize: const Size(0, 44),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          )
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LineChartView(points: pts, unit: _unit),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Лучшее: ${fmtG(best!.value)} $_unit (${_dFmt.format(best.date)})',
                  ),
                  Text(
                    'Последнее: ${fmtG(pts.last.value)} $_unit (${_dFmt.format(pts.last.date)})',
                  ),
                  if (_metric == 'e1rm')
                    Text(
                      change == null
                          ? 'Изменение: недостаточно данных (нужно минимум две тренировки)'
                          : 'Изменение e1RM за период: ${change >= 0 ? '+' : '−'}${change.abs().toStringAsFixed(1)}% '
                              '(последняя точка относительно первой)',
                    ),
                  if (pts.length == 1) const Text('Первый результат'),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          _metric == 'e1rm'
              ? 'e1RM — оценка по формуле Эпли: вес × (1 + повторы/30); для 1 повтора равна весу; '
                  'не считается при более 10 повторах и нулевом внешнем весе. Это не реально установленный 1RM.'
              : _metric == 'vol'
              ? 'Объём = сумма вес × повторы выполненных рабочих подходов, кг·повт. (не работа и не калории). '
                  'Вес вводится как записано, без удвоения для гантелей.'
              : 'Лучший вес — максимальный внешний вес выполненных рабочих подходов.',
          style: const TextStyle(fontSize: 12, color: LlColors.textSecondary),
        ),
        const SizedBox(height: 4),
        const Text(
          '$_periodHint Разминочные и невыполненные подходы, а также незавершённые тренировки не учитываются.',
          style: TextStyle(fontSize: 12, color: LlColors.textSecondary),
        ),
      ],
    );
  }
}

// ---------- вес тела ----------
class WeightTab extends StatefulWidget {
  final DateTime end;
  final ValueChanged<int>? onGoToTab;
  const WeightTab({super.key, required this.end, this.onGoToTab});
  @override
  State<WeightTab> createState() => _WeightTabState();
}

class _WeightTabState extends State<WeightTab> {
  List<Rec> _rows = [];
  String _period = '3М';
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _repo.weights();
      if (mounted) {
        setState(() {
          _rows = r;
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

  Future<void> _edit([Rec? r]) async {
    if (await showWeightDialog(context, date: widget.end, existing: r)) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ошибка: $_error'),
            FilledButton(onPressed: _load, child: const Text('Повторить')),
          ],
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_rows.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
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
                  Icons.monitor_weight_outlined,
                  size: 48,
                  color: LlColors.accent,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'В истории измерений нет',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Записывайте вес тела, чтобы видеть график динамики и 7-дневный скользящий тренд.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: LlColors.textSecondary),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('Записать вес'),
              ),
            ],
          ),
        ),
      );
    }
    final all = [
      for (final r in _rows)
        WeightPoint(
          DateTime.parse(r['date'] as String),
          (r['kg'] as num).toDouble(),
        ),
    ];
    final start = periodStart(_period, widget.end);
    final win = all.where((p) => inWindow(p.date, start, widget.end)).toList();
    final trend = <ChartPt>[
      for (final p in win)
        if (movingAverage(all, p.date) != null)
          ChartPt(p.date, movingAverage(all, p.date)!.avg),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        FilledButton.icon(
          onPressed: () => _edit(),
          icon: const Icon(Icons.add),
          label: const Text('Записать вес'),
        ),
        const SizedBox(height: 8),
        _periodChips(_period, (p) => setState(() => _period = p)),
        const SizedBox(height: 12),
        if (win.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'В выбранном периоде измерений нет. Запишите вес для этой даты — тренд появится, '
                    'когда в 7-дневном окне будет минимум 3 измерения.',
                    style: TextStyle(color: LlColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _edit(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Записать вес'),
                  ),
                ],
              ),
            ),
          )
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LineChartView(
                    points: win.map((p) => ChartPt(p.date, p.kg)).toList(),
                    trend: trend,
                    unit: 'кг',
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Зелёная — измерения, синяя — тренд (среднее за 7 дней, только где есть ≥ 3 измерений).',
                    style: TextStyle(
                      fontSize: 12,
                      color: LlColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Измерения',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          for (final r in _rows.reversed.where(
            (r) => inWindow(
              DateTime.parse(r['date'] as String),
              start,
              widget.end,
            ),
          ))
            _row(r, all),
        ],
        const SizedBox(height: 12),
        const Text(
          'Среднее за 7 дней — среднее по измерениям календарного окна [D−6, D]; нужно минимум 3 дня с записями. '
          '«Изм. средних 2 нед.» = среднее на дату D минус среднее на D−7 (оба окна ≥ 3 измерений); это разница '
          'средних, а не скорость в кг/нед. Прочерк — данных недостаточно. $_periodHint',
          style: TextStyle(fontSize: 12, color: LlColors.textSecondary),
        ),
      ],
    );
  }

  Widget _row(Rec r, List<WeightPoint> all) {
    final d = DateTime.parse(r['date'] as String);
    final avg = movingAverage(all, d);
    final ch = twoWeekChange(all, d);
    final sign =
        ch == null
            ? ''
            : (ch.delta > 0
                ? '+'
                : ch.delta < 0
                ? '−'
                : '');
    return Card(
      margin: const EdgeInsets.only(top: 6),
      child: ListTile(
        onTap: () => _edit(r),
        title: Text(
          '${_dFmt.format(d)} • ${fmtG((r['kg'] as num).toDouble())} кг',
        ),
        subtitle: Text(
          'Среднее 7 дн.: ${avg == null ? '—' : '${avg.avg.toStringAsFixed(2)} кг (${avg.n}/7)'}\n'
          'Изм. средних 2 нед.: ${ch == null ? '—' : '$sign${ch.delta.abs().toStringAsFixed(2)} кг (${ch.nNow}/7 и ${ch.nPrev}/7)'}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.edit_outlined),
      ),
    );
  }
}

// ---------- питание за неделю ----------
class NutritionWeekTab extends StatefulWidget {
  final DateTime end;
  final ValueChanged<int>? onGoToTab;
  const NutritionWeekTab({super.key, required this.end, this.onGoToTab});
  @override
  State<NutritionWeekTab> createState() => _NutritionWeekTabState();
}

class _NutritionWeekTabState extends State<NutritionWeekTab> {
  List<({DateTime date, Nutrients? totals, double? goalKcal})>? _week;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _repo
        .week(widget.end)
        .then((w) {
          if (mounted) setState(() => _week = w);
        })
        .catchError((e) {
          if (mounted) setState(() => _error = e);
        });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text('Ошибка: $_error'));
    final w = _week;
    if (w == null) return const Center(child: CircularProgressIndicator());
    final avg = averageOverEntryDays([for (final d in w) d.totals?.kcal]);
    final withEntries = w.where((d) => d.totals != null).toList();
    double avgOf(double Function(Nutrients) f) =>
        withEntries.isEmpty
            ? 0
            : withEntries.map((d) => f(d.totals!)).reduce((a, b) => a + b) /
                withEntries.length;
    final fmt = DateFormat('E d MMM', 'ru');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          'Неделя по ${_dFmt.format(widget.end)} (7 дней)',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (avg == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'За эти 7 дней записей питания нет',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Ведите дневник питания, чтобы видеть среднюю калорийность, баланс БЖУ и соблюдение целей за неделю.',
                    style: TextStyle(color: LlColors.textSecondary),
                  ),
                  if (widget.onGoToTab != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => widget.onGoToTab!(2),
                      icon: const Icon(Icons.restaurant, size: 18),
                      label: const Text(
                        'Перейти к питанию',
                        textAlign: TextAlign.center,
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        minimumSize: const Size(0, 44),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Среднее: ${fmtKcal(avg.avg)} ккал (дней с записями: ${avg.days} из 7)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Б ${fmtG(avgOf((n) => n.protein))} г • Ж ${fmtG(avgOf((n) => n.fat))} г • У ${fmtG(avgOf((n) => n.carbs))} г (в среднем)',
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        for (final d in w.reversed)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              title: Text(fmt.format(d.date)),
              subtitle: Text(
                d.goalKcal == null
                    ? 'Цели на этот день нет'
                    : 'Цель дня: ${fmtKcal(d.goalKcal!)} ккал',
              ),
              trailing: Text(
                d.totals == null
                    ? 'нет записей'
                    : '${fmtKcal(d.totals!.kcal)} ккал',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color:
                      d.totals == null ? LlColors.textSecondary : LlColors.text,
                ),
              ),
            ),
          ),
        const Text(
          'День без записей — не подтверждённое голодание: он не входит в среднее и не считается нулём. '
          'Каждый день сравнивается с целью, действовавшей в этот день.',
          style: TextStyle(fontSize: 12, color: LlColors.textSecondary),
        ),
      ],
    );
  }
}
