import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'db.dart';
import 'nutrition_calc.dart';
import 'nutrition_repo.dart';
import 'theme.dart';
import 'week_utils.dart';

NutritionRepo get _repo => NutritionRepo(AppDb.instance.db);

void _snack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));

String _fmtDate(DateTime d) => DateFormat('d MMMM yyyy, EEEE', 'ru').format(d);

/// Goals dialog; goals apply from [from] onwards (past days keep older goals).
Future<bool> showGoalsDialog(BuildContext context, DateTime from) async {
  final cur = await _repo.goalsFor(dateKey(from));
  if (!context.mounted) return false;
  final res = await showDialog<bool>(
    context: context,
    builder: (_) => _GoalsDialog(from: from, cur: cur),
  );
  return res == true;
}

class _GoalsDialog extends StatefulWidget {
  final DateTime from;
  final NutritionGoals cur;
  const _GoalsDialog({required this.from, required this.cur});
  @override
  State<_GoalsDialog> createState() => _GoalsDialogState();
}

class _GoalsDialogState extends State<_GoalsDialog> {
  final _form = GlobalKey<FormState>();
  late final _k = TextEditingController(text: _s(widget.cur.calories));
  late final _p = TextEditingController(text: _s(widget.cur.protein));
  late final _f = TextEditingController(text: _s(widget.cur.fat));
  late final _c = TextEditingController(text: _s(widget.cur.carbs));
  bool _busy = false;

  static String _s(double? v) => v == null ? '' : fmtG(v);

  String? _v(String? s) {
    if (s == null || s.trim().isEmpty) return null; // no goal
    final v = parseDecimal(s);
    return (v == null || v <= 0) ? 'Нужно число > 0 или пусто' : null;
  }

  Widget _f4(String label, TextEditingController c) => TextFormField(
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label),
    validator: _v,
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Цели питания'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Действуют с ${DateFormat('d MMMM yyyy', 'ru').format(widget.from)}. '
                'Прошлые дни сохраняют прежние цели. Пустое поле — цели нет.',
                style: const TextStyle(
                  fontSize: 12,
                  color: LlColors.textSecondary,
                ),
              ),
              _f4('Калории, ккал', _k),
              _f4('Белки, г', _p),
              _f4('Жиры, г', _f),
              _f4('Углеводы, г', _c),
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
          onPressed:
              _busy
                  ? null
                  : () async {
                    if (!_form.currentState!.validate()) return;
                    setState(() => _busy = true);
                    try {
                      await _repo.setGoals(
                        widget.from,
                        NutritionGoals(
                          parseDecimal(_k.text),
                          parseDecimal(_p.text),
                          parseDecimal(_f.text),
                          parseDecimal(_c.text),
                        ),
                      );
                      if (context.mounted) Navigator.pop(context, true);
                    } catch (e) {
                      if (context.mounted) {
                        setState(() => _busy = false);
                        _snack(context, 'Не удалось сохранить: $e');
                      }
                    }
                  },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

IconData mealIcon(String meal) => switch (meal) {
  'breakfast' => Icons.wb_sunny_outlined,
  'lunch' => Icons.lunch_dining_outlined,
  'dinner' => Icons.dinner_dining_outlined,
  _ => Icons.cookie_outlined,
};

/// Shows a bottom sheet to explicitly pick a meal category before adding food.
/// Returns null if cancelled.
Future<String?> showMealPickerSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: LlColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder:
        (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'Выберите приём пищи',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                for (final m in kMeals)
                  ListTile(
                    leading: Icon(mealIcon(m), color: LlColors.accent),
                    title: Text(
                      kMealLabels[m] ?? m,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: LlColors.textSecondary,
                    ),
                    onTap: () => Navigator.pop(ctx, m),
                  ),
              ],
            ),
          ),
        ),
  );
}

