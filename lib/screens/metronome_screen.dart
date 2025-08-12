// File: lib/screens/metronome_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state_service.dart';
import '../services/audio_service.dart';
import '../services/tick_service.dart';
import '../widgets/wheel_picker.dart';
import '../widgets/metronome_settings_modal.dart';

class MetronomeScreen extends StatefulWidget {
  /// Whether this tab is active (so we can stop playback when switching away)
  final bool active;

  const MetronomeScreen({
    super.key,
    required this.active,
  });

  @override
  State<MetronomeScreen> createState() => _MetronomeScreenState();
}

class _MetronomeScreenState extends State<MetronomeScreen> {
  final TickService _tickService = TickService();
  StreamSubscription<void>? _clickSub;
  StreamSubscription<void>? _tempoIncSub;
  bool _isRunning = false;

  // For tap-tempo
  final List<DateTime> _tapTimes = [];
  Timer? _tapResetTimer;
  DateTime? _tapSuppressionUntil;

  @override
  void didUpdateWidget(covariant MetronomeScreen old) {
    super.didUpdateWidget(old);
    if (old.active && !widget.active && _isRunning) {
      _stop();
    }
  }

  void _start() {
    final appState = context.read<AppStateService>();
    final bpm = appState.bpm;

    // cleanup
    _clickSub?.cancel();
    _tempoIncSub?.cancel();

    _tickService.start(bpm);

    // tempo-increase
    if (appState.tempoIncreaseEnabled) {
      int counter = 0;
      _tempoIncSub = _tickService.tickStream.skip(1).listen((_) {
        counter++;
        if (counter >= appState.tempoIncreaseY) {
          counter = 0;
          final newBpm = (appState.bpm + appState.tempoIncreaseX).clamp(10, 240);
          appState.setBpm(newBpm);
          _tickService.updateBpm(newBpm);
        }
      });
    }

    // live soundOn check each tick
    _clickSub = _tickService.tickStream.listen((_) {
      final now = DateTime.now();
      if (_tapSuppressionUntil != null && now.isBefore(_tapSuppressionUntil!)) return;
      if (context.read<AppStateService>().soundOn) {
        AudioService.playClick();
      }
    });

    setState(() => _isRunning = true);
  }

  void _stop() {
    _tickService.stop();
    _clickSub?.cancel();
    _tempoIncSub?.cancel();
    setState(() => _isRunning = false);
  }

  void _onDragBpm(int val) {
    final bpm = val.clamp(10, 240);
    final appState = context.read<AppStateService>();
    appState.setBpm(bpm);
    if (_isRunning) _tickService.updateBpm(bpm);
  }

  void _tapTempo() {
    final appState = context.read<AppStateService>();
    final now = DateTime.now();
    _tapTimes.add(now);
    _tapResetTimer?.cancel();
    _tapResetTimer = Timer(const Duration(seconds: 6), () => _tapTimes.clear());
    if (_tapTimes.length > 4) _tapTimes.removeAt(0);

    if (_tapTimes.length >= 2) {
      final intervals = <int>[];
      for (int i = 1; i < _tapTimes.length; i++) {
        intervals.add(_tapTimes[i].difference(_tapTimes[i - 1]).inMilliseconds);
      }
      final last = intervals.last;
      final dev = (last * 0.2).round();
      final filtered = intervals.where((ms) => (ms - last).abs() <= dev).toList();
      final avg = filtered.isNotEmpty
          ? filtered.reduce((a, b) => a + b) ~/ filtered.length
          : last;
      final newBpm = (60000 / avg).clamp(10, 240).round();
      appState.setBpm(newBpm);
      if (_isRunning) _tickService.updateBpm(newBpm);
    }

    if (context.read<AppStateService>().soundOn) {
      AudioService.playClick();
      _tapSuppressionUntil = now.add(
        Duration(milliseconds: (60000 / context.read<AppStateService>().bpm * 1.5).round()),
      );
    }
  }

  void _toggleSound() {
    final appState = context.read<AppStateService>();
    appState.setSoundOn(!appState.soundOn);
  }

  Future<void> _openSettings() async {
    _stop();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const MetronomeSettingsModal(),
    );
  }

  @override
  void dispose() {
    _clickSub?.cancel();
    _tempoIncSub?.cancel();
    _tickService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateService>();
    final width = MediaQuery.of(context).size.width;
    final wheelHeight = width * 0.8;

    return SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // BPM wheel
          SizedBox(
            height: wheelHeight,
            child: WheelPicker(
              initialBpm: appState.bpm,
              minBpm: 10,
              maxBpm: 240,
              wheelSize: wheelHeight,
              onBpmChanged: _onDragBpm,
            ),
          ),

          // controls
          SizedBox(
            height: 100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // sound toggle
                IconButton(
                  iconSize: 40,
                  icon: Icon(appState.soundOn ? Icons.volume_up : Icons.volume_off),
                  onPressed: _toggleSound,
                ),
                // play / stop
                IconButton(
                  iconSize: 40,
                  icon: Icon(_isRunning ? Icons.stop_circle : Icons.play_circle),
                  onPressed: () => _isRunning ? _stop() : _start(),
                ),
                // tap tempo
                IconButton(
                  iconSize: 40,
                  icon: const Icon(Icons.touch_app),
                  onPressed: _tapTempo,
                ),
                // settings
                IconButton(
                  iconSize: 40,
                  icon: const Icon(Icons.settings),
                  onPressed: _openSettings,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}