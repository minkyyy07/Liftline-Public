import 'package:flutter/material.dart';

/// Liftspire design tokens:
/// - Midnight Black: #0A0E17 (dark background)
/// - Electric Blue: #4D8DFF (primary brand accent)
/// - Electric Orange: #FF8A3D (secondary accent)
/// - Semantic Success: #22C55E (for completed sets, goal milestones)
class LlColors {
  // Brand foundations
  static const background = Color(0xFF0A0E17);
  static const surface = Color(0xFF121826);
  static const surfaceHigh = Color(0xFF1C2436);
  static const border = Color(0xFF253046);

  // Typography
  static const text = Color(0xFFF8FAFC);
  static const textSecondary = Color(0xFF94A3B8);

  // Brand Accents
  static const accent = Color(0xFF4D8DFF); // Electric Blue (#4D8DFF)
  static const primary = Color(0xFF4D8DFF);
  static const secondary = Color(0xFFFF8A3D); // Electric Orange (#FF8A3D)
  static const electricBlue = Color(0xFF4D8DFF);
  static const electricOrange = Color(0xFFFF8A3D);

  // Semantic statuses
  static const success = Color(0xFF22C55E); // Green for completed sets / goal success only
  static const warning = Color(0xFFFFB454);
  static const error = Color(0xFFFF5C5C);
}

ThemeData buildLiftlineTheme() {
  const scheme = ColorScheme.dark(
    primary: LlColors.primary,
    onPrimary: Color(0xFF060B14),
    secondary: LlColors.secondary,
    onSecondary: Color(0xFF060B14),
    surface: LlColors.surface,
    onSurface: LlColors.text,
    onSurfaceVariant: LlColors.textSecondary,
    surfaceContainerHighest: LlColors.surfaceHigh,
    outline: LlColors.border,
    error: LlColors.error,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: LlColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: LlColors.background,
      foregroundColor: LlColors.text,
      centerTitle: true,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: LlColors.text,
        fontSize: 18,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: LlColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: LlColors.border, width: 1),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: LlColors.surface,
      indicatorColor: LlColors.primary.withValues(alpha: 0.18),
      elevation: 0,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: LlColors.primary, size: 24);
        }
        return const IconThemeData(color: LlColors.textSecondary, size: 24);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            fontSize: 11,
            letterSpacing: -0.3,
            fontWeight: FontWeight.w600,
            overflow: TextOverflow.ellipsis,
            color: LlColors.primary,
          );
        }
        return const TextStyle(
          fontSize: 11,
          letterSpacing: -0.3,
          fontWeight: FontWeight.w500,
          overflow: TextOverflow.ellipsis,
          color: LlColors.textSecondary,
        );
      }),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: LlColors.primary,
      foregroundColor: Color(0xFF060B14),
      elevation: 3,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: LlColors.primary,
        foregroundColor: const Color(0xFF060B14),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: LlColors.primary,
        side: const BorderSide(color: LlColors.primary, width: 1.2),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: LlColors.primary,
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: LlColors.surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: LlColors.border, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: LlColors.border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: LlColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: LlColors.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: LlColors.error, width: 1.5),
      ),
      labelStyle: const TextStyle(color: LlColors.textSecondary, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: LlColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: LlColors.border, width: 1),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: LlColors.surface,
      modalBackgroundColor: LlColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      checkColor: WidgetStateProperty.all(const Color(0xFF060B14)),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return LlColors.success;
        }
        return Colors.transparent;
      }),
      side: const BorderSide(color: LlColors.textSecondary, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    dividerTheme: const DividerThemeData(
      color: LlColors.border,
      thickness: 1,
      space: 1,
    ),
    textTheme: ThemeData.dark().textTheme.apply(
      bodyColor: LlColors.text,
      displayColor: LlColors.text,
    ),
  );
}
