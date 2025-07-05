import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/audio_service.dart';
import '../services/tick_service.dart';
import '../widgets/wheel_picker.dart';

class MetronomeScreen extends StatefulWidget {
  @override
  _MetronomeScreenState createState() => _MetronomeScreenState();
}

class _MetronomeScreenState extends State<MetronomeScreen> {
  int bpm = 60;
  bool isRunning = false;
  bool soundOn = true;
  bool _prefsLoaded = false;

  late final TickService _tickService;
  StreamSubscription<void>? _tickSub;

  List<DateTime> tapTimes = [];
  Timer? _tapResetTimer;

  @override
  void initState() {
    super.initState();
    _tickService = TickService();
    _loadPreferences();

    _tickSub = _tickService.tickStream.listen((_) {
      if (soundOn) AudioService.playClick();
    });
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedBpm = prefs.getInt('metronome_screen_bpm');
    final savedSound = prefs.getBool('metronome_screen_sound');

    setState(() {
      bpm = savedBpm?.clamp(10, 240) ?? 60;
      soundOn = savedSound ?? true;
      _prefsLoaded = true;
    });
  }

  Future<void> _saveBpm(int newBpm) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('metronome_screen_bpm', newBpm);
  }

  Future<void> _saveSound(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('metronome_screen_sound', value);
  }

  void _startMetronome() {
    _tickService.start(bpm);
    setState(() => isRunning = true);
  }

  void _stopMetronome() {
    _tickService.stop();
    setState(() => isRunning = false);
  }

  void _toggleStartStop() {
    isRunning ? _stopMetronome() : _startMetronome();
  }

  void _tapTempo() {
    final now = DateTime.now();
    tapTimes.add(now);

    _tapResetTimer?.cancel();
    _tapResetTimer = Timer(Duration(seconds: 6), () {
      tapTimes.clear();
    });

    if (tapTimes.length > 4) tapTimes.removeAt(0);

    if (tapTimes.length >= 2) {
      final intervals = <int>[];
      for (int i = 1; i < tapTimes.length; i++) {
        intervals.add(tapTimes[i].difference(tapTimes[i - 1]).inMilliseconds);
      }
      final avgMs = intervals.reduce((a, b) => a + b) ~/ intervals.length;
      final newBpm = (60000 / avgMs).clamp(10, 240).round();

      setState(() => bpm = newBpm);
      _saveBpm(newBpm);
      if (isRunning) _tickService.start(bpm);
    }

    if (soundOn) AudioService.playClick();
  }

  @override
  void dispose() {
    _tapResetTimer?.cancel();
    _tickSub?.cancel();
    _tickService.stop();
    super.dispose();
  }

  @override
Widget build(BuildContext context) {
  if (!_prefsLoaded) return SizedBox.shrink();

  return Padding(
    padding: const EdgeInsets.only(top: 250.0), // Pushes entire screen down
    child: Column(
      children: [
        Expanded(
          child: Center(
            child: WheelPicker(
              initialBpm: bpm,
              minBpm: 10,
              maxBpm: 240,
              wheelSize: MediaQuery.of(context).size.width * 0.8,
              onBpmChanged: (val) {
                setState(() => bpm = val);
                _saveBpm(val);
                if (isRunning) _tickService.start(bpm);
              },
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              iconSize: 40.0,
              onPressed: () {
                setState(() => soundOn = !soundOn);
                _saveSound(soundOn);
              },
              icon: Icon(
                soundOn ? Icons.volume_up : Icons.volume_off,
                color: Colors.white,
              ),
            ),
            IconButton(
              iconSize: 40.0,
              onPressed: _toggleStartStop,
              icon: Icon(
                isRunning ? Icons.stop_circle : Icons.play_circle,
                color: Colors.white,
              ),
            ),
            IconButton(
              iconSize: 40.0,
              onPressed: _tapTempo,
              icon: const Icon(Icons.music_note, color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    ),
  );
}
}