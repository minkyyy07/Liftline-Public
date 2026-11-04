import 'dart:async';
import '../data_events.dart';
import '../db.dart';
import 'auth_service.dart';
import 'cloud_workout_sync.dart';

/// Single account-bound sync queue runner that handles debounce, single-flight
/// background processing, automatic retries with bounded exponential backoff,
/// and immediate abort on session/account switches.
class SyncQueueRunner {
  static final SyncQueueRunner instance = SyncQueueRunner._();
  SyncQueueRunner._() {
    _init();
  }

  /// Factory for isolated testing
  SyncQueueRunner.isolated({
    AuthService? authService,
    CloudWorkoutSync? syncEngine,
    AppDb? appDb,
  })  : _authService = authService ?? AuthService.instance,
        _syncEngine = syncEngine ?? CloudWorkoutSync(),
        _appDb = appDb ?? (authService != null ? authService.db : AppDb.instance) {
    _init();
  }

  AuthService _authService = AuthService.instance;
  CloudWorkoutSync _syncEngine = CloudWorkoutSync();
  AppDb _appDb = AppDb.instance;

  Timer? _debounceTimer;
  Timer? _backoffTimer;
  bool _isProcessing = false;
  bool _hasQueuedRun = false;
  int _consecutiveFailures = 0;
  static const int _maxBackoffSeconds = 60;

  StreamSubscription? _eventSubscription;
  void Function()? _dbSwitchListener;

  void _init() {
    _dbSwitchListener = () {
      cancelCurrentTasks();
      _consecutiveFailures = 0;
    };
    _appDb.addDatabaseSwitchListener(_dbSwitchListener!);

    _eventSubscription = AppDataEvents.instance.stream.listen((cat) {
      if (cat == AppDataCategory.workout) {
        scheduleSync(immediate: false);
      }
    });
  }

  void dispose() {
    cancelCurrentTasks();
    if (_dbSwitchListener != null) {
      _appDb.removeDatabaseSwitchListener(_dbSwitchListener!);
    }
    _eventSubscription?.cancel();
  }

  /// Cancels in-flight timers and resets runner state (e.g. on account switch or logout).
  void cancelCurrentTasks() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _backoffTimer?.cancel();
    _backoffTimer = null;
    _hasQueuedRun = false;
    _isProcessing = false;
  }

  /// Schedules sync with debounce (default 250ms), or immediate for manual retry / app resume.
  void scheduleSync({bool immediate = false}) {
    if (!_authService.isAuthenticated || !_appDb.isOpen) return;

    if (immediate) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _triggerSync();
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      _triggerSync();
    });
  }

  Future<void> _triggerSync() async {
    if (!_authService.isAuthenticated || !_appDb.isOpen) return;

    if (_isProcessing) {
      _hasQueuedRun = true;
      return;
    }

    _isProcessing = true;
    final targetUserId = _appDb.currentUserId;
    final targetEpoch = _appDb.accountEpoch;

    try {
      await _syncEngine.processSyncQueue(_appDb.db);

      // Check if session switched during sync
      if (!_appDb.isCurrentAccount(targetUserId, targetEpoch)) {
        return;
      }

      _consecutiveFailures = 0;
    } catch (e) {
      if (!_appDb.isCurrentAccount(targetUserId, targetEpoch)) {
        return;
      }

      _consecutiveFailures++;
      final backoffSeconds = (_consecutiveFailures * 2).clamp(2, _maxBackoffSeconds);
      _backoffTimer?.cancel();
      _backoffTimer = Timer(Duration(seconds: backoffSeconds), () {
        if (_appDb.isCurrentAccount(targetUserId, targetEpoch) && _authService.isAuthenticated) {
          scheduleSync(immediate: true);
        }
      });
    } finally {
      _isProcessing = false;
      if (_hasQueuedRun) {
        _hasQueuedRun = false;
        if (_appDb.isCurrentAccount(targetUserId, targetEpoch)) {
          scheduleSync(immediate: true);
        }
      }
    }
  }

  /// Triggered on AppLifecycleState.resumed or network restored
  void onConnectivityOrResume() {
    _consecutiveFailures = 0;
    _backoffTimer?.cancel();
    scheduleSync(immediate: true);
  }
}
