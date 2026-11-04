import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'nutrition_calc.dart';
import 'nutrition_repo.dart';
import 'nutrition_ui.dart';
import 'progress_ui.dart';
import 'theme.dart';
import 'week_utils.dart';
import 'workouts_ui.dart';

// =============================================================================
// CONCEPT 1: ATHLETIC HIGH-PERFORMANCE FOCUS (Action & Metric Heavy)
// =============================================================================

class Concept1AthleticView extends StatelessWidget {
  final DateTime selectedDate;
  final bool isFollowingToday;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<int> onGoToTab;
  final Nutrients totals;
  final NutritionGoals goals;
  final int entriesCount;
  final List<Map<String, Object?>> workouts;
  final Set<String> workoutDays;
  final Map<String, Object?>? activeWorkout;
  final Map<String, Object?>? weightRecord;
  final VoidCallback onRefresh;
  final VoidCallback onAddFood;

  const Concept1AthleticView({
    super.key,
    required this.selectedDate,
    required this.isFollowingToday,
    required this.onDateChanged,
    required this.onGoToTab,
    required this.totals,
    required this.goals,
    required this.entriesCount,
    required this.workouts,
    required this.workoutDays,
    required this.activeWorkout,
    required this.weightRecord,
    required this.onRefresh,
    required this.onAddFood,
  });

  @override
  Widget build(BuildContext context) {
    final hasActive = activeWorkout != null;
    final calGoal = (goals.calories ?? 2400).toDouble();
    final calRatio = calGoal <= 0 ? 0.0 : (totals.kcal / calGoal).clamp(0.0, 1.0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // 1. Kinetic Day & Calendar Header
        _buildKineticCalendar(context),
        const SizedBox(height: 16),

        // 2. HERO: Active Workout Card or High-Performance Training Pod
        if (hasActive)
          _buildActiveWorkoutHero(context)
        else
          _buildReadyToTrainHero(context),
        const SizedBox(height: 18),

        // 3. Asymmetric Nutrition Power Grid
        _buildNutritionPowerGrid(context, calGoal.round(), calRatio),
        const SizedBox(height: 18),

        // 4. Athletic Weight & Body Stat Pod
        _buildWeightStatPod(context),
        const SizedBox(height: 18),

        // 5. Scheduled / Completed Workouts Stream
        _buildWorkoutsStream(context),
        const SizedBox(height: 24),

        // 6. Action Dock
        _buildActionDock(context),
      ],
    );
  }

  Widget _buildKineticCalendar(BuildContext context) {
    final days = weekDays(selectedDate);
    final dayNames = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];
    final dateFmt = DateFormat('d MMMM yyyy, EEEE', 'ru');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101726),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E2B45), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: LlColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: LlColors.accent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt, color: LlColors.accent, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'НЕДЕЛЬНЫЙ ЦИКЛ',
                      style: TextStyle(
                        color: LlColors.accent.withValues(alpha: 0.9),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked != null) onDateChanged(picked);
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        dateFmt.format(selectedDate),
                        style: const TextStyle(
                          fontSize: 12,
                          color: LlColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, color: LlColors.textSecondary, size: 18),
                    ],
                  ),
                ),
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
                    isSelected: isSameDay(days[i], selectedDate),
                    isToday: isSameDay(days[i], DateTime.now()),
                    hasWorkout: workoutDays.contains(dateKey(days[i])),
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
    return GestureDetector(
      onTap: () => onDateChanged(day),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 2.5),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? LlColors.accent
              : (isToday ? const Color(0xFF1E293B) : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? LlColors.accent
                : (isToday ? LlColors.accent.withValues(alpha: 0.5) : const Color(0xFF1E293B)),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: LlColors.accent.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Text(
              dayName,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.black : LlColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: isSelected ? Colors.black : Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasWorkout
                    ? (isSelected ? Colors.black : LlColors.accent)
                    : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveWorkoutHero(BuildContext context) {
    final title = activeWorkout!['title'] as String? ?? 'Тренировка';
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3A8A), Color(0xFF0F172A)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LlColors.accent, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: LlColors.accent.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => WorkoutOverviewScreen(
                  workoutId: activeWorkout!['id'] as String,
                ),
              ),
            );
            onRefresh();
          },
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 10),
                          SizedBox(width: 5),
                          Text(
                            'СЕССИЯ В ПРОЦЕССЕ',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: LlColors.accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      ),
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WorkoutOverviewScreen(
                              workoutId: activeWorkout!['id'] as String,
                            ),
                          ),
                        );
                        onRefresh();
                      },
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text(
                        'Продолжить',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReadyToTrainHero(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1F2937), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: LlColors.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.fitness_center, color: LlColors.accent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Готовы к тренировке?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  workouts.isEmpty ? 'Запланируйте или начните сессию' : 'Запланировано: ${workouts.length}',
                  style: const TextStyle(
                    color: LlColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: LlColors.accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: const Size(0, 38),
            ),
            onPressed: () => onGoToTab(1),
            child: const Text('Старт', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _buildNutritionPowerGrid(BuildContext context, int calGoal, double calRatio) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF1E293B), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.bolt, color: LlColors.accent, size: 18),
                  const SizedBox(width: 6),
                  const Text(
                    'БАЛАНС ЭНЕРГИИ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () async {
                  if (await showGoalsDialog(context, selectedDate)) onRefresh();
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    'Цель',
                    style: TextStyle(
                      color: LlColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Radial / Arc representation
              SizedBox(
                width: 90,
                height: 90,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(90, 90),
                      painter: _ArcProgressPainter(
                        progress: calRatio,
                        bgColor: const Color(0xFF1E293B),
                        progressColor: LlColors.accent,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(calRatio * 100).toInt()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'от цели',
                          style: TextStyle(
                            color: LlColors.textSecondary.withValues(alpha: 0.8),
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          fmtKcal(totals.kcal),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '/ $calGoal ккал',
                          style: const TextStyle(
                            color: LlColors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildMacroPillBar('Белки', totals.protein, goals.protein ?? 160, const Color(0xFF38BDF8)),
                    const SizedBox(height: 5),
                    _buildMacroPillBar('Жиры', totals.fat, goals.fat ?? 70, const Color(0xFFFBBF24)),
                    const SizedBox(height: 5),
                    _buildMacroPillBar('Углеводы', totals.carbs, goals.carbs ?? 280, const Color(0xFF34D399)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF334155)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: const Size(0, 36),
                ),
                onPressed: onAddFood,
                icon: const Icon(Icons.add, size: 16, color: LlColors.accent),
                label: const Text('Добавить приём пищи', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMacroPillBar(String label, double val, double goal, Color color) {
    final ratio = goal <= 0 ? 0.0 : (val / goal).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: const TextStyle(color: LlColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: const Color(0xFF1E293B),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 48,
          child: Text(
            '${val.toInt()}г',
            textAlign: TextAlign.end,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _buildWeightStatPod(BuildContext context) {
    final w = weightRecord;
    final hasVal = w != null;
    final kgStr = hasVal ? fmtG((w['kg'] as num).toDouble()) : '--';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF101726),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.monitor_weight_outlined, color: LlColors.accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'МАССА ТЕЛА',
                  style: TextStyle(
                    color: LlColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      kgStr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'кг',
                      style: TextStyle(color: LlColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF334155)),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(0, 36),
            ),
            onPressed: () async {
              if (await showWeightDialog(context, date: selectedDate)) onRefresh();
            },
            child: const Text('Внести', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutsStream(BuildContext context) {
    if (workouts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: Column(
          children: [
            const Icon(Icons.event_available, color: LlColors.textSecondary, size: 28),
            const SizedBox(height: 8),
            const Text(
              'На сегодня тренировок нет',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'Отличный день для восстановления или легкой активности',
              textAlign: TextAlign.center,
              style: TextStyle(color: LlColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => onGoToTab(1),
              child: const Text('Перейти к тренировкам'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ТРЕНИРОВКИ ДНЯ',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        for (final w in workouts)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1F2937)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: LlColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.fitness_center, color: LlColors.accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        w['title'] as String,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Длительность: ${w['duration_minutes'] ?? 0} мин',
                        style: const TextStyle(color: LlColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildActionDock(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: LlColors.accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => onGoToTab(1),
            icon: const Icon(Icons.fitness_center),
            label: const Text('К тренировкам', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF334155)),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: onAddFood,
            icon: const Icon(Icons.restaurant, color: LlColors.accent),
            label: const Text('Добавить еду', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

class _ArcProgressPainter extends CustomPainter {
  final double progress;
  final Color bgColor;
  final Color progressColor;

  _ArcProgressPainter({
    required this.progress,
    required this.bgColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;

    final bgPaint = Paint()
      ..color = bgColor
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke;

    final progPaint = Paint()
      ..color = progressColor
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, bgPaint);
    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      progPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ArcProgressPainter old) =>
      old.progress != progress || old.progressColor != progressColor;
}

// =============================================================================
// CONCEPT 2: MODERN MINIMALIST STREAM (Timeline & Precision Flow)
// =============================================================================

class Concept2MinimalistView extends StatelessWidget {
  final DateTime selectedDate;
  final bool isFollowingToday;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<int> onGoToTab;
  final Nutrients totals;
  final NutritionGoals goals;
  final int entriesCount;
  final List<Map<String, Object?>> workouts;
  final Set<String> workoutDays;
  final Map<String, Object?>? activeWorkout;
  final Map<String, Object?>? weightRecord;
  final VoidCallback onRefresh;
  final VoidCallback onAddFood;

  const Concept2MinimalistView({
    super.key,
    required this.selectedDate,
    required this.isFollowingToday,
    required this.onDateChanged,
    required this.onGoToTab,
    required this.totals,
    required this.goals,
    required this.entriesCount,
    required this.workouts,
    required this.workoutDays,
    required this.activeWorkout,
    required this.weightRecord,
    required this.onRefresh,
    required this.onAddFood,
  });

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMMM, EEEE', 'ru');
    final calGoal = (goals.calories ?? 2400).toDouble();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      children: [
        // 1. Sleek Minimal Date Selector
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'СЕГОДНЯШНИЙ ОБЗОР',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: LlColors.textSecondary.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateFmt.format(selectedDate),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            IconButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                );
                if (picked != null) onDateChanged(picked);
              },
              icon: const Icon(Icons.calendar_month, color: LlColors.accent, size: 22),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Minimal Horizontal Week Dots
        _buildMinimalWeekStrip(),
        const SizedBox(height: 24),

        // 2. Timeline Item: Workout Segment
        _buildTimelineSectionHeader('ТРЕНИРОВКА', Icons.fitness_center),
        const SizedBox(height: 10),
        _buildWorkoutMinimalStream(context),
        const SizedBox(height: 24),

        // 3. Timeline Item: Nutrition Segment
        _buildTimelineSectionHeader('ПИТАНИЕ И КАЛОРИИ', Icons.local_dining),
        const SizedBox(height: 10),
        _buildNutritionMinimalStream(context, calGoal),
        const SizedBox(height: 24),

        // 4. Timeline Item: Body Weight Segment
        _buildTimelineSectionHeader('МАССА ТЕЛА', Icons.show_chart),
        const SizedBox(height: 10),
        _buildWeightMinimalStream(context),
      ],
    );
  }

  Widget _buildMinimalWeekStrip() {
    final days = weekDays(selectedDate);
    final dayLetters = ['П', 'В', 'С', 'Ч', 'П', 'С', 'В'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F131D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1B2233)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (int i = 0; i < 7; i++)
            GestureDetector(
              onTap: () => onDateChanged(days[i]),
              child: Column(
                children: [
                  Text(
                    dayLetters[i],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSameDay(days[i], selectedDate)
                          ? LlColors.accent
                          : LlColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSameDay(days[i], selectedDate)
                          ? LlColors.accent.withValues(alpha: 0.18)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                      border: isSameDay(days[i], selectedDate)
                          ? Border.all(color: LlColors.accent, width: 1.5)
                          : (isSameDay(days[i], DateTime.now())
                              ? Border.all(color: const Color(0xFF334155))
                              : null),
                    ),
                    child: Text(
                      '${days[i].day}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSameDay(days[i], selectedDate)
                            ? FontWeight.w900
                            : FontWeight.w600,
                        color: isSameDay(days[i], selectedDate)
                            ? Colors.white
                            : Colors.white70,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(
                    Icons.circle,
                    size: 4,
                    color: workoutDays.contains(dateKey(days[i]))
                        ? LlColors.accent
                        : Colors.transparent,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimelineSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: LlColors.accent),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: LlColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildWorkoutMinimalStream(BuildContext context) {
    if (activeWorkout != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF111726),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: LlColors.accent.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'АКТИВНАЯ СЕССИЯ',
                    style: TextStyle(color: LlColors.accent, fontSize: 10, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    activeWorkout!['title'] as String? ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: LlColors.accent,
                foregroundColor: Colors.black,
              ),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WorkoutOverviewScreen(
                      workoutId: activeWorkout!['id'] as String,
                    ),
                  ),
                );
                onRefresh();
              },
              child: const Text('Продолжить', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }

    if (workouts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0F131D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1B2233)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Тренировок нет',
              style: TextStyle(color: LlColors.textSecondary, fontSize: 14),
            ),
            TextButton(
              onPressed: () => onGoToTab(1),
              child: const Text('Запланировать', style: TextStyle(color: LlColors.accent)),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (final w in workouts)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0F131D),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF1B2233)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    w['title'] as String,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${w['duration_minutes'] ?? 0} мин',
                  style: const TextStyle(color: LlColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildNutritionMinimalStream(BuildContext context, double calGoal) {
    final pct = calGoal <= 0 ? 0 : ((totals.kcal / calGoal) * 100).toInt();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F131D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1B2233)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fmtKcal(totals.kcal),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                  Text(
                    'из ${calGoal.round()} ккал ($pct%)',
                    style: const TextStyle(color: LlColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF26324A)),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 36),
                ),
                onPressed: onAddFood,
                icon: const Icon(Icons.add, size: 16, color: LlColors.accent),
                label: const Text('Запись', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: calGoal <= 0 ? 0.0 : (totals.kcal / calGoal).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: const Color(0xFF1A2234),
              valueColor: const AlwaysStoppedAnimation<Color>(LlColors.accent),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMacroMinimalCol('Белки', totals.protein, goals.protein ?? 160),
              _buildMacroMinimalCol('Жиры', totals.fat, goals.fat ?? 70),
              _buildMacroMinimalCol('Углеводы', totals.carbs, goals.carbs ?? 280),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMacroMinimalCol(String name, double val, double goal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: const TextStyle(color: LlColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 2),
        Text(
          '${val.toInt()} / ${goal.toInt()}г',
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildWeightMinimalStream(BuildContext context) {
    final w = weightRecord;
    final hasVal = w != null;
    final kgStr = hasVal ? fmtG((w['kg'] as num).toDouble()) : '--';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F131D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1B2233)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                kgStr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 4),
              const Text('кг', style: TextStyle(color: LlColors.textSecondary, fontSize: 14)),
            ],
          ),
          TextButton(
            onPressed: () async {
              if (await showWeightDialog(context, date: selectedDate)) onRefresh();
            },
            child: const Text('Записать вес', style: TextStyle(color: LlColors.accent)),
          ),
        ],
      ),
    );
  }
}
