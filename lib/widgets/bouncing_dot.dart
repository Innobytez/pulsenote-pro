import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/tick_service.dart';

/// ─────────────────────────────────────────────────────────────────
/// Inlined PolyrhythmVizBus (no extra file needed)
/// ─────────────────────────────────────────────────────────────────
class PolyrhythmVizBus {
  PolyrhythmVizBus._();
  static final PolyrhythmVizBus instance = PolyrhythmVizBus._();

  /// When true, BouncingDot subscribes to polyrhythm streams instead of TickService.
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  /// Per-side mute flags so dots can dim when a side is muted.
  final ValueNotifier<bool> leftMuted = ValueNotifier<bool>(false);
  final ValueNotifier<bool> rightMuted = ValueNotifier<bool>(false);

  final _leftCtrl = StreamController<void>.broadcast();
  final _rightCtrl = StreamController<void>.broadcast();

  Stream<void> get leftStream => _leftCtrl.stream;
  Stream<void> get rightStream => _rightCtrl.stream;

  void emitLeft()  { if (!_leftCtrl.isClosed)  _leftCtrl.add(null); }
  void emitRight() { if (!_rightCtrl.isClosed) _rightCtrl.add(null); }

  void setEnabled(bool v) => enabled.value = v;

  void setMuted({bool? left, bool? right}) {
    if (left != null)  leftMuted.value  = left;
    if (right != null) rightMuted.value = right;
  }

  void dispose() {
    _leftCtrl.close();
    _rightCtrl.close();
  }
}

enum DotSide { left, right }

class BouncingDot extends StatefulWidget {
  final int bpm;
  final bool isRunning;
  final DotSide side;

  const BouncingDot({
    super.key,
    required this.bpm,
    required this.isRunning,
    required this.side,
  });

  @override
  _BouncingDotState createState() => _BouncingDotState();
}

// Keep some state per side so dots don’t jump when screens change
class _DotState {
  double topOffset;
  bool pulsing;
  _DotState({required this.topOffset, required this.pulsing});
}

class _DotStateStore {
  static final _DotStateStore _i = _DotStateStore._();
  factory _DotStateStore() => _i;
  _DotStateStore._();

  final Map<DotSide, _DotState> _map = {
    DotSide.left:  _DotState(topOffset: 0.45, pulsing: false),
    DotSide.right: _DotState(topOffset: 0.77, pulsing: false),
  };

  _DotState get(DotSide s) => _map[s]!;
  void update(DotSide s, _DotState v) => _map[s] = v;
}

class _BouncingDotState extends State<BouncingDot> {
  late _DotState _state;

  StreamSubscription<void>? _tickSub;
  StreamSubscription<void>? _busLeftSub;
  StreamSubscription<void>? _busRightSub;
  late final PolyrhythmVizBus _bus;

  // Listen to mute flags for color dimming when polyrhythm is active
  ValueNotifier<bool>? _mutedNotifier;

  // Track actual interval between hits so left dot can speed=Q/P automatically.
  DateTime? _lastHitAt;
  Duration? _lastInterval;

  // Single listener ref so we don't stack listeners on rebinds
  VoidCallback? _enabledListener;

  Duration get _fallbackBounceDuration {
    final tickMs = (60000 / widget.bpm).round();
    return Duration(milliseconds: (tickMs * 0.9).round());
  }

  Duration get _pulseDuration => const Duration(milliseconds: 100);

  Duration get _bounceDuration {
    // Use measured interval (0.9x) when we have it; otherwise fall back to BPM.
    final d = _lastInterval;
    if (d != null) {
      final ms = (d.inMilliseconds * 0.9).round();
      // Clamp to avoid ultra-short animations
      return Duration(milliseconds: ms.clamp(60, 2000));
    }
    return _fallbackBounceDuration;
  }

  @override
  void initState() {
    super.initState();
    _state = _DotStateStore().get(widget.side);
    _bus = PolyrhythmVizBus.instance;
    _mutedNotifier = (widget.side == DotSide.left) ? _bus.leftMuted : _bus.rightMuted;

    _bindStreams(); // initial bind

    // Rebind if polyrhythm mode toggles on/off — ensure only one listener
    _enabledListener = () {
      if (!mounted) return;
      _bindStreams();
    };
    _bus.enabled.addListener(_enabledListener!);
  }

  void _bindStreams() {
    _tickSub?.cancel();
    _busLeftSub?.cancel();
    _busRightSub?.cancel();

    _lastHitAt = null;      // reset measurement when source changes
    _lastInterval = null;

    if (_bus.enabled.value) {
      if (widget.side == DotSide.left) {
        _busLeftSub = _bus.leftStream.listen((_) => _onHit());
      } else {
        _busRightSub = _bus.rightStream.listen((_) => _onHit());
      }
    } else {
      _tickSub = TickService().tickStream.listen((_) => _onHit());
    }
  }

  void _onHit() {
    if (!mounted) return;

    final now = DateTime.now();
    if (_lastHitAt != null) {
      _lastInterval = now.difference(_lastHitAt!);
    }
    _lastHitAt = now;

    setState(() {
      _state.topOffset = (_state.topOffset == 0.45) ? 0.77 : 0.45;
      _state.pulsing = true;
    });
    _DotStateStore().update(widget.side, _state);

    Future.delayed(_pulseDuration, () {
      if (!mounted) return;
      setState(() => _state.pulsing = false);
      _DotStateStore().update(widget.side, _state);
    });
  }

  @override
  void didUpdateWidget(covariant BouncingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isRunning && oldWidget.isRunning) {
      final distanceToTop = (_state.topOffset - 0.45).abs();
      final distanceToBottom = (_state.topOffset - 0.77).abs();
      setState(() {
        _state.topOffset = (distanceToTop < distanceToBottom) ? 0.45 : 0.77;
        _state.pulsing = false;
      });
      _DotStateStore().update(widget.side, _state);
    }
  }

  @override
  void dispose() {
    _tickSub?.cancel();
    _busLeftSub?.cancel();
    _busRightSub?.cancel();
    if (_enabledListener != null) {
      _bus.enabled.removeListener(_enabledListener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double size = _state.pulsing ? 22 : 16;
    final screenH = MediaQuery.of(context).size.height;
    final y = (_state.topOffset * screenH) - (size / 2);

    final activeColor = Colors.tealAccent;
    final pulseGlow = _state.pulsing ? activeColor.withOpacity(0.9) : activeColor;

    final dimmed = _bus.enabled.value && (_mutedNotifier?.value ?? false);
    final color = dimmed ? Colors.white38 : pulseGlow;

    return SizedBox(
      width: 40,
      height: screenH,
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: _bounceDuration,
            curve: Curves.linear,
            top: y,
            left: (40 - size) / 2,
            child: AnimatedContainer(
              duration: _pulseDuration,
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: _state.pulsing && !dimmed
                    ? [BoxShadow(color: color, blurRadius: 12, spreadRadius: 2)]
                    : const [],
              ),
            ),
          ),
        ],
      ),
    );
  }
}