import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:liftline_app/app_shell.dart';
import 'package:liftline_app/db.dart';
import 'package:liftline_app/nutrition_calc.dart';
import 'package:liftline_app/nutrition_repo.dart';
import 'package:liftline_app/progress_repo.dart';
import 'package:liftline_app/repo.dart';
import 'package:liftline_app/theme.dart';
import 'package:liftline_app/week_utils.dart';
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

  Future<void> captureScreen({
    required WidgetTester tester,
    required GlobalKey key,
    required String filePath,
  }) async {
    final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(pngBytes);
  }

  testWidgets('Capture real screenshots of empty, filled, and active states', (tester) async {
    const screenshotDir = '/Users/apple/.gemini/antigravity-cli/brain/25f7e2dd-f533-4056-b31b-abb50b12312c/screenshots';
    final now = DateTime(2026, 11, 4);

    // ==========================================
    // 1. EMPTY STATE
    // ==========================================
    final emptyRepaintKey = GlobalKey();
    tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() => tester.view.reset());

    late Database dbEmpty;
    await tester.runAsync(() async {
      dbEmpty = await openLiftlineDb(inMemoryDatabasePath, factory: databaseFactoryFfi);
      AppDb.instance.useDatabase(dbEmpty);
    });

    await tester.pumpWidget(
      RepaintBoundary(
        key: emptyRepaintKey,
        child: MaterialApp(
          title: 'Liftspire',
          debugShowCheckedModeBanner: false,
          theme: buildLiftlineTheme(),
          home: const MainNavigationScreen(),
        ),
      ),
    );

    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await captureScreen(
        tester: tester,
        key: emptyRepaintKey,
        filePath: '$screenshotDir/today_empty_state.png',
      );
    });

    await tester.runAsync(() => dbEmpty.close());

    // ==========================================
    // 2. FILLED STATE (Planned workout, goals, weight)
    // ==========================================
    final filledRepaintKey = GlobalKey();
    late Database dbFilled;
    await tester.runAsync(() async {
      dbFilled = await openLiftlineDb(inMemoryDatabasePath, factory: databaseFactoryFfi);
      AppDb.instance.useDatabase(dbFilled);

      final wrepo = WorkoutRepo(dbFilled);
      final wid = await wrepo.createWorkout(
        title: 'Тяжёлый жим и дельты (Push Day)',
        date: now,
        start: false,
      );
      final eid = await wrepo.addExercise(wid, 'Жим штанги лёжа');
      final sid = await wrepo.addSet(eid);
      await wrepo.updateSet(sid, weight: 100.0, reps: 8, rir: 2);

      final nrepo = NutritionRepo(dbFilled);
      await nrepo.setGoals(now, const NutritionGoals(2400, 160, 70, 260));
      await nrepo.savePortion(
        date: dateKey(now),
        meal: 'breakfast',
        name: 'Овсянка с протеином и ягодами',
        total: const Nutrients(480, 36, 10, 58),
      );
      await nrepo.savePortion(
        date: dateKey(now),
        meal: 'lunch',
        name: 'Куриное филе с рисом и овощами',
        total: const Nutrients(620, 52, 14, 72),
      );

      final prepo = ProgressRepo(dbFilled);
      await prepo.saveWeight(now, 81.2);
    });

    await tester.pumpWidget(
      RepaintBoundary(
        key: filledRepaintKey,
        child: MaterialApp(
          title: 'Liftspire',
          debugShowCheckedModeBanner: false,
          theme: buildLiftlineTheme(),
          home: const MainNavigationScreen(),
        ),
      ),
    );

    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await captureScreen(
        tester: tester,
        key: filledRepaintKey,
        filePath: '$screenshotDir/today_filled_state.png',
      );
    });

    await tester.runAsync(() => dbFilled.close());

    // ==========================================
    // 3. ACTIVE WORKOUT IN PROGRESS STATE
    // ==========================================
    final activeRepaintKey = GlobalKey();
    late Database dbActive;
    await tester.runAsync(() async {
      dbActive = await openLiftlineDb(inMemoryDatabasePath, factory: databaseFactoryFfi);
      AppDb.instance.useDatabase(dbActive);

      final wrepo = WorkoutRepo(dbActive);
      await wrepo.createWorkout(
        title: 'Интенсивный тренинг ног и кора',
        date: now,
        start: true,
      );
      final nrepo = NutritionRepo(dbActive);
      await nrepo.setGoals(now, const NutritionGoals(2600, 175, 75, 290));
      await nrepo.savePortion(
        date: dateKey(now),
        meal: 'breakfast',
        name: 'Омлет из 4 яиц с цельнозерновым хлебом',
        total: const Nutrients(520, 42, 22, 38),
      );
      final prepo = ProgressRepo(dbActive);
      await prepo.saveWeight(now, 80.8);
    });

    await tester.pumpWidget(
      RepaintBoundary(
        key: activeRepaintKey,
        child: MaterialApp(
          title: 'Liftspire',
          debugShowCheckedModeBanner: false,
          theme: buildLiftlineTheme(),
          home: const MainNavigationScreen(),
        ),
      ),
    );

    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await captureScreen(
        tester: tester,
        key: activeRepaintKey,
        filePath: '$screenshotDir/today_active_state.png',
      );
    });

    await tester.runAsync(() => dbActive.close());
  });
}
