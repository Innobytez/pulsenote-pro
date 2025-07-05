import 'dart:async';
import 'package:flutter/material.dart';
import '../services/tick_service.dart';

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

// Simple shared state per side (not persisted to disk)
class _DotState {
  int tickCount;
  double topOffset;
  bool pulsing;

  _DotState({
    required this.tickCount,
    required this.topOffset,
    required this.pulsing,
  });
}

class _DotStateStore {
  static final _DotStateStore _instance = _DotStateStore._internal();
  factory _DotStateStore() => _instance;
  _DotStateStore._internal();

  final Map<DotSide, _DotState> _states = {
    DotSide.left: _DotState(tickCount: 0, topOffset: 0.15, pulsing: false),
    DotSide.right: _DotState(tickCount: 0, topOffset: 0.85, pulsing: false),
  };

  _DotState get(DotSide side) => _states[side]!;
  void update(DotSide side, _DotState state) => _states[side] = state;
}

class _BouncingDotState extends State<BouncingDot> {
  late final StreamSubscription<void> _tickSub;
  late _DotState _state;

  Duration get _bounceDuration {
    final tickMs = (60000 / widget.bpm).round();
    return Duration(milliseconds: (tickMs * 0.9).round());
  }
  Duration get _pulseDuration => const Duration(milliseconds: 100);

  @override
  void initState() {
    super.initState();
    _state = _DotStateStore().get(widget.side);
    _tickSub = TickService().tickStream.listen((_) => _onTick());
  }

  void _onTick() {
    setState(() {
      _state.topOffset = (_state.topOffset == 0.15) ? 0.85 : 0.15;
      _state.pulsing = true;
    });
    _DotStateStore().update(widget.side, _state);

    Future.delayed(_pulseDuration, () {
      if (mounted) {
        setState(() => _state.pulsing = false);
        _DotStateStore().update(widget.side, _state);
      }
    });
  }

  @override
  void didUpdateWidget(covariant BouncingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isRunning && oldWidget.isRunning) {
      final distanceToTop = (_state.topOffset - 0.15).abs();
      final distanceToBottom = (_state.topOffset - 0.85).abs();

      setState(() {
        _state.topOffset = (distanceToTop < distanceToBottom) ? 0.15 : 0.85;
        _state.pulsing = false;
      });
      _DotStateStore().update(widget.side, _state);
    }
  }

  @override
  void dispose() {
    _tickSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double size = _state.pulsing ? 22 : 16;
    final Color glow = _state.pulsing ? Colors.tealAccent.shade100 : Colors.tealAccent;
    final screenHeight = MediaQuery.of(context).size.height;
    final y = (_state.topOffset * screenHeight) - (size / 2);

    return SizedBox(
      width: 40,
      height: screenHeight,
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
                color: glow,
                boxShadow: _state.pulsing
                    ? [BoxShadow(color: glow, blurRadius: 12, spreadRadius: 2)]
                    : [],
              ),
            ),
          ),
        ],
      ),
    );
  }
}