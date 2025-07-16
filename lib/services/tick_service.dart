import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Provides precise sub-beat and crotchet ticks using a drift-corrected Stopwatch + Timer.
class TickService {
  static final TickService _instance = TickService._internal();
  factory TickService() => _instance;
  TickService._internal();

  /// Stream of crotchet (full-beat) ticks.
  final StreamController<void> _crotchetController = StreamController.broadcast();
  Stream<void> get tickStream => _crotchetController.stream;

  /// Stream of sub-beat ticks (e.g. subdivided beats).
  final StreamController<void> _subController = StreamController.broadcast();
  Stream<void> get subTickStream => _subController.stream;

  /// Notifies listeners of the current BPM.
  final ValueNotifier<int> bpmNotifier = ValueNotifier(60);

  /// Notifies whether the service is running.
  final ValueNotifier<bool> isRunningNotifier = ValueNotifier(false);

  int? _pendingBpm;
  Timer? _timer;
  Stopwatch? _stopwatch;
  int _bpm = 60;
  Duration _interval = Duration(milliseconds: 1000);

  int _subTickCount = 0;
  int _ticksPerCrotchet = 1;

  /// Starts ticking at [bpm], subdividing each beat by [unitFraction].
  void start(int bpm, { double unitFraction = 1.0 }) {
    stop();
    _bpm = bpm;
    _ticksPerCrotchet = (1 / unitFraction).round();
    _interval = Duration(milliseconds: (60000 / bpm * unitFraction).round());
    _safeNotify(() => bpmNotifier.value = bpm);
    _safeNotify(() => isRunningNotifier.value = true);

    // 1) start the stopwatch
    _stopwatch = Stopwatch()..start();

    // 2) fire the very first tick immediately
    _emitTick();

    // 3) reset the timer base and counter so that
    //    the *next* tick comes in exactly one interval
    _stopwatch!.reset();      // zero out elapsed
    _subTickCount = 0;        // zero out count

    // 4) schedule the subsequent ticks normally
    _scheduleNextTick();
  }

  /// Stops any scheduled ticks and resets state.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _stopwatch?.stop();
    _stopwatch = null;
    _safeNotify(() => isRunningNotifier.value = false);
  }

  /// Requests a BPM change on the next tick.
  void updateBpm(int newBpm) {
    if (!isRunning || newBpm == _bpm || newBpm == _pendingBpm) return;
    _pendingBpm = newBpm;
  }

  void _scheduleNextTick() {
    if (_stopwatch == null) return;
    final target = _interval * (_subTickCount + 1);
    final delay = target - _stopwatch!.elapsed;
    _timer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () {
        _emitTick();

        // Handle pending BPM change exactly at a crotchet boundary.
        if (_pendingBpm != null) {
          _bpm = _pendingBpm!;
          _interval = Duration(milliseconds: (60000 / _bpm * (1 / _ticksPerCrotchet)).round());
          _pendingBpm = null;
          _safeNotify(() => bpmNotifier.value = _bpm);
          _stopwatch!..stop()..reset()..start();
          _subTickCount = 0;
          _crotchetController.add(null);
        }

        // Schedule the next tick.
        _scheduleNextTick();
      },
    );
  }

  void _emitTick() {

    // Fire sub-beat tick.
    _subController.add(null);
    _subTickCount++;

    // Fire crotchet tick every N sub-ticks.
    if (_subTickCount % _ticksPerCrotchet == 0) {
      _crotchetController.add(null);
    }
  }

  /// Returns the current BPM.
  int get bpm => _bpm;

  /// Returns true if the service is actively running.
  bool get isRunning => _stopwatch?.isRunning ?? false;

  void _safeNotify(VoidCallback cb) {
    SchedulerBinding.instance.addPostFrameCallback((_) => cb());
  }
}