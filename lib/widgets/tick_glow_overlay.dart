import 'dart:async';
import 'package:flutter/material.dart';
import '../services/tick_service.dart';

class TickGlowOverlay extends StatefulWidget {
  const TickGlowOverlay({super.key});

  @override
  State<TickGlowOverlay> createState() => _TickGlowOverlayState();
}

class _TickGlowOverlayState extends State<TickGlowOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final StreamSubscription<void> _tickSub;
  bool _hasStarted = false;

  Duration get _fadeDuration {
    final bpm = TickService().bpm;
    final tickMs = (60000 / bpm).round();
    return Duration(milliseconds: (tickMs * 0.5).round());
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _fadeDuration,
      value: 1.0,
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _tickSub = TickService().tickStream.listen((_) {
      setState(() => _hasStarted = true);
      _controller.duration = _fadeDuration;
      _controller.forward(from: 0.0);
    });
  }

  @override
  void dispose() {
    _tickSub.cancel();
    _controller.dispose();
    super.dispose();
  }

  Widget _glowBar({required Alignment alignment, required Offset offset, required Size size}) {
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
                color: Colors.tealAccent.withOpacity(1.0 - _fade.value),
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

    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _fade,
          builder: (_, __) => Stack(
            children: [
              // Top glow (50% wide, above screen)
              _glowBar(
                alignment: Alignment.topCenter,
                offset: const Offset(0, -40),
                size: Size(screenWidth * 0.5, 2),
              ),

              // Bottom glow (50% wide, below screen)
              _glowBar(
                alignment: Alignment.bottomCenter,
                offset: const Offset(0, 40),
                size: Size(screenWidth * 0.5, 2),
              ),

              // Left glow (50% tall, offscreen left)
              _glowBar(
                alignment: Alignment.centerLeft,
                offset: const Offset(-40, 0),
                size: Size(2, screenHeight * 0.5),
              ),

              // Right glow (50% tall, offscreen right)
              _glowBar(
                alignment: Alignment.centerRight,
                offset: const Offset(40, 0),
                size: Size(2, screenHeight * 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}