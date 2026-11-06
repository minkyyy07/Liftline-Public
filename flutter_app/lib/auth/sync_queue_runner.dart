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
  }) : _authService = authService ?? AuthService.instance,
       _syncEngine = syncEngine ?? CloudWorkoutSync(),
       _appDb =
           appDb ?? (authService != null ? authService.db : AppDb.instance) {
    _init();
  }

  AuthService _authService = AuthService.instance;
  CloudWorkoutSync _syncEngine = CloudWorkoutSync();
  AppDb _appDb = AppDb.instance;

  Timer? _debounceTimer;
  Timer? _backoffTimer;
  bool _isProcessing = false;
  bool _hasQueuedRun = false;
  int _runnerGeneration = 0;
  int _consecutiveFailures = 0;
  static const int _maxBackoffSeconds = 60;

  StreamSubscription? _eventSubscription;
  void Function()? _dbSwitchListener;
  void Function()? _authStateListener;

  void _init() {
    _dbSwitchListener = () {
      cancelCurrentTasks();
      _consecutiveFailures = 0;
    };
    _appDb.addDatabaseSwitchListener(_dbSwitchListener!);
    _authStateListener = _handleAuthStateChanged;
    _authService.addListener(_authStateListener!);

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
    if (_authStateListener != null) {
      _authService.removeListener(_authStateListener!);
    }
    _eventSubscription?.cancel();
  }

  bool get _canSync {
    final userId = _authService.user?.id;
    return _authService.isAuthenticated &&
        !_authService.apiClient.isSessionTransitionPending &&
        userId != null &&
        userId == _authService.apiClient.sessionAccountId &&
        userId == _appDb.currentUserId &&
        _appDb.isOpen;
  }

  void _handleAuthStateChanged() {
    if (!_canSync) {
      cancelCurrentTasks();
      return;
    }
    scheduleSync(immediate: true);
  }

  /// Cancels timers and invalidates the current run's completion handlers.
  void cancelCurrentTasks() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _backoffTimer?.cancel();
    _backoffTimer = null;
    _hasQueuedRun = false;
    _runnerGeneration++;
  }

  /// Schedules sync with debounce (default 250ms), or immediate for manual retry / app resume.
  void scheduleSync({bool immediate = false}) {
    if (!_canSync) return;

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
    if (!_canSync) return;

    if (_isProcessing) {
      _hasQueuedRun = true;
      return;
    }

    _isProcessing = true;
    final targetUserId = _appDb.currentUserId;
    final targetEpoch = _appDb.accountEpoch;
    final targetSessionGeneration = _authService.apiClient.sessionGeneration;
    final runnerGeneration = _runnerGeneration;

    try {
      await _syncEngine.processSyncQueue(_appDb.db);

      if (runnerGeneration != _runnerGeneration ||
          !_canSync ||
          !_appDb.isCurrentAccount(targetUserId, targetEpoch) ||
          !_authService.apiClient.isCurrentSession(
            targetUserId,
            targetSessionGeneration,
          )) {
        return;
      }

      _consecutiveFailures = 0;
    } catch (e) {
      if (runnerGeneration != _runnerGeneration ||
          !_canSync ||
          !_appDb.isCurrentAccount(targetUserId, targetEpoch) ||
          !_authService.apiClient.isCurrentSession(
            targetUserId,
            targetSessionGeneration,
          )) {
        return;
      }

      _consecutiveFailures++;
      final backoffSeconds = (_consecutiveFailures * 2).clamp(
        2,
        _maxBackoffSeconds,
      );
      _backoffTimer?.cancel();
      _backoffTimer = Timer(Duration(seconds: backoffSeconds), () {
        if (_appDb.isCurrentAccount(targetUserId, targetEpoch) &&
            _authService.isAuthenticated) {
          scheduleSync(immediate: true);
        }
      });
    } finally {
      _isProcessing = false;
      if (_hasQueuedRun && _canSync) {
        _hasQueuedRun = false;
        scheduleSync(immediate: true);
      } else if (!_canSync) {
        _hasQueuedRun = false;
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
