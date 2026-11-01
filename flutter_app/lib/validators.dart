class InputValidators {
  /// Validates that [value] is non-null and not empty/whitespace.
  static String? validateRequiredText(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return 'Поле "$fieldName" обязательно для заполнения';
    }
    return null;
  }

  /// Validates that [value] is a strictly positive integer (> 0).
  static String? validatePositiveInt(
    String? value,
    String fieldName, {
    bool required = true,
  }) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'Поле "$fieldName" обязательно для заполнения' : null;
    }
    final trimmed = value.trim();
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed <= 0) {
      return 'Поле "$fieldName" должно быть целым положительным числом';
    }
    return null;
  }

  /// Validates that [value] is a non-negative integer (>= 0).
  static String? validateNonNegativeInt(
    String? value,
    String fieldName, {
    bool required = true,
  }) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'Поле "$fieldName" обязательно для заполнения' : null;
    }
    final trimmed = value.trim();
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed < 0) {
      return 'Поле "$fieldName" должно быть целым неотрицательным числом';
    }
    return null;
  }

  /// Validates that [value] is a finite non-negative real number (>= 0.0).
  /// Normalizes comma to dot for locale support (e.g., "12,5" -> "12.5").
  static String? validateNonNegativeDouble(
    String? value,
    String fieldName, {
    bool required = true,
  }) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'Поле "$fieldName" обязательно для заполнения' : null;
    }
    final normalized = value.trim().replaceAll(',', '.');
    final parsed = double.tryParse(normalized);
    if (parsed == null || !parsed.isFinite || parsed.isNaN || parsed < 0) {
      return 'Поле "$fieldName" должно быть конечным неотрицательным числом';
    }
    return null;
  }

  /// Parses a string into a positive integer, or returns null if invalid / <= 0.
  static int? parsePositiveInt(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = int.tryParse(value.trim());
    if (parsed != null && parsed > 0) return parsed;
    return null;
  }

  /// Parses a string into a non-negative integer, or returns [defaultValue] if empty/invalid.
  static int? parseNonNegativeInt(String? value, {int? defaultValue}) {
    if (value == null || value.trim().isEmpty) return defaultValue;
    final parsed = int.tryParse(value.trim());
    if (parsed != null && parsed >= 0) return parsed;
    return defaultValue;
  }

  /// Parses a string into a finite non-negative double, or returns [defaultValue] if empty/invalid.
  static double? parseNonNegativeDouble(String? value, {double? defaultValue}) {
    if (value == null || value.trim().isEmpty) return defaultValue;
    final normalized = value.trim().replaceAll(',', '.');
    final parsed = double.tryParse(normalized);
    if (parsed != null && parsed.isFinite && !parsed.isNaN && parsed >= 0) {
      return parsed;
    }
    return defaultValue;
  }

  /// Trims text and returns null if empty.
  static String? parseOptionalText(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
