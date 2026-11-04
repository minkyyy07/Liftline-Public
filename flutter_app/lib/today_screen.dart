import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'athletic_components.dart';
import 'auth/auth_service.dart';
import 'auth/cloud_workout_sync.dart';
import 'auth/login_screen.dart';
import 'auth/profile_screen.dart';
import 'data_events.dart';
import 'db.dart';
import 'nutrition_calc.dart';
import 'nutrition_repo.dart';
import 'nutrition_ui.dart';
import 'progress_repo.dart';
import 'progress_ui.dart';
import 'repo.dart';
import 'sync_status_badge.dart';
import 'week_utils.dart';
import 'workouts_ui.dart';

/// "Сегодня": Athletic Focus home screen.
/// Evolved design direction:
/// - Midnight Black base (#0A0E17)
/// - High-contrast Electric Blue accents for primary actions & key states
/// - Clean typography, crisp key metrics, more breathing room, fewer nested cards
/// - Workout of the day is the primary hero anchor
/// - Real data for nutrition and body weight progress (no fake goals/metrics)
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
  StreamSubscription? _eventsSub;
  void Function()? _dbListener;

  @override
  void initState() {
    super.initState();
    _dbListener = () {
      if (mounted) _load(fromNetwork: true);
    };
    AppDb.instance.addDatabaseSwitchListener(_dbListener!);
    _eventsSub = AppDataEvents.instance.stream.listen((_) {
      if (mounted) _load(fromNetwork: false);
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

  @override
  void didUpdateWidget(covariant TodayScreen old) {
    super.didUpdateWidget(old);
    if (!isSameDay(old.selectedDate, widget.selectedDate)) _load(fromNetwork: false);
  }

  Future<void> _load({bool fromNetwork = false}) async {
    final accountUserId = AppDb.instance.currentUserId;
    final accountEpoch = AppDb.instance.accountEpoch;

    if (_workouts.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      if (fromNetwork && AuthService.instance.isAuthenticated) {
        try {
          await CloudWorkoutSync().syncFromServer(AppDb.instance.db);
        } catch (_) {}
      }
      if (!AppDb.instance.isCurrentAccount(accountUserId, accountEpoch)) return;
      if (!mounted) return;

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

      if (!AppDb.instance.isCurrentAccount(accountUserId, accountEpoch)) return;
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
      if (!AppDb.instance.isCurrentAccount(accountUserId, accountEpoch)) return;
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
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

  Future<void> _recordWeight() async {
    final saved = await showWeightDialog(context, date: widget.selectedDate);
    if (saved == true) _load();
  }

  Future<void> _setGoals() async {
    final saved = await showGoalsDialog(context, widget.selectedDate);
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

  Future<void> _createWorkout() async {
    try {
      final id = await showCreateWorkoutDialog(context, initialDate: widget.selectedDate);
      if (id == null || !mounted) return;
      await _load();
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => WorkoutOverviewScreen(workoutId: id)),
        );
        _load();
      }
    } on ActiveWorkoutExists catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось создать тренировку: $e')),
        );
      }
    }
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
              Icon(Icons.bolt, color: AthleticTokens.electricBlue, size: 22),
              SizedBox(width: 6),
              Text(
                'Liftspire',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (!isToday || !widget.isFollowingToday)
            TextButton(
              onPressed: () => widget.onDateChanged(DateTime.now()),
              child: const Text(
                'Сегодня',
                style: TextStyle(
                  color: AthleticTokens.electricBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ListenableBuilder(
            listenable: AuthService.instance,
            builder: (ctx, _) {
              final isAuth = AuthService.instance.isAuthenticated;
              final user = AuthService.instance.user;
              return IconButton(
                icon: CircleAvatar(
                  radius: 14,
                  backgroundColor: isAuth ? AthleticTokens.electricBlue : Colors.white24,
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
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _error != null
            ? _buildErrorView()
            : _loading && _workouts.isEmpty && _entries == 0 && _weight == null
                ? const Center(
                    child: CircularProgressIndicator(color: AthleticTokens.electricBlue),
                  )
                : _buildContent(context),
      ),
    );
  }

  Widget _buildErrorView() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        AthleticCard(
          borderColor: AthleticTokens.error.withValues(alpha: 0.5),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AthleticTokens.error, size: 36),
              const SizedBox(height: 12),
              const Text(
                'Ошибка загрузки данных',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AthleticTokens.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AthleticTokens.electricBlue,
                  foregroundColor: Colors.black,
                ),
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Повторить', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // 1. Kinetic Week Strip & Date Selector
        _buildKineticCalendar(context),
        const SizedBox(height: 16),

        // 2. HERO: Workout of the Day (Главный акцент)
        _buildWorkoutHero(context),
        const SizedBox(height: 18),

        // 3. Compact Nutrition Summary (Сводка питания)
        _buildNutritionSummary(context),
        const SizedBox(height: 18),

        // 4. Progress / Body Weight Pod (Краткий прогресс)
        _buildWeightPod(context),
        const SizedBox(height: 20),

        // 5. Quick Actions Dock (Быстрые действия)
        _buildQuickActions(context),
      ],
    );
  }

  Widget _buildKineticCalendar(BuildContext context) {
    final days = weekDays(widget.selectedDate);
    final dayNames = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];
    final dateFmt = DateFormat('d MMMM yyyy, EEEE', 'ru');
    final isToday = isSameDay(widget.selectedDate, DateTime.now());

    return AthleticCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 15,
                          color: AthleticTokens.electricBlue,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            dateFmt.format(widget.selectedDate),
                            style: const TextStyle(
                              fontSize: 13,
                              color: AthleticTokens.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_drop_down,
                          color: AthleticTokens.textSecondary,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (isToday)
                const AthleticBadge(
                  label: 'СЕГОДНЯ',
                  color: AthleticTokens.electricBlue,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (int i = 0; i < 7; i++)
                Expanded(
                  child: _buildDayPill(
                    day: days[i],
                    dayName: dayNames[i],
                    isSelected: isSameDay(days[i], widget.selectedDate),
                    isToday: isSameDay(days[i], DateTime.now()),
                    hasWorkout: _workoutDays.contains(dateKey(days[i])),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayPill({
    required DateTime day,
    required String dayName,
    required bool isSelected,
    required bool isToday,
    required bool hasWorkout,
  }) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$dayName ${day.day}${hasWorkout ? ', есть тренировка' : ''}',
      child: GestureDetector(
        onTap: () => widget.onDateChanged(day),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          margin: const EdgeInsets.symmetric(horizontal: 2.0),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? AthleticTokens.electricBlue
                : (isToday ? const Color(0xFF19253B) : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AthleticTokens.electricBlue
                  : (isToday
                      ? AthleticTokens.electricBlue.withValues(alpha: 0.6)
                      : AthleticTokens.borderSubtle),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  dayName,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.black : AthleticTokens.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? Colors.black : Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasWorkout
                      ? (isSelected ? Colors.black : AthleticTokens.electricBlue)
                      : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// HERO: Workout of the Day (Главный акцент — тренировка дня)
  Widget _buildWorkoutHero(BuildContext context) {
    // 1. Active workout in progress
    if (_active != null) {
      final title = _active!['title'] as String? ?? 'Тренировка';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AthleticSectionHeader(
            title: 'Тренировки дня',
            icon: Icons.bolt,
          ),
          const SizedBox(height: 6),
          AthleticCard(
            borderColor: AthleticTokens.electricOrange.withValues(alpha: 0.5),
            backgroundColor: const Color(0xFF141C2C),
            padding: const EdgeInsets.all(16),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WorkoutOverviewScreen(workoutId: _active!['id'] as String),
                ),
              );
              _load();
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: AthleticBadge(
                          label: 'СЕССИЯ В ПРОЦЕССЕ',
                          color: AthleticTokens.electricOrange,
                          showDot: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: AthleticTokens.textSecondary,
                      size: 14,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Тренировка начата • Нажмите, чтобы продолжить',
                  style: TextStyle(
                    color: AthleticTokens.textSecondary,
                    fontSize: 12,
                  ),
                ),
                SyncStatusBadge(
                  workoutId: _active!['id'] as String,
                  syncStatus: _active!['sync_status'] as String? ?? 'synced',
                  syncError: _active!['sync_error'] as String?,
                  onRetryFinished: () => _load(fromNetwork: false),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AthleticTokens.electricBlue,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WorkoutOverviewScreen(workoutId: _active!['id'] as String),
                        ),
                      );
                      _load();
                    },
                    icon: const Icon(Icons.play_arrow, size: 20),
                    label: const Text(
                      'Продолжить',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // 2. Planned workout on selected date
    if (_workouts.isNotEmpty) {
      final primary = _workouts.first;
      final title = primary['title'] as String;
      final duration = primary['duration_minutes'] ?? 0;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AthleticSectionHeader(
            title: 'Тренировки дня',
            icon: Icons.bolt,
          ),
          const SizedBox(height: 6),
          AthleticCard(
            padding: const EdgeInsets.all(16),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WorkoutOverviewScreen(workoutId: primary['id'] as String),
                ),
              );
              _load();
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: AthleticBadge(
                          label: 'ЗАПЛАНИРОВАНО',
                          color: AthleticTokens.electricBlue,
                          icon: Icons.event_available,
                        ),
                      ),
                    ),
                    if (_workouts.length > 1) ...[
                      const SizedBox(width: 8),
                      Text(
                        '+ ещё ${_workouts.length - 1}',
                        style: const TextStyle(
                          color: AthleticTokens.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Длительность: $duration мин',
                  style: const TextStyle(
                    color: AthleticTokens.textSecondary,
                    fontSize: 12,
                  ),
                ),
                SyncStatusBadge(
                  workoutId: primary['id'] as String,
                  syncStatus: primary['sync_status'] as String? ?? 'synced',
                  syncError: primary['sync_error'] as String?,
                  onRetryFinished: () => _load(fromNetwork: false),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AthleticTokens.electricBlue,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WorkoutOverviewScreen(workoutId: primary['id'] as String),
                        ),
                      );
                      _load();
                    },
                    icon: const Icon(Icons.play_arrow, size: 20),
                    label: const Text(
                      'Начать тренировку',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // 3. No plan: clear athletic invitation to create or pick
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AthleticSectionHeader(
          title: 'Тренировки дня',
          icon: Icons.bolt,
        ),
        const SizedBox(height: 6),
        AthleticCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AthleticTokens.electricBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.fitness_center,
                      color: AthleticTokens.electricBlue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'На эту дату тренировок нет',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Запланируйте тренировку или выберите из списка',
                          style: TextStyle(
                            color: AthleticTokens.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final textScale = MediaQuery.textScalerOf(context).scale(1.0);
                  final isNarrow = constraints.maxWidth < 340 || textScale > 1.2;

                  if (isNarrow) {
                    return Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AthleticTokens.electricBlue,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: _createWorkout,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text(
                              'Создать тренировку',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AthleticTokens.border),
                              foregroundColor: AthleticTokens.textPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => widget.onGoToTab(1),
                            child: const Text('Выбрать из списка'),
                          ),
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AthleticTokens.electricBlue,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: _createWorkout,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text(
                            'Создать тренировку',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AthleticTokens.border),
                            foregroundColor: AthleticTokens.textPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => widget.onGoToTab(1),
                          child: const Text('Выбрать из списка'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Nutrition summary with real data (no fictitious 2400 kcal fallback)
  Widget _buildNutritionSummary(BuildContext context) {
    final hasGoal = _goals.calories != null && _goals.calories! > 0;
    final calGoal = _goals.calories?.round();
    final ratio = hasGoal ? (_totals.kcal / _goals.calories!).clamp(0.0, 1.0) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AthleticSectionHeader(
          title: 'Питание',
          icon: Icons.restaurant,
          trailing: InkWell(
            onTap: _setGoals,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                hasGoal ? 'Изменить цель' : 'Задать цель',
                style: const TextStyle(
                  color: AthleticTokens.electricBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        AthleticCard(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1.0);
              final isCompact = constraints.maxWidth < 360 || textScale > 1.2;

              final calorieHeader = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          fmtKcal(_totals.kcal),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          hasGoal ? '/ $calGoal ккал' : 'ккал',
                          style: const TextStyle(
                            color: AthleticTokens.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    !hasGoal
                        ? 'Цель не задана'
                        : _entries == 0
                            ? 'Нет записей за день'
                            : 'Записей за день: $_entries',
                    style: const TextStyle(
                      color: AthleticTokens.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              );

              final macroBars = Column(
                children: [
                  AthleticMacroBar(
                    label: 'Белки',
                    val: _totals.protein,
                    goal: _goals.protein,
                    color: AthleticTokens.macroProtein,
                  ),
                  AthleticMacroBar(
                    label: 'Жиры',
                    val: _totals.fat,
                    goal: _goals.fat,
                    color: AthleticTokens.macroFat,
                  ),
                  AthleticMacroBar(
                    label: 'Углеводы',
                    val: _totals.carbs,
                    goal: _goals.carbs,
                    color: AthleticTokens.macroCarbs,
                  ),
                ],
              );

              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AthleticArcGauge(
                          ratio: ratio,
                          kcal: _totals.kcal.round(),
                          goalKcal: calGoal,
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: calorieHeader),
                      ],
                    ),
                    const SizedBox(height: 12),
                    macroBars,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AthleticArcGauge(
                    ratio: ratio,
                    kcal: _totals.kcal.round(),
                    goalKcal: calGoal,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        calorieHeader,
                        const SizedBox(height: 8),
                        macroBars,
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Real body weight progress pod
  Widget _buildWeightPod(BuildContext context) {
    final w = _weight;
    final isDay = w != null && w['date'] == dateKey(widget.selectedDate);
    final kgStr = w != null ? fmtG((w['kg'] as num).toDouble()) : '--';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AthleticSectionHeader(
          title: 'Вес тела',
          icon: Icons.monitor_weight_outlined,
        ),
        const SizedBox(height: 6),
        AthleticCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1.0);
              final isNarrow = constraints.maxWidth < 360 || textScale > 1.2;

              final info = Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF192438),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.monitor_weight_outlined,
                      color: AthleticTokens.electricBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                kgStr,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'кг',
                                style: TextStyle(
                                  color: AthleticTokens.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          w == null
                              ? 'Измерений до этой даты нет'
                              : isDay
                                  ? 'Измерение за этот день'
                                  : 'Последнее: ${DateFormat('d MMM yyyy', 'ru').format(DateTime.parse(w['date'] as String))}',
                          style: const TextStyle(
                            color: AthleticTokens.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              );

              final btn = OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AthleticTokens.border),
                  foregroundColor: AthleticTokens.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: const Size(0, 36),
                ),
                onPressed: _recordWeight,
                child: const Text('Записать вес', style: TextStyle(fontSize: 12)),
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    info,
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerRight, child: btn),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 8),
                  btn,
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Secondary quick actions dock: Add food, Record weight
  Widget _buildQuickActions(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final isNarrow = constraints.maxWidth < 340 || textScale > 1.2;

        if (isNarrow) {
          return Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AthleticTokens.border),
                    foregroundColor: AthleticTokens.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _addFood,
                  icon: const Icon(Icons.restaurant_outlined, size: 18, color: AthleticTokens.electricBlue),
                  label: const Text('Добавить еду', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AthleticTokens.border),
                    foregroundColor: AthleticTokens.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _recordWeight,
                  icon: const Icon(Icons.monitor_weight_outlined, size: 18, color: AthleticTokens.electricBlue),
                  label: const Text('Записать вес', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AthleticTokens.border),
                  foregroundColor: AthleticTokens.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _addFood,
                icon: const Icon(Icons.restaurant_outlined, size: 18, color: AthleticTokens.electricBlue),
                label: const Text('Добавить еду', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AthleticTokens.border),
                  foregroundColor: AthleticTokens.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _recordWeight,
                icon: const Icon(Icons.monitor_weight_outlined, size: 18, color: AthleticTokens.electricBlue),
                label: const Text('Записать вес', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        );
      },
    );
  }
}
