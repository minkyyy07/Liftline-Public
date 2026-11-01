import 'dart:async';
import 'package:flutter/material.dart';
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
    _midnightCheck =
        Timer.periodic(const Duration(minutes: 1), (_) => _syncToday());
  }

  @override
  void dispose() {
    _midnightCheck?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncToday();
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
    final screens = [
      TodayScreen(
        selectedDate: _selectedDate,
        isFollowingToday: _followToday,
        onDateChanged: _selectDate,
        onGoToTab: (i) => setState(() => _currentIndex = i),
      ),
      WorkoutsScreen(selectedDate: _selectedDate),
      NutritionScreen(selectedDate: _selectedDate, onDateChanged: _selectDate),
      ProgressScreen(selectedDate: _selectedDate),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Сегодня',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: 'Тренировки',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_outlined),
            selectedIcon: Icon(Icons.restaurant),
            label: 'Питание',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart),
            label: 'Прогресс',
          ),
        ],
      ),
    );
  }
}
