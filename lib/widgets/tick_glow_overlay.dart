import 'dart:async';
import 'package:flutter/material.dart';
import '../services/tick_service.dart';
import 'bouncing_dot.dart' show PolyrhythmVizBus; // use the inlined bus

class TickGlowOverlay extends StatefulWidget {
  const TickGlowOverlay({super.key});

  @override
  State<TickGlowOverlay> createState() => _TickGlowOverlayState();
}

class _TickGlowOverlayState extends State<TickGlowOverlay> with TickerProviderStateMixin {
  // Existing (all-bars) controller remains for normal mode and "both" in poly mode.
  late final AnimationController _controllerBoth;
  late final Animation<double> _fadeBoth;

  // New: independent fades for left(P) and right(Q) bars in polyrhythm mode.
  late final AnimationController _controllerLeft;
  late final AnimationController _controllerRight;
  late final Animation<double> _fadeLeft;
  late final Animation<double> _fadeRight;

  // Subscriptions
  StreamSubscription<void>? _tickSub;      // normal mode
  StreamSubscription<void>? _busLeftSub;   // poly mode
  StreamSubscription<void>? _busRightSub;  // poly mode

  // Rebinding to poly/normal
  final _bus = PolyrhythmVizBus.instance;
  VoidCallback? _enabledListener;

  // Coincidence detection for "both" (top/bottom) flash
  DateTime? _lastLeftAt;
  DateTime? _lastRightAt;
  static const Duration _bothWindow = Duration(milliseconds: 15);

  bool _hasStarted = false;

  static const _visualDelay = Duration(milliseconds: 0); // Match SoLoud latency

  Duration get _fadeDuration {
    final bpm = TickService().bpm;
    final tickMs = (60000 / bpm).round();
    return Duration(milliseconds: (tickMs * 0.5).round());
  }

  @override
  void initState() {
    super.initState();

    _controllerBoth = AnimationController(vsync: this, duration: _fadeDuration, value: 1.0);
    _fadeBoth = CurvedAnimation(parent: _controllerBoth, curve: Curves.easeOut);

    _controllerLeft = AnimationController(vsync: this, duration: _fadeDuration, value: 1.0);
    _controllerRight = AnimationController(vsync: this, duration: _fadeDuration, value: 1.0);
    _fadeLeft = CurvedAnimation(parent: _controllerLeft, curve: Curves.easeOut);
    _fadeRight = CurvedAnimation(parent: _controllerRight, curve: Curves.easeOut);

    _rebindSources(); // initial bind

    // Rebind if polyrhythm mode toggles on/off (avoid stacking)
    _enabledListener = () {
      if (!mounted) return;
      _rebindSources();
    };
    _bus.enabled.addListener(_enabledListener!);
  }

  void _rebindSources() {
    _tickSub?.cancel();
    _busLeftSub?.cancel();
    _busRightSub?.cancel();

    _lastLeftAt = null;
    _lastRightAt = null;

    // Keep durations in sync with BPM changes
    final d = _fadeDuration;
    _controllerBoth.duration = d;
    _controllerLeft.duration = d;
    _controllerRight.duration = d;

    if (_bus.enabled.value) {
      // Polyrhythm: separate streams
      _busLeftSub = _bus.leftStream.listen((_) => _onLeft());
      _busRightSub = _bus.rightStream.listen((_) => _onRight());
    } else {
      // Normal: pulse everything on every tick (original behavior)
      _tickSub = TickService().tickStream.listen((_) {
        Future.delayed(_visualDelay, () {
          if (!mounted) return;
          setState(() => _hasStarted = true);
          _controllerBoth.duration = _fadeDuration;
          _controllerBoth.forward(from: 0.0);
        });
      });
    }
  }

  void _onLeft() {
    final now = DateTime.now();
    _lastLeftAt = now;

    setState(() => _hasStarted = true);

    _controllerLeft.duration = _fadeDuration;
    _controllerLeft.forward(from: 0.0);

    // If right happened just now too, flash BOTH (top/bottom).
    if (_lastRightAt != null && now.difference(_lastRightAt!) <= _bothWindow) {
      _controllerBoth.duration = _fadeDuration;
      _controllerBoth.forward(from: 0.0);
    }
  }

  void _onRight() {
    final now = DateTime.now();
    _lastRightAt = now;

    setState(() => _hasStarted = true);

    _controllerRight.duration = _fadeDuration;
    _controllerRight.forward(from: 0.0);

    // If left happened just now too, flash BOTH (top/bottom).
    if (_lastLeftAt != null && now.difference(_lastLeftAt!) <= _bothWindow) {
      _controllerBoth.duration = _fadeDuration;
      _controllerBoth.forward(from: 0.0);
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

    _controllerLeft.dispose();
    _controllerRight.dispose();
    _controllerBoth.dispose();
    super.dispose();
  }

  Widget _glowBar({
    required Alignment alignment,
    required Offset offset,
    required Size size,
    required double intensity, // 0..1
  }) {
    return Align(
      alignment: alignment,
      child: Transform.translate(
        offset: offset,
        child: Container(
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.tealAccent.withOpacity(1.0 - intensity),
                blurRadius: 50,
                spreadRadius: 25,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasStarted) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Normal mode: keep EXACT previous look (all four bars tied to _fadeBoth).
    if (!_bus.enabled.value) {
      return Positioned.fill(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _fadeBoth,
            builder: (_, __) => Stack(
              children: [
                _glowBar(
                  alignment: Alignment.topCenter,
                  offset: const Offset(0, -40),
                  size: Size(screenWidth * 0.5, 2),
                  intensity: _fadeBoth.value,
                ),
                _glowBar(
                  alignment: Alignment.bottomCenter,
                  offset: const Offset(0, 40),
                  size: Size(screenWidth * 0.5, 2),
                  intensity: _fadeBoth.value,
                ),
                _glowBar(
                  alignment: Alignment.centerLeft,
                  offset: const Offset(-40, 0),
                  size: Size(2, screenHeight * 0.5),
                  intensity: _fadeBoth.value,
                ),
                _glowBar(
                  alignment: Alignment.centerRight,
                  offset: const Offset(40, 0),
                  size: Size(2, screenHeight * 0.5),
                  intensity: _fadeBoth.value,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Polyrhythm mode:
    // - Left bar uses _fadeLeft (P)
    // - Right bar uses _fadeRight (Q)
    // - Top & bottom use _fadeBoth ONLY when P and Q coincide
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: Listenable.merge([_fadeLeft, _fadeRight, _fadeBoth]),
          builder: (_, __) => Stack(
            children: [
              // Top (coincidence only)
              _glowBar(
                alignment: Alignment.topCenter,
                offset: const Offset(0, -40),
                size: Size(screenWidth * 0.5, 2),
                intensity: _fadeBoth.value,
              ),
              // Bottom (coincidence only)
              _glowBar(
                alignment: Alignment.bottomCenter,
                offset: const Offset(0, 40),
                size: Size(screenWidth * 0.5, 2),
                intensity: _fadeBoth.value,
              ),
              // Left (P)
              _glowBar(
                alignment: Alignment.centerLeft,
                offset: const Offset(-40, 0),
                size: Size(2, screenHeight * 0.5),
                intensity: _fadeLeft.value,
              ),
              // Right (Q)
              _glowBar(
                alignment: Alignment.centerRight,
                offset: const Offset(40, 0),
                size: Size(2, screenHeight * 0.5),
                intensity: _fadeRight.value,
              ),
            ],
          ),
        ),
      ),
    );
  }
}