import 'dart:async';

enum AppDataCategory {
  workout,
  nutrition,
  weight,
}

/// Lightweight reactive event bus for cross-tab synchronization.
/// When data changes on one tab (e.g. food added, weight logged, workout finished),
/// listeners (such as the TodayScreen summary) reload local database state without
/// triggering extraneous network requests or rebuild loops.
class AppDataEvents {
  static final AppDataEvents instance = AppDataEvents._();
  AppDataEvents._();

  final StreamController<AppDataCategory> _controller =
      StreamController<AppDataCategory>.broadcast();

  Stream<AppDataCategory> get stream => _controller.stream;

  void notifyWorkoutChanged() {
    if (!_controller.isClosed) {
      _controller.add(AppDataCategory.workout);
    }
  }

  void notifyNutritionChanged() {
    if (!_controller.isClosed) {
      _controller.add(AppDataCategory.nutrition);
    }
  }

  void notifyWeightChanged() {
    if (!_controller.isClosed) {
      _controller.add(AppDataCategory.weight);
    }
  }
}
