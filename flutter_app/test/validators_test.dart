import 'package:flutter_test/flutter_test.dart';
import 'package:liftline_app/validators.dart';

void main() {
  group('validateRequiredText', () {
    test('returns error for null, empty or whitespace', () {
      expect(InputValidators.validateRequiredText(null, 'Название'), isNotNull);
      expect(InputValidators.validateRequiredText('', 'Название'), isNotNull);
      expect(InputValidators.validateRequiredText('   ', 'Название'), isNotNull);
    });

    test('returns null for valid text', () {
      expect(InputValidators.validateRequiredText('Жим лежа', 'Название'), isNull);
      expect(InputValidators.validateRequiredText('  Овсянка  ', 'Название'), isNull);
    });
  });

  group('validatePositiveInt', () {
    test('returns error for non-integer formats', () {
      expect(InputValidators.validatePositiveInt('abc', 'Длительность'), isNotNull);
      expect(InputValidators.validatePositiveInt('12.5', 'Длительность'), isNotNull);
      expect(InputValidators.validatePositiveInt('10,5', 'Длительность'), isNotNull);
    });

    test('returns error for zero and negative numbers', () {
      expect(InputValidators.validatePositiveInt('0', 'Длительность'), isNotNull);
      expect(InputValidators.validatePositiveInt('-1', 'Длительность'), isNotNull);
      expect(InputValidators.validatePositiveInt('-100', 'Длительность'), isNotNull);
    });

    test('handles empty values according to required flag', () {
      expect(InputValidators.validatePositiveInt('', 'Длительность', required: true), isNotNull);
      expect(InputValidators.validatePositiveInt('', 'Длительность', required: false), isNull);
      expect(InputValidators.validatePositiveInt(null, 'Длительность', required: false), isNull);
    });

    test('returns null for valid positive integers', () {
      expect(InputValidators.validatePositiveInt('1', 'Длительность'), isNull);
      expect(InputValidators.validatePositiveInt('60', 'Длительность'), isNull);
      expect(InputValidators.validatePositiveInt(' 120 ', 'Длительность'), isNull);
    });
  });

  group('validateNonNegativeInt', () {
    test('returns error for non-integer formats', () {
      expect(InputValidators.validateNonNegativeInt('abc', 'Калории'), isNotNull);
      expect(InputValidators.validateNonNegativeInt('15.8', 'Калории'), isNotNull);
    });

    test('returns error for negative numbers', () {
      expect(InputValidators.validateNonNegativeInt('-1', 'Калории'), isNotNull);
      expect(InputValidators.validateNonNegativeInt('-500', 'Калории'), isNotNull);
    });

    test('allows zero and positive integers', () {
      expect(InputValidators.validateNonNegativeInt('0', 'Калории'), isNull);
      expect(InputValidators.validateNonNegativeInt('250', 'Калории'), isNull);
    });

    test('handles empty values based on required flag', () {
      expect(InputValidators.validateNonNegativeInt('', 'Калории', required: true), isNotNull);
      expect(InputValidators.validateNonNegativeInt('', 'Калории', required: false), isNull);
      expect(InputValidators.validateNonNegativeInt(null, 'Калории', required: false), isNull);
    });
  });

  group('validateNonNegativeDouble', () {
    test('returns error for invalid formats', () {
      expect(InputValidators.validateNonNegativeDouble('abc', 'Вес'), isNotNull);
      expect(InputValidators.validateNonNegativeDouble('12..3', 'Вес'), isNotNull);
      expect(InputValidators.validateNonNegativeDouble('NaN', 'Вес'), isNotNull);
      expect(InputValidators.validateNonNegativeDouble('Infinity', 'Вес'), isNotNull);
    });

    test('returns error for negative doubles', () {
      expect(InputValidators.validateNonNegativeDouble('-0.1', 'Вес'), isNotNull);
      expect(InputValidators.validateNonNegativeDouble('-50.0', 'Вес'), isNotNull);
      expect(InputValidators.validateNonNegativeDouble('-10,5', 'Вес'), isNotNull);
    });

    test('allows zero and positive numbers with dot or comma', () {
      expect(InputValidators.validateNonNegativeDouble('0', 'Вес'), isNull);
      expect(InputValidators.validateNonNegativeDouble('0.0', 'Вес'), isNull);
      expect(InputValidators.validateNonNegativeDouble('75.5', 'Вес'), isNull);
      expect(InputValidators.validateNonNegativeDouble('75,5', 'Вес'), isNull);
      expect(InputValidators.validateNonNegativeDouble(' 100 ', 'Вес'), isNull);
    });

    test('handles optional empty values', () {
      expect(InputValidators.validateNonNegativeDouble('', 'Белки', required: false), isNull);
      expect(InputValidators.validateNonNegativeDouble(null, 'Белки', required: false), isNull);
      expect(InputValidators.validateNonNegativeDouble('', 'Вес', required: true), isNotNull);
    });
  });

  group('Parsing helpers', () {
    test('parsePositiveInt parses positive int or returns null', () {
      expect(InputValidators.parsePositiveInt('60'), 60);
      expect(InputValidators.parsePositiveInt('0'), isNull);
      expect(InputValidators.parsePositiveInt('-5'), isNull);
      expect(InputValidators.parsePositiveInt('abc'), isNull);
      expect(InputValidators.parsePositiveInt(''), isNull);
    });

    test('parseNonNegativeInt returns value or default', () {
      expect(InputValidators.parseNonNegativeInt('0'), 0);
      expect(InputValidators.parseNonNegativeInt('150'), 150);
      expect(InputValidators.parseNonNegativeInt('-10', defaultValue: 0), 0);
      expect(InputValidators.parseNonNegativeInt('', defaultValue: 10), 10);
    });

    test('parseNonNegativeDouble parses floats with dot and comma', () {
      expect(InputValidators.parseNonNegativeDouble('75.5'), 75.5);
      expect(InputValidators.parseNonNegativeDouble('75,5'), 75.5);
      expect(InputValidators.parseNonNegativeDouble('0'), 0.0);
      expect(InputValidators.parseNonNegativeDouble('-5', defaultValue: 0.0), 0.0);
      expect(InputValidators.parseNonNegativeDouble('', defaultValue: 0.0), 0.0);
    });

    test('parseOptionalText trims and handles empty strings', () {
      expect(InputValidators.parseOptionalText('  150г  '), '150г');
      expect(InputValidators.parseOptionalText('   '), isNull);
      expect(InputValidators.parseOptionalText(''), isNull);
      expect(InputValidators.parseOptionalText(null), isNull);
    });
  });
}