// ====================== Экран питания ======================
class NutritionScreen extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;
  const NutritionScreen({
    super.key,
    required this.selectedDate,
    required this.onDateChanged,
  });
  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  List<Map<String, Object?>> _entries = [];
  NutritionGoals _goals = const NutritionGoals(null, null, null, null);
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant NutritionScreen old) {
    super.didUpdateWidget(old);
    if (!isSameDay(old.selectedDate, widget.selectedDate)) _load();
  }

  Future<void> _load() async {
    try {
      final key = dateKey(widget.selectedDate);
      final e = await _repo.day(key);
      final g = await _repo.goalsFor(key);
      if (mounted) {
        setState(() {
          _entries = e;
          _goals = g;
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

  Future<void> _openForm({String? entryId, String? meal}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder:
            (_) => EntryFormScreen(
              date: widget.selectedDate,
              entryId: entryId,
              meal: meal,
            ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _repeat(Map<String, Object?> e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _RepeatDialog(entry: e, initialDate: widget.selectedDate),
    );
    if (ok == true) {
      _load();
      if (mounted) _snack(context, 'Запись добавлена');
    }
  }

  Future<void> _delete(Map<String, Object?> e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Удалить запись?'),
            content: Text('«${e['name']}» будет удалена из дневника.'),
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
      await _repo.delete(e['id'] as String);
      _load();
    }
  }

  void _shiftDay(int d) {
    final s = widget.selectedDate;
    widget.onDateChanged(DateTime(s.year, s.month, s.day + d));
  }

  Future<void> _addFoodAction() async {
    final meal = await showMealPickerSheet(context);
    if (meal != null && mounted) {
      _openForm(meal: meal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = sumNutrients(_entries.map(entryTotals));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Питание'),
        actions: [
          IconButton(
            tooltip: 'Добавить еду',
            icon: const Icon(Icons.add),
            onPressed: _addFoodAction,
          ),
          IconButton(
            tooltip: 'Цели питания',
            icon: const Icon(Icons.flag_outlined),
            onPressed: () async {
              if (await showGoalsDialog(context, widget.selectedDate)) _load();
            },
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
              : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                  children: [
                    _dateRow(),
                    const SizedBox(height: 12),
                    NutritionSummaryCard(
                      totals: totals,
                      goals: _goals,
                      hasEntries: _entries.isNotEmpty,
                      onSetGoals: () async {
                        if (await showGoalsDialog(context, widget.selectedDate)) {
                          _load();
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _addFoodAction,
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить еду'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final m in [...kMeals, 'other']) _mealGroup(m),
                  ],
                ),
              ),
    );
  }

  Widget _dateRow() => Row(
    children: [
      IconButton(
        tooltip: 'Предыдущий день',
        icon: const Icon(Icons.chevron_left),
        onPressed: () => _shiftDay(-1),
      ),
      Expanded(
        child: TextButton(
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: widget.selectedDate,
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
            );
            if (d != null) widget.onDateChanged(d);
          },
          child: Text(
            _fmtDate(widget.selectedDate),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      IconButton(
        tooltip: 'Следующий день',
        icon: const Icon(Icons.chevron_right),
        onPressed: () => _shiftDay(1),
      ),
    ],
  );

  Widget _mealGroup(String meal) {
    final items =
        _entries
            .where(
              (e) =>
                  ((e['meal'] as String?) ?? 'other') == meal ||
                  (meal == 'other' && !kMeals.contains(e['meal'])),
            )
            .toList();
    if (meal == 'other' && items.isEmpty) return const SizedBox.shrink();
    final sum = sumNutrients(items.map(entryTotals));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${kMealLabels[meal]}${items.isEmpty ? '' : ' • ${fmtKcal(sum.kcal)} ккал'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              if (meal != 'other')
                IconButton(
                  tooltip: 'Добавить: ${kMealLabels[meal]}',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => _openForm(meal: meal),
                ),
            ],
          ),
          for (final e in items)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                title: Text(e['name'] as String),
                subtitle: Text(_entrySubtitle(e)),
                onTap: () => _openForm(entryId: e['id'] as String),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) => v == 'repeat' ? _repeat(e) : _delete(e),
                  itemBuilder:
                      (_) => const [
                        PopupMenuItem(
                          value: 'repeat',
                          child: Text('Повторить в другой день'),
                        ),
                        PopupMenuItem(value: 'delete', child: Text('Удалить')),
                      ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _entrySubtitle(Map<String, Object?> e) {
    final t = entryTotals(e);
    final head =
        e['mode'] == 'product' && e['grams'] != null
            ? '${fmtG((e['grams'] as num).toDouble())} г'
            : (e['portion'] as String?)?.isNotEmpty == true
            ? '${e['portion']}'
            : 'порция';
    return '$head • ${fmtKcal(t.kcal)} ккал • Б ${fmtG(t.protein)} Ж ${fmtG(t.fat)} У ${fmtG(t.carbs)}';
  }
}

/// Totals vs. goals card. Consistent across "Сегодня" and "Питание".
class NutritionSummaryCard extends StatelessWidget {
  final Nutrients totals;
  final NutritionGoals goals;
  final bool hasEntries;
  final VoidCallback onSetGoals;
  const NutritionSummaryCard({
    super.key,
    required this.totals,
    required this.goals,
    required this.hasEntries,
    required this.onSetGoals,
  });

  @override
  Widget build(BuildContext context) {
    final gk = goals.calories;
    final hasGoal = gk != null;

    Widget macro(String label, double v, double? goal, Color c) => Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              goal == null ? '${fmtG(v)} г' : '${fmtG(v)} / ${fmtG(goal)} г',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: c,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: LlColors.textSecondary),
          ),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              if (!hasGoal) ...[
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: fmtKcal(totals.kcal),
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: LlColors.accent,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const TextSpan(
                        text: ' ккал съедено',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: LlColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        fmtKcal(totals.kcal),
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: LlColors.accent,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        ' / ${fmtKcal(gk)} ккал',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: LlColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Builder(
                  builder: (_) {
                    final b = calorieBalance(totals.kcal, gk);
                    final isOver = b.over > 0;
                    final isReached = b.remaining == 0 && !isOver;
                    final progress = (totals.kcal / gk).clamp(0.0, 1.0);
                    return Column(
                      children: [
                        Text(
                          isOver
                              ? 'Сверх цели: ${fmtKcal(b.over)} ккал'
                              : (isReached
                                  ? 'Цель достигнута'
                                  : 'Осталось: ${fmtKcal(b.remaining)} ккал'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color:
                                isOver
                                    ? LlColors.secondary
                                    : (isReached
                                        ? LlColors.success
                                        : LlColors.textSecondary),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            color:
                                isOver
                                    ? LlColors.secondary
                                    : (isReached
                                        ? LlColors.success
                                        : LlColors.accent),
                            backgroundColor: LlColors.surfaceHigh,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  macro(
                    'Белки',
                    totals.protein,
                    goals.protein,
                    LlColors.accent,
                  ),
                  macro('Жиры', totals.fat, goals.fat, LlColors.secondary),
                  macro('Углеводы', totals.carbs, goals.carbs, LlColors.warning),
                ],
              ),
              const SizedBox(height: 12),
              if (!hasGoal)
                OutlinedButton.icon(
                  onPressed: onSetGoals,
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  label: const Text('Задать цель'),
                )
              else
                TextButton.icon(
                  onPressed: onSetGoals,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Изменить цели'),
                  style: TextButton.styleFrom(
                    foregroundColor: LlColors.textSecondary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ====================== Повтор записи ======================
class _RepeatDialog extends StatefulWidget {
  final Map<String, Object?> entry;
  final DateTime initialDate;
  const _RepeatDialog({required this.entry, required this.initialDate});
  @override
  State<_RepeatDialog> createState() => _RepeatDialogState();
}

class _RepeatDialogState extends State<_RepeatDialog> {
  late DateTime _date = dateOnly(widget.initialDate);
  late final _grams = TextEditingController(
    text:
        widget.entry['grams'] == null
            ? ''
            : fmtG((widget.entry['grams'] as num).toDouble()),
  );
  bool _busy = false;
  String? _err;

  bool get _product => widget.entry['mode'] == 'product';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Повторить запись'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.entry['name'] as String),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text(DateFormat('d MMMM yyyy', 'ru').format(_date)),
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
          if (_product)
            TextField(
              controller: _grams,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Масса, г',
                errorText: _err,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed:
              _busy
                  ? null
                  : () async {
                    double? g;
                    if (_product) {
                      g = parseDecimal(_grams.text);
                      if (g == null || g <= 0) {
                        setState(() => _err = 'Масса > 0');
                        return;
                      }
                    }
                    setState(() => _busy = true); // blocks double tap
                    try {
                      await _repo.repeat(
                        widget.entry['id'] as String,
                        date: dateKey(_date),
                        grams: g,
                      );
                      if (context.mounted) Navigator.pop(context, true);
                    } catch (e) {
                      if (context.mounted) {
                        setState(() => _busy = false);
                        _snack(context, 'Не удалось сохранить: $e');
                      }
                    }
                  },
          child: const Text('Повторить'),
        ),
      ],
    );
  }
}

// ====================== Форма записи ======================
class EntryFormScreen extends StatefulWidget {
  final DateTime date;
  final String? entryId;
  final String? meal;
  const EntryFormScreen({
    super.key,
    required this.date,
    this.entryId,
    this.meal,
  });
  @override
  State<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends State<EntryFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _grams = TextEditingController(text: '100');
  final _k = TextEditingController();
  final _p = TextEditingController();
  final _f = TextEditingController();
  final _c = TextEditingController();
  String _mode = 'product';
  String _meal = 'snack';
  late DateTime _date = dateOnly(widget.date);
  bool _remember = true;
  bool _busy = false;
  bool _loaded = false;
  Map<String, Object?>? _orig;
  List<Map<String, Object?>> _recent = [];

  bool get _editing => widget.entryId != null;
  bool get _product => _mode == 'product';

  @override
  void initState() {
    super.initState();
    if (widget.meal != null) _meal = widget.meal!;
    _init();
  }

  Future<void> _init() async {
    _recent = await _repo.recentFoods();
    if (_editing) {
      final e = await _repo.entry(widget.entryId!);
      if (e != null) {
        _orig = e;
        _mode = e['mode'] as String? ?? 'portion';
        _name.text = e['name'] as String;
        _date = DateTime.parse(e['date'] as String);
        final m = e['meal'] as String?;
        _meal = kMeals.contains(m) ? m! : 'other';
        if (_mode == 'product') {
          // values of the entry itself (snapshot), not the catalogue
          _grams.text = fmtG((e['grams'] as num).toDouble());
          _k.text = fmtG((e['per100_kcal'] as num).toDouble());
          _p.text = fmtG((e['per100_protein'] as num).toDouble());
          _f.text = fmtG((e['per100_fat'] as num).toDouble());
          _c.text = fmtG((e['per100_carbs'] as num).toDouble());
        } else {
          _k.text = fmtG((e['calories'] as num).toDouble());
          _p.text = fmtG((e['protein'] as num).toDouble());
          _f.text = fmtG((e['fat'] as num).toDouble());
          _c.text = fmtG((e['carbs'] as num).toDouble());
        }
      }
    }
    if (mounted) setState(() => _loaded = true);
  }

  String? _req(String? s, String label) {
    if (s == null || s.trim().isEmpty) {
      return '$label: обязательно (введите 0, если нет)';
    }
    return parseDecimal(s) == null ? '$label: число ≥ 0' : null;
  }

  Nutrients? get _preview {
    final g = parseDecimal(_grams.text);
    final k = parseDecimal(_k.text), p = parseDecimal(_p.text);
    final f = parseDecimal(_f.text), c = parseDecimal(_c.text);
    if (g == null || g <= 0 || k == null || p == null || f == null || c == null) {
      return null;
    }
    return Nutrients(k, p, f, c).scaled(g);
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() => _busy = true); // guards double tap
    try {
      final key = dateKey(_date);
      final k = parseDecimal(_k.text)!, p = parseDecimal(_p.text)!;
      final f = parseDecimal(_f.text)!, c = parseDecimal(_c.text)!;
      if (_product) {
        final per100 = Nutrients(k, p, f, c);
        String? foodId = _orig?['food_id'] as String?;
        if (_remember && !_editing) {
          foodId = await _repo.upsertFood(_name.text, per100);
        }
        await _repo.saveProduct(
          id: widget.entryId,
          date: key,
          meal: _meal == 'other' ? 'snack' : _meal,
          name: _name.text,
          grams: parseDecimal(_grams.text)!,
          per100: per100,
          foodId: foodId,
        );
      } else {
        await _repo.savePortion(
          id: widget.entryId,
          date: key,
          meal: _meal == 'other' ? 'snack' : _meal,
          name: _name.text,
          total: Nutrients(k, p, f, c),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(context, 'Не удалось сохранить: $e'); // no false "saved"
      }
    }
  }

  Widget _num(String label, TextEditingController c, {String? hint}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, helperText: hint),
      validator: (v) => _req(v, label),
      onChanged: (_) => setState(() {}),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final unit = _product ? 'на 100 г' : 'за порцию';
    final pv = _preview;
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Изменить запись' : 'Добавить еду'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_editing)
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'product',
                    label: Text('Продукт и масса'),
                  ),
                  ButtonSegment(
                    value: 'portion',
                    label: Text('Быстрая порция'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              )
            else
              Text(
                _product ? 'Режим: продукт и масса' : 'Режим: быстрая порция',
                style: const TextStyle(color: LlColors.textSecondary),
              ),
            const SizedBox(height: 12),
            if (_product && !_editing && _recent.isNotEmpty) ...[
              const Text(
                'Недавние продукты:',
                style: TextStyle(fontSize: 12, color: LlColors.textSecondary),
              ),
              Wrap(
                spacing: 6,
                children: [
                  for (final r in _recent)
                    ActionChip(
                      label: Text(r['name'] as String),
                      onPressed:
                          () => setState(() {
                            // catalogue's CURRENT values are used for NEW entries
                            _name.text = r['name'] as String;
                            _k.text = fmtG((r['kcal100'] as num).toDouble());
                            _p.text = fmtG((r['protein100'] as num).toDouble());
                            _f.text = fmtG((r['fat100'] as num).toDouble());
                            _c.text = fmtG((r['carbs100'] as num).toDouble());
                          }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Название *'),
              validator:
                  (v) =>
                      (v == null || v.trim().isEmpty)
                          ? 'Название обязательно'
                          : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _meal,
              decoration: const InputDecoration(labelText: 'Приём пищи'),
              items: [
                for (final m in kMeals)
                  DropdownMenuItem(value: m, child: Text(kMealLabels[m]!)),
                if (_meal == 'other')
                  DropdownMenuItem(
                    value: 'other',
                    child: Text(kMealLabels['other']!),
                  ),
              ],
              onChanged: (v) => setState(() => _meal = v ?? _meal),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(_fmtDate(_date)),
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
            const SizedBox(height: 16),
            if (_product)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: _grams,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Съеденная масса, г *',
                  ),
                  validator: (v) {
                    final g = parseDecimal(v);
                    return (g == null || g <= 0)
                        ? 'Масса должна быть больше 0'
                        : null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
              ),
            _num('Калории, ккал ($unit)', _k),
            _num('Белки, г ($unit)', _p),
            _num('Жиры, г ($unit)', _f),
            _num('Углеводы, г ($unit)', _c),
            if (_product)
              Card(
                color: LlColors.surfaceHigh,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    pv == null
                        ? 'Итого: заполните массу и значения на 100 г'
                        : 'Итого: ${fmtKcal(pv.kcal)} ккал • Б ${fmtG(pv.protein)} г • '
                            'Ж ${fmtG(pv.fat)} г • У ${fmtG(pv.carbs)} г',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              )
            else
              const Text(
                'Значения записываются как есть: масса не нужна, на 100 не делится, '
                'калории по БЖУ не пересчитываются.',
                style: TextStyle(fontSize: 12, color: LlColors.textSecondary),
              ),
            if (_product && !_editing)
              CheckboxListTile(
                value: _remember,
                onChanged: (v) => setState(() => _remember = v ?? true),
                title: const Text('Запомнить продукт'),
                contentPadding: EdgeInsets.zero,
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_editing ? 'Сохранить' : 'Добавить'),
            ),
          ],
        ),
      ),
    );
  }
}
