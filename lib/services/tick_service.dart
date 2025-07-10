import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class TickService {
  static final TickService _instance = TickService._internal();
  factory TickService() => _instance;
  TickService._internal();

  final StreamController<void> _tickController = StreamController.broadcast();
  Stream<void> get tickStream => _tickController.stream;

  final ValueNotifier<int> bpmNotifier = ValueNotifier(60);
  final ValueNotifier<bool> isRunningNotifier = ValueNotifier(false);

  int? _pendingBpm;
  Timer? _timer;
  Stopwatch? _stopwatch;
  int _bpm = 60;
  Duration _interval = Duration(milliseconds: 1000);

  DateTime? _lastTickTime;
  int _tickCount = 0;

  void start(int bpm) {
    stop();
    _bpm = bpm;
    _interval = Duration(milliseconds: (60000 / bpm).round());
    _safeNotify(() => bpmNotifier.value = bpm);
    _safeNotify(() => isRunningNotifier.value = true);

    _stopwatch = Stopwatch()..start();
    _tickCount = 0;

    // Emit tick 1 immediately, not post-frame
    final now = DateTime.now();
    _lastTickTime = now;
    debugPrint('[TICK] First tick at ${now.toIso8601String()}');
    _tickController.add(null);

    _scheduleNextTick(); // align tick 2+
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _stopwatch?.stop();
    _stopwatch = null;
    _safeNotify(() => isRunningNotifier.value = false);
  }

  void updateBpm(int newBpm) {
    if (!isRunning || newBpm == _bpm || newBpm == _pendingBpm) return;
    _pendingBpm = newBpm;
  }

  void _scheduleNextTick() {
    if (_stopwatch == null) return;

    final targetElapsed = _interval * (_tickCount + 1);
    final delay = targetElapsed - _stopwatch!.elapsed;

    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _emitTick();

      if (_pendingBpm != null) {
        _bpm = _pendingBpm!;
        _interval = Duration(milliseconds: (60000 / _bpm).round());
        _safeNotify(() => bpmNotifier.value = _bpm);
        _pendingBpm = null;

        _stopwatch?.stop();
        _stopwatch = Stopwatch()..start();
        _tickCount = 0;

        final now = DateTime.now();
        _lastTickTime = now;
        debugPrint('[TICK] First tick at ${now.toIso8601String()}');
        _tickController.add(null);

        _scheduleNextTick(); // restart cleanly
        return;
      }

      _scheduleNextTick();
    });
  }

  void _emitTick() {
    final now = DateTime.now();
    if (_lastTickTime != null) {
      final delta = now.difference(_lastTickTime!).inMilliseconds;
      final expected = _interval.inMilliseconds;
      final deviation = delta - expected;
      debugPrint('[TICK] Δ = ${delta} ms | expected = $expected ms | deviation = ${deviation >= 0 ? '+' : ''}$deviation ms (tick $_tickCount)', wrapWidth: 1024);
    } else {
      debugPrint('[TICK] First tick at ${now.toIso8601String()}', wrapWidth: 1024);
    }

    _lastTickTime = now;
    _tickCount++;

    _tickController.add(null);
  }

  int get bpm => _bpm;
  bool get isRunning => _stopwatch?.isRunning ?? false;

  void _safeNotify(VoidCallback callback) {
    SchedulerBinding.instance.addPostFrameCallback((_) => callback());
  }
}