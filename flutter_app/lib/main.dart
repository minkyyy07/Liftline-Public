import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'db.dart';
import 'rest_timer.dart';
export 'db.dart' show AppDb;
import 'app_shell.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru');
  Intl.defaultLocale = 'ru';
  await AppDb.instance.init();
  await RestTimerController.instance.load();
  runApp(const LiftlineApp());
}

class LiftlineApp extends StatelessWidget {
  const LiftlineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Liftline',
      debugShowCheckedModeBanner: false,
      theme: buildLiftlineTheme(),
      home: const MainNavigationScreen(),
    );
  }
}

// Navigation and Today screens live in app_shell.dart / today_screen.dart
