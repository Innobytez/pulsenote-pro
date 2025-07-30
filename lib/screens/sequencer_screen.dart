// File: lib/screens/sequencer_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/audio_service.dart';
import '../services/tick_service.dart';
import '../services/metronome_sequencer_service.dart';
import '../widgets/wheel_picker.dart';
import '../widgets/sequencer_settings_modal.dart';

class SequencerScreen extends StatefulWidget {
  const SequencerScreen({super.key});
  @override
  State<SequencerScreen> createState() => _SequencerScreenState();
}

class _SequencerScreenState extends State<SequencerScreen> {
  int bpm = 60;
  bool isRunning = false;
  bool soundOn = true;
  bool tempoIncreaseEnabled = false;
  int tempoIncreaseX = 1;
  int tempoIncreaseY = 1;
  StreamSubscription<void>? _tempoIncSub;

  final List<DateTime> _tapTimes = [];
  Timer? _tapResetTimer;

  late final TickService _tickService;

  @override
  void initState() {
    super.initState();
    _tickService = TickService();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    tempoIncreaseEnabled = prefs.getBool('tempo_increase_enabled') ?? false;
    tempoIncreaseX = prefs.getInt('tempo_increase_x') ?? 1;
    tempoIncreaseY = prefs.getInt('tempo_increase_y') ?? 1;
    soundOn = prefs.getBool('metronome_screen_sound') ?? true;

    final seq = MetronomeSequencerService();
    final loaded = await seq.loadMostRecent();
    if (!loaded) seq.initDefault();

    if (!mounted) return;
    setState(() {
      bpm = seq.bpm.clamp(10, 240);
    });
    seq.setSoundOn(soundOn);
  }

  void _start() {
    if (tempoIncreaseEnabled) _startTempoIncreaseMode();
    final seq = MetronomeSequencerService();
    if (seq.bars.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No bars created in sequencer!')),
      );
      return;
    }
    seq.start(bpm: bpm, soundOn: soundOn);
    setState(() => isRunning = true);
  }

  void _stop() {
    MetronomeSequencerService().stop();
    _stopTempoIncreaseMode();
    setState(() => isRunning = false);
  }

  void _tapTempo() {
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
      final deviation = (last * 0.2).round();
      final filtered = intervals.where((ms) => (ms - last).abs() <= deviation).toList();
      final avgMs = filtered.isNotEmpty
          ? filtered.reduce((a, b) => a + b) ~/ filtered.length
          : last;
      final newBpm = (60000 / avgMs).clamp(10, 240).round();
      setState(() => bpm = newBpm);
      SharedPreferences.getInstance().then((p) => p.setInt('metronome_screen_bpm', newBpm));
      if (isRunning) _tickService.updateBpm(newBpm);
    }
    if (soundOn) {
      AudioService.playClick();
    }
  }

  void _toggleSound() {
    setState(() => soundOn = !soundOn);
    MetronomeSequencerService().setSoundOn(soundOn);
    SharedPreferences.getInstance()
        .then((p) => p.setBool('metronome_screen_sound', soundOn));
  }

  void _startTempoIncreaseMode() {
    _tempoIncSub?.cancel();
    bool firstSkipped = false;
    int count = 0;
    _tempoIncSub = _tickService.tickStream.listen((_) {
      if (!firstSkipped) {
        firstSkipped = true;
        return;
      }
      count++;
      if (count >= tempoIncreaseY) {
        count = 0;
        final updated = (bpm + tempoIncreaseX).clamp(10, 240);
        setState(() => bpm = updated);
        MetronomeSequencerService().bpm = updated;
        _tickService.updateBpm(updated);
        SharedPreferences.getInstance()
            .then((p) => p.setInt('metronome_screen_bpm', updated));
      }
    });
    _tickService.start(bpm);
  }

  void _stopTempoIncreaseMode() {
    _tempoIncSub?.cancel();
    _tempoIncSub = null;
  }

  void _openSettings() {
    _tickService.stop();
    MetronomeSequencerService().stop();
    setState(() => isRunning = false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SequencerSettingsModal(
        initialEnabled: tempoIncreaseEnabled,
        onToggle: (enabled) {
          setState(() => tempoIncreaseEnabled = enabled);
          SharedPreferences.getInstance()
            .then((p) => p.setBool('tempo_increase_enabled', enabled));
        },
      ),
    ).then((_) {
      SharedPreferences.getInstance().then((prefs) {
        tempoIncreaseEnabled = prefs.getBool('tempo_increase_enabled') ?? false;
        tempoIncreaseX = prefs.getInt('tempo_increase_x') ?? 1;
        tempoIncreaseY = prefs.getInt('tempo_increase_y') ?? 1;
      });
      final seq = MetronomeSequencerService();
      setState(() => bpm = seq.bpm.clamp(10, 240));
      if (isRunning) _tickService.updateBpm(bpm);
    });
  }

  @override
  void dispose() {
    _tempoIncSub?.cancel();
    _tickService.stop();
    MetronomeSequencerService().stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final wheelHeight = width * 0.8;
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 8),
              child: MetronomeSequencerWidget(onStop: _stop),
            ),
          ),
          SizedBox(
            height: wheelHeight,
            child: Center(
              child: WheelPicker(
                initialBpm: bpm,
                minBpm: 10,
                maxBpm: 240,
                wheelSize: wheelHeight,
                onBpmChanged: (val) {
                  setState(() => bpm = val);
                  MetronomeSequencerService().bpm = val;
                  SharedPreferences.getInstance()
                      .then((p) => p.setInt('metronome_screen_bpm', val));
                  if (isRunning) _tickService.updateBpm(val);
                },
              ),
            ),
          ),
          SizedBox(
            height: 100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  iconSize: 40,
                  icon: Icon(soundOn ? Icons.volume_up : Icons.volume_off),
                  onPressed: _toggleSound,
                ),
                IconButton(
                  iconSize: 40,
                  icon: Icon(isRunning ? Icons.stop_circle : Icons.play_circle),
                  onPressed: () => isRunning ? _stop() : _start(),
                ),
                IconButton(
                  iconSize: 40,
                  icon: const Icon(Icons.touch_app),
                  onPressed: _tapTempo,
                ),
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
