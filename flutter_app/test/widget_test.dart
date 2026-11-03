import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:liftline_app/app_shell.dart';
import 'package:liftline_app/db.dart';
import 'package:liftline_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Full app launch, Liftspire branding, and tab navigation test', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    late Database db;
    await tester.runAsync(() async {
      db = await openLiftlineDb(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      AppDb.instance.useDatabase(db);
    });

    await tester.pumpWidget(const LiftlineApp());
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    // Verify MaterialApp title and UI branding
    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.title, 'Liftspire');
    expect(find.text('Liftspire'), findsOneWidget);
    expect(find.byType(MainNavigationScreen), findsOneWidget);

    // Initial tab: "Сегодня"
    expect(find.text('Питание'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Тренировки дня'), 200);
    expect(find.text('Тренировки дня'), findsOneWidget);

    // Navigate to "Тренировки" (Tab 1)
    await tester.tap(find.byIcon(Icons.fitness_center_outlined));
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Тренировок пока нет'), findsOneWidget);

    // Navigate to "Питание" (Tab 2)
    await tester.tap(find.byIcon(Icons.restaurant_outlined));
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Завтрак'), findsOneWidget);

    // Navigate to "Прогресс" (Tab 3)
    await tester.tap(find.byIcon(Icons.show_chart_outlined));
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Силовые'), findsOneWidget);

    // Test PopScope back-navigation:
    // From Tab 3 (Progress), a back navigation must return to Tab 0 (Сегодня)
    final popHandled = await tester.binding.handlePopRoute();
    expect(popHandled, isTrue);
    await tester.pumpAndSettle();

    // Verify we returned to Tab 0 ("Сегодня")
    expect(find.text('Liftspire'), findsOneWidget);

    await tester.runAsync(() => db.close());
  });
}
