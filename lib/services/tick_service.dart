// File: lib/services/tick_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

typedef AsyncVoid = Future<void> Function();

/// Provides precise sub-beat and crotchet ticks using a drift-corrected
/// Stopwatch + Timer. Also exposes a background "resumer" hook so the
/// SystemMediaHandler (Control Center / notifications) can restart the
/// *currently active* mode without needing to know which screen owns playback.
class TickService {
  static final TickService _instance = TickService._internal();
  factory TickService() => _instance;
  TickService._internal();

  // Public streams: crotchet (tickStream) and sub-tick (subTickStream)
  final _crotchetController = StreamController<void>.broadcast();
  Stream<void> get tickStream => _crotchetController.stream;

  final _subController = StreamController<void>.broadcast();
  Stream<void> get subTickStream => _subController.stream;

  // UI notifiers used by your overlays/dots
  final ValueNotifier<int> bpmNotifier = ValueNotifier<int>(60);
  final ValueNotifier<bool> isRunningNotifier = ValueNotifier<bool>(false);

  // Internal timing
  int? _pendingBpm;
  Timer? _timer;
  Stopwatch? _stopwatch;
  int _bpm = 60;
  Duration _interval = const Duration(milliseconds: 1000);
  int _subTickCount = 0;
  int _ticksPerCrotchet = 1;

  // Background resume hook
  AsyncVoid? _backgroundResumer;
  void setBackgroundResumer(AsyncVoid? cb) => _backgroundResumer = cb;
  Future<bool> resumeFromBackground() async {
    final cb = _backgroundResumer;
    if (cb == null) return false;
    await cb();
    return true;
    // Note: the owning screen should set this when it starts playback
    // and clear it when it stops (so play from Control Center is predictable).
  }

  /// Starts ticking at [bpm]. [unitFraction] = 1.0 (quarter), 0.5 (eighth), etc.
  void start(int bpm, {double unitFraction = 1.0}) {
    stop();
    _bpm = bpm;
    _ticksPerCrotchet = (1 / unitFraction).round();
    _interval = Duration(milliseconds: (60000 / bpm * unitFraction).round());

    _safeNotify(() => bpmNotifier.value = bpm);
    _safeNotify(() => isRunningNotifier.value = true);

    _stopwatch = Stopwatch()..start();
    _emitTick();          // immediate first tick
    _stopwatch!..reset(); // zero elapsed
    _subTickCount = 0;
    _scheduleNextTick();
  }

  /// Cancels everything.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _stopwatch?.stop();
    _stopwatch = null;
    _safeNotify(() => isRunningNotifier.value = false);
  }

  /// Defer a BPM change until the next crotchet boundary for smoothness.
  void updateBpm(int newBpm) {
    if (!isRunning || newBpm == _bpm || newBpm == _pendingBpm) return;
    _pendingBpm = newBpm;
  }

  void _scheduleNextTick() {
    if (_stopwatch == null) return;
    final target = _interval * (_subTickCount + 1);
    final delay = target - _stopwatch!.elapsed;

    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _emitTick();

      // Apply pending BPM exactly on crotchet boundary
      if (_pendingBpm != null) {
        _bpm = _pendingBpm!;
        _interval = Duration(
          milliseconds: (60000 / _bpm * (1 / _ticksPerCrotchet)).round(),
        );
        _pendingBpm = null;
        _safeNotify(() => bpmNotifier.value = _bpm);
        _stopwatch!..stop()..reset()..start();
        _subTickCount = 0;
      }

      _scheduleNextTick();
    });
  }

  void _emitTick() {
    _subController.add(null);
    _subTickCount++;
    if (_subTickCount % _ticksPerCrotchet == 0) {
      _crotchetController.add(null);
    }
  }

  int get bpm => _bpm;
  bool get isRunning => _stopwatch?.isRunning ?? false;

  void _safeNotify(VoidCallback cb) {
    SchedulerBinding.instance.addPostFrameCallback((_) => cb());
  }
}