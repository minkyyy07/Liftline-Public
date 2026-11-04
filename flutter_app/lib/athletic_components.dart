import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Design tokens for the Athletic Focus visual language:
/// - Midnight Black foundation
/// - High-contrast Electric Blue accents for primary actions & key states
/// - Subtle architectural borders, reduced gradient noise & glow
/// - Clean typography with high legibility on dark surfaces
class AthleticTokens {
  // Foundations
  static const Color midnight = Color(0xFF0A0E17);
  static const Color surface = Color(0xFF111726);
  static const Color surfaceElevated = Color(0xFF161F33);
  static const Color surfaceHighlight = Color(0xFF1E2A42);

  // Borders
  static const Color border = Color(0xFF1E2B42);
  static const Color borderSubtle = Color(0xFF192335);
  static const Color borderHighlight = Color(0xFF2A3C5C);

  // Accents
  static const Color electricBlue = Color(0xFF4D8DFF);
  static const Color electricOrange = Color(0xFFFF8A3D);
  static const Color success = Color(0xFF22C55E);
  static const Color electricGreen = Color(0xFF22C55E);
  static const Color error = Color(0xFFFF5C5C);

  // Typography
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Nutrition macros
  static const Color macroProtein = Color(0xFF38BDF8); // Cyan / Sky
  static const Color macroFat = Color(0xFFFBBF24);     // Amber / Gold
  static const Color macroCarbs = Color(0xFF34D399);   // Mint / Emerald

  // Spacing
  static const double spaceXs = 4.0;
  static const double spaceSm = 8.0;
  static const double spaceMd = 12.0;
  static const double spaceLg = 16.0;
  static const double spaceXl = 20.0;
  static const double spaceXxl = 24.0;

  // Radii
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 20.0;
}

/// Technical metric box displaying a prominent figure, unit, and label in Athletic Focus style.
class AthleticMetricBox extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final Color? accentColor;

  const AthleticMetricBox({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AthleticTokens.surface,
        borderRadius: BorderRadius.circular(AthleticTokens.radiusMd),
        border: Border.all(color: AthleticTokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AthleticTokens.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: accentColor ?? AthleticTokens.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  unit!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AthleticTokens.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Reusable card in the Athletic Focus aesthetic.
/// Replaces arbitrary nested card containers with clean, calm surfaces.
class AthleticCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final BorderRadius? borderRadius;

  const AthleticCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1.0,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(AthleticTokens.radiusLg);
    final bg = backgroundColor ?? AthleticTokens.surface;
    final bColor = borderColor ?? AthleticTokens.border;

    Widget content = Container(
      padding: padding ?? const EdgeInsets.all(AthleticTokens.spaceLg),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: Border.all(color: bColor, width: borderWidth),
      ),
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: content,
        ),
      );
    }

    return content;
  }
}

/// Compact technical badge for workout status & highlights.
class AthleticBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool showDot;

  const AthleticBadge({
    super.key,
    required this.label,
    this.color = AthleticTokens.electricBlue,
    this.icon,
    this.showDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
              ),
            ),
            const SizedBox(width: 5),
          ] else if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Section header in Athletic Focus style (crisp title with optional action)
class AthleticSectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget? trailing;

  const AthleticSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: AthleticTokens.electricBlue),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: AthleticTokens.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: trailing!,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Horizontal macro nutrient progress indicator (Protein, Fat, Carbs).
/// Shows consumed amount and goal without clipping or clutter across any screen width or text scale.
class AthleticMacroBar extends StatelessWidget {
  final String label;
  final double val;
  final double? goal;
  final Color color;

  const AthleticMacroBar({
    super.key,
    required this.label,
    required this.val,
    required this.goal,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final hasGoal = goal != null && goal! > 0;
    final ratio = hasGoal ? (val / goal!).clamp(0.0, 1.0) : 0.0;
    final valText = hasGoal ? '${val.toInt()} / ${goal!.toInt()} г' : '${val.toInt()} г';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AthleticTokens.textSecondary,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: hasGoal ? ratio : (val > 0 ? 1.0 : 0.0),
                minHeight: 5,
                backgroundColor: const Color(0xFF1E283C),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            fit: FlexFit.loose,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                valText,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular arc calorie gauge with calm athletic styling.
/// Displays clean percentage and progress when goal exists,
/// or an energetic flame placeholder when goal is not set.
class AthleticArcGauge extends StatelessWidget {
  final double? ratio; // null if no goal
  final int kcal;
  final int? goalKcal;

  const AthleticArcGauge({
    super.key,
    required this.ratio,
    required this.kcal,
    required this.goalKcal,
  });

  @override
  Widget build(BuildContext context) {
    const size = 78.0;
    final hasGoal = ratio != null && goalKcal != null && goalKcal! > 0;
    final progress = hasGoal ? ratio!.clamp(0.0, 1.0) : 0.0;
    final percent = (progress * 100).toInt();

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(size, size),
            painter: _AthleticArcPainter(
              progress: hasGoal ? progress : (kcal > 0 ? 1.0 : 0.0),
              bgColor: const Color(0xFF1C273C),
              progressColor: hasGoal ? AthleticTokens.electricBlue : const Color(0xFF334668),
            ),
          ),
          if (hasGoal)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$percent%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'от цели',
                    style: TextStyle(
                      color: AthleticTokens.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            )
          else
            const Icon(
              Icons.local_fire_department_outlined,
              color: AthleticTokens.electricBlue,
              size: 24,
            ),
        ],
      ),
    );
  }
}

class _AthleticArcPainter extends CustomPainter {
  final double progress;
  final Color bgColor;
  final Color progressColor;

  _AthleticArcPainter({
    required this.progress,
    required this.bgColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.5;
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
    if (progress > 0) {
      final sweepAngle = 2 * math.pi * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweepAngle,
        false,
        progPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AthleticArcPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.bgColor != bgColor ||
        oldDelegate.progressColor != progressColor;
  }
}
