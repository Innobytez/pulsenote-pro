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

  Timer? _timer;
  Stopwatch? _stopwatch;
  int _bpm = 60;
  Duration _interval = Duration(milliseconds: 1000);

  void start(int bpm) {
    stop();
    _bpm = bpm;
    _safeNotify(() => bpmNotifier.value = bpm);
    _safeNotify(() => isRunningNotifier.value = true);

    _interval = Duration(milliseconds: (60000 / bpm).round());
    _stopwatch = Stopwatch()..start();

    // Delay the first tick until after isRunning == true has propagated
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _tickController.add(null);
    });

    _scheduleNextTick();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _stopwatch?.stop();
    _stopwatch = null;
    _safeNotify(() => isRunningNotifier.value = false);
  }

  void _scheduleNextTick() {
    final now = _stopwatch!.elapsed;
    final msUntilNext = _interval.inMilliseconds - (now.inMilliseconds % _interval.inMilliseconds);
    _timer = Timer(Duration(milliseconds: msUntilNext), () {
      _tickController.add(null);
      _scheduleNextTick();
    });
  }

  int get bpm => _bpm;
  bool get isRunning => _timer != null;

  /// Ensure notifier updates don’t break build/dispose cycles
  void _safeNotify(VoidCallback callback) {
    SchedulerBinding.instance.addPostFrameCallback((_) => callback());
  }
}