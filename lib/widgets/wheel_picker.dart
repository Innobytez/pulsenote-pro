import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WheelPicker extends StatefulWidget {
  final int initialBpm;
  final int minBpm;
  final int maxBpm;
  final ValueChanged<int> onBpmChanged;
  final double? wheelSize;

  const WheelPicker({
    super.key,
    required this.initialBpm,
    required this.onBpmChanged,
    this.minBpm = 10,
    this.maxBpm = 240,
    this.wheelSize,
  });

  @override
  _WheelPickerState createState() => _WheelPickerState();
}

class _WheelPickerState extends State<WheelPicker> with SingleTickerProviderStateMixin {
  late int _bpm;
  Offset _center = Offset.zero;
  double? _lastAngle;
  double _angleAccumulator = 0;

  late AnimationController _dotRotationController;
  late Animation<double> _dotRotation;
  double _currentDotAngle = 0;

  bool _hasInitialized = false;

  @override
  void initState() {
    super.initState();
    _bpm = widget.initialBpm.clamp(widget.minBpm, widget.maxBpm);
    _currentDotAngle = _bpmToAngle(_bpm);
    _dotRotationController = AnimationController(vsync: this, duration: Duration(milliseconds: 200));
    _dotRotation = AlwaysStoppedAnimation(_currentDotAngle);
  }

  @override
  void didUpdateWidget(covariant WheelPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clamped = widget.initialBpm.clamp(widget.minBpm, widget.maxBpm);
    if (clamped != _bpm) {
      final newAngle = _bpmToAngle(clamped);

      if (_hasInitialized) {
        _dotRotation = Tween<double>(
          begin: _currentDotAngle,
          end: newAngle,
        ).animate(CurvedAnimation(parent: _dotRotationController, curve: Curves.easeOut));
        _dotRotationController.forward(from: 0);
      } else {
        _dotRotation = AlwaysStoppedAnimation(newAngle);
        _hasInitialized = true;
      }

      _currentDotAngle = newAngle;
      setState(() => _bpm = clamped);
    }
  }

  double _bpmToAngle(int bpm) {
    final t = (bpm - widget.minBpm) / (widget.maxBpm - widget.minBpm);
    return t * 2 * pi;
  }

  void _handleRotation(Offset localPosition) {
    if (_center == Offset.zero) return;

    final dx = localPosition.dx - _center.dx;
    final dy = localPosition.dy - _center.dy;
    final angle = atan2(dy, dx);

    if (_lastAngle != null) {
      double delta = angle - _lastAngle!;
      if (delta.abs() > pi) {
        delta -= 2 * pi * delta.sign;
      }

      _angleAccumulator += delta;
      final bpmChange = (_angleAccumulator * 30).truncate(); // 30 = sensitivity

      if (bpmChange != 0) {
        _angleAccumulator -= bpmChange / 30.0; // remove used part
        final newBpm = (_bpm + bpmChange).clamp(widget.minBpm, widget.maxBpm);
        if (newBpm != _bpm) {
          HapticFeedback.selectionClick();
          final newAngle = _bpmToAngle(newBpm);
          _dotRotation = Tween<double>(
            begin: _currentDotAngle,
            end: newAngle,
          ).animate(CurvedAnimation(parent: _dotRotationController, curve: Curves.easeOut));

          _dotRotationController.forward(from: 0);
          _currentDotAngle = newAngle;

          setState(() => _bpm = newBpm);
          widget.onBpmChanged(_bpm);
        }
      }
    }

    _lastAngle = angle;
  }

  @override
  void dispose() {
    _dotRotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.wheelSize ??
        min(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height) * 0.6;

    final radius = size / 2 - 10;

    return GestureDetector(
      onPanStart: (details) {
        final box = context.findRenderObject() as RenderBox;
        _center = box.size.center(Offset.zero);
        _handleRotation(details.localPosition);
      },
      onPanUpdate: (details) => _handleRotation(details.localPosition),
      onPanEnd: (_) {
        _lastAngle = null;
        _angleAccumulator = 0;
      },
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black87,
                border: Border.all(color: Colors.tealAccent, width: 3),
              ),
              child: Center(
                child: Text(
                  '$_bpm',
                  style: TextStyle(
                    fontSize: size * 0.25,
                    color: Colors.tealAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _dotRotation,
              builder: (context, child) {
                final angle = _dotRotation.value - pi / 2;
                final dx = cos(angle) * radius;
                final dy = sin(angle) * radius;
                return Positioned(
                  left: size / 2 + dx - 5,
                  top: size / 2 + dy - 5,
                  child: child!,
                );
              },
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.tealAccent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}