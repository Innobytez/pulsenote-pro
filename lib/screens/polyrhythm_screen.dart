// lib/screens/polyrhythm_screen.dart
import 'package:flutter/material.dart';

class PolyrhythmScreen extends StatelessWidget {
  const PolyrhythmScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Text(
          'Polyrhythm mode coming soon!',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    );
  }
}