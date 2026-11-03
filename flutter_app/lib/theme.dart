import 'package:flutter/material.dart';

/// Liftline design tokens (dark blue-black theme, green accent).
class LlColors {
  static const background = Color(0xFF030817);
  static const surface = Color(0xFF10192B);
  static const surfaceHigh = Color(0xFF1B293B);
  static const text = Color(0xFFF5F7FC);
  static const textSecondary = Color(0xFFA3AEC2);
  static const accent = Color(0xFF35D879);
  static const secondary = Color(0xFF4B9BFF);
  static const warning = Color(0xFFFFB454);
  static const error = Color(0xFFFF6B6B);
}

ThemeData buildLiftlineTheme() {
  const scheme = ColorScheme.dark(
    primary: LlColors.accent,
    onPrimary: Color(0xFF03130A),
    secondary: LlColors.secondary,
    surface: LlColors.surface,
    onSurface: LlColors.text,
    onSurfaceVariant: LlColors.textSecondary,
    surfaceContainerHighest: LlColors.surfaceHigh,
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
    ),
    cardTheme: CardThemeData(
      color: LlColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: LlColors.surface,
      indicatorColor: LlColors.accent.withValues(alpha: 0.15),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: LlColors.accent, size: 24);
        }
        return const IconThemeData(color: LlColors.textSecondary, size: 24);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: LlColors.accent,
          );
        }
        return const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: LlColors.textSecondary,
        );
      }),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: LlColors.accent,
      foregroundColor: Color(0xFF03130A),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: LlColors.surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    textTheme: ThemeData.dark().textTheme.apply(
      bodyColor: LlColors.text,
      displayColor: LlColors.text,
    ),
  );
}
