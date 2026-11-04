import 'dart:async';
import 'package:flutter/material.dart';
import 'auth/sync_queue_runner.dart';
import 'db.dart';
import 'workouts_ui.dart';
import 'nutrition_ui.dart';
import 'progress_ui.dart';
import 'today_screen.dart';
import 'week_utils.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  DateTime _selectedDate = dateOnly(DateTime.now());

  /// true: the selected day follows the current calendar day (updates after
  /// midnight). false: the user explicitly picked a date (kept as is).
  bool _followToday = true;
  Timer? _midnightCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppDb.instance.addDatabaseSwitchListener(_onAccountSwitched);
    _midnightCheck = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _syncToday(),
    );
  }

  void _onAccountSwitched() {
    if (mounted) {
      setState(() {
        _currentIndex = 0;
        _selectedDate = dateOnly(DateTime.now());
        _followToday = true;
      });
    }
  }

  @override
  void dispose() {
    AppDb.instance.removeDatabaseSwitchListener(_onAccountSwitched);
    _midnightCheck?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncToday();
      SyncQueueRunner.instance.onConnectivityOrResume();
    }
  }

  void _syncToday() {
    if (!_followToday) return;
    final today = dateOnly(DateTime.now());
    if (!isSameDay(today, _selectedDate) && mounted) {
      setState(() => _selectedDate = today);
    }
  }

  void _selectDate(DateTime d) {
    final day = dateOnly(d);
    setState(() {
      _selectedDate = day;
      _followToday = isSameDay(day, DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    final epoch = AppDb.instance.accountEpoch;
    final userId = AppDb.instance.currentUserId ?? 'guest';
    final screens = [
      TodayScreen(
        key: ValueKey('today_${epoch}_$userId'),
        selectedDate: _selectedDate,
        isFollowingToday: _followToday,
        onDateChanged: _selectDate,
        onGoToTab: (i) => setState(() => _currentIndex = i),
      ),
      WorkoutsScreen(
        key: ValueKey('workouts_${epoch}_$userId'),
        selectedDate: _selectedDate,
      ),
      NutritionScreen(
        key: ValueKey('nutrition_${epoch}_$userId'),
        selectedDate: _selectedDate,
        onDateChanged: _selectDate,
      ),
      ProgressScreen(
        key: ValueKey('progress_${epoch}_$userId'),
        selectedDate: _selectedDate,
        onGoToTab: (i) => setState(() => _currentIndex = i),
      ),
    ];

    final textScaler = MediaQuery.textScalerOf(context);
    final navHeight = (textScaler.scale(72.0)).clamp(72.0, 96.0);

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
        }
      },
      child: Scaffold(
        body: IndexedStack(index: _currentIndex, children: screens),
        bottomNavigationBar: NavigationBar(
          height: navHeight,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          selectedIndex: _currentIndex,
          onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.today_outlined),
              selectedIcon: Icon(Icons.today),
              label: 'Сегодня',
              tooltip: 'Сегодня',
            ),
            NavigationDestination(
              icon: Icon(Icons.fitness_center_outlined),
              selectedIcon: Icon(Icons.fitness_center),
              label: 'Тренировки',
              tooltip: 'Тренировки',
            ),
            NavigationDestination(
              icon: Icon(Icons.restaurant_outlined),
              selectedIcon: Icon(Icons.restaurant),
              label: 'Питание',
              tooltip: 'Питание',
            ),
            NavigationDestination(
              icon: Icon(Icons.show_chart_outlined),
              selectedIcon: Icon(Icons.show_chart),
              label: 'Прогресс',
              tooltip: 'Прогресс',
            ),
          ],
        ),
      ),
    );
  }
}
