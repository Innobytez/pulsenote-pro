import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Provides precise sub-beat and crotchet ticks using a drift-corrected Stopwatch + Timer.
class TickService {
  static final TickService _instance = TickService._internal();
  factory TickService() => _instance;
  TickService._internal();

  final StreamController<void> _crotchetController = StreamController<void>.broadcast();
  Stream<void> get tickStream => _crotchetController.stream;

  final StreamController<void> _subController = StreamController<void>.broadcast();
  Stream<void> get subTickStream => _subController.stream;

  final ValueNotifier<int> bpmNotifier = ValueNotifier<int>(60);
  final ValueNotifier<bool> isRunningNotifier = ValueNotifier<bool>(false);

  int? _pendingBpm;
  Timer? _timer;
  Stopwatch? _stopwatch;
  int _bpm = 60;
  Duration _interval = const Duration(milliseconds: 1000);

  int _subTickCount = 0;
  int _ticksPerCrotchet = 1;

  /// Starts at [bpm], subdividing by [unitFraction].
  void start(int bpm, { double unitFraction = 1.0 }) {
    stop();
    _bpm = bpm;
    _ticksPerCrotchet = (1 / unitFraction).round();
    _interval = Duration(milliseconds: (60000 / bpm * unitFraction).round());

    _safeNotify(() => bpmNotifier.value = bpm);
    _safeNotify(() => isRunningNotifier.value = true);

    _stopwatch = Stopwatch()..start();
    _emitTick();            // immediate
    _stopwatch!..reset();   // zero elapsed
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

  /// Defer a BPM change until the next crotchet-boundary.
  void updateBpm(int newBpm) {
    if (!isRunning || newBpm == _bpm || newBpm == _pendingBpm) return;
    _pendingBpm = newBpm;
  }

  void _scheduleNextTick() {
    if (_stopwatch == null) return;
    final target = _interval * (_subTickCount + 1);
    final delay  = target - _stopwatch!.elapsed;

    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _emitTick();

      // apply pending BPM at the next crotchet
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