import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'calc.dart';

/// Rest timer persisted as an UTC end time; survives backgrounding/restart.
/// No notifications or background service (out of scope).
class RestTimerController extends ChangeNotifier {
  static final RestTimerController instance = RestTimerController._();
  RestTimerController._();

  static const _key = 'rest_end_utc_ms';
  DateTime? _end;
  Timer? _tick;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final ms = p.getInt(_key);
    _end = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    _schedule();
    notifyListeners();
  }

  Duration get remaining =>
      RestTimer(_end).remaining(DateTime.now().toUtc());
  bool get isRunning => remaining > Duration.zero;

  Future<void> start(int seconds) async {
    if (seconds <= 0) return;
    await _set(DateTime.now().toUtc().add(Duration(seconds: seconds)));
  }

  Future<void> adjust(int deltaSeconds) async {
    final e = _end;
    if (e == null || !isRunning) return;
    final n = e.add(Duration(seconds: deltaSeconds));
    if (n.isBefore(DateTime.now().toUtc())) {
      await stop();
    } else {
      await _set(n);
    }
  }

  Future<void> stop() => _set(null);

  Future<void> _set(DateTime? end) async {
    _end = end;
    final p = await SharedPreferences.getInstance();
    if (end == null) {
      await p.remove(_key);
    } else {
      await p.setInt(_key, end.millisecondsSinceEpoch);
    }
    _schedule();
    notifyListeners();
  }

  void _schedule() {
    _tick?.cancel();
    if (_end == null) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isRunning) {
        _tick?.cancel();
      }
      notifyListeners();
    });
  }
}
