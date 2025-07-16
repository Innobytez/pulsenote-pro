import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/audio_service.dart';
import '../services/tick_service.dart';
import '../services/metronome_sequencer_service.dart';
import '../widgets/wheel_picker.dart';
import '../widgets/metronome_sequencer_settings_modal.dart';

class MetronomeScreen extends StatefulWidget {
  @override
  _MetronomeScreenState createState() => _MetronomeScreenState();
}

class _MetronomeScreenState extends State<MetronomeScreen> {
  int bpm = 60;
  bool isRunning = false;
  bool soundOn = true;
  bool sequencerEnabled = false;
  bool _prefsLoaded = false;

  late final TickService _tickService;
  StreamSubscription<void>? _tickSub;
  List<DateTime> tapTimes = [];
  Timer? _tapResetTimer;

  DateTime? _lastClickTime;
  DateTime? _tapSuppressionUntil;

  final GlobalKey<MetronomeSequencerWidgetState> _seqKey = GlobalKey<MetronomeSequencerWidgetState>();

  @override
  void initState() {
    super.initState();
    _tickService = TickService();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedBpm = prefs.getInt('metronome_screen_bpm');
    final savedSound = prefs.getBool('metronome_screen_sound');
    final savedSeqEnabled = prefs.getBool('metronome_sequencer_enabled');

    final sequencer = MetronomeSequencerService();
    final loaded = await sequencer.loadMostRecent();
    if (!loaded) sequencer.initDefault();

    if (!mounted) return;
    setState(() {
      if (loaded) {
        bpm = sequencer.bpm.clamp(10, 240);
      } else {
        bpm = savedBpm?.clamp(10, 240) ?? 60;
      }
      soundOn = savedSound ?? true;
      sequencerEnabled = savedSeqEnabled ?? false;
      _prefsLoaded = true;
    });

    MetronomeSequencerService().setSoundOn(soundOn);
  }

  void _startMetronome() {
    if (sequencerEnabled) {
      final seq = MetronomeSequencerService();

      // ← ADD THESE 4 LINES:
      if (seq.bars.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No bars created in sequencer!')),
        );
        return;
      }

      seq.start(bpm: bpm, soundOn: soundOn);
    } else {
      _tickSub?.cancel();
      _tickSub = _tickService.tickStream.listen((_) {
        final now = DateTime.now();
        if (_tapSuppressionUntil != null && now.isBefore(_tapSuppressionUntil!)) {
          return; // suppress tick click
        }

        if (soundOn) {
          AudioService.playClick();
          _lastClickTime = now;
        }
      });
      _tickService.start(bpm);
    }
    setState(() => isRunning = true);
  }

  void _stopMetronome() {
    _tickService.stop();
    _tickSub?.cancel();
    _tickSub = null;

    if (sequencerEnabled) {
      MetronomeSequencerService().stop();
    }

    setState(() => isRunning = false);
  }

  void _tapTempo() {
    final now = DateTime.now();
    tapTimes.add(now);

    _tapResetTimer?.cancel();
    _tapResetTimer = Timer(Duration(seconds: 6), () => tapTimes.clear());
    if (tapTimes.length > 4) tapTimes.removeAt(0);

    if (tapTimes.length >= 2) {
      // 1) build raw list of intervals in ms
      final intervals = <int>[];
      for (int i = 1; i < tapTimes.length; i++) {
        intervals.add(tapTimes[i].difference(tapTimes[i - 1]).inMilliseconds);
      }

      // 2) look at the most recent interval
      final last = intervals.last;

      // 3) define an allowable deviation (here 20% of last)
      final deviation = (last * 0.20).round();

      // 4) keep only those intervals within ±deviation of last
      final filtered = intervals
        .where((ms) => (ms - last).abs() <= deviation)
        .toList();

      // 5) compute average — or fallback to last if filtered is empty
      final avgMs = filtered.isNotEmpty
        ? filtered.reduce((a, b) => a + b) ~/ filtered.length
        : last;

      // 6) convert to BPM
      final newBpm = (60000 / avgMs).clamp(10, 240).round();

      setState(() => bpm = newBpm);
      SharedPreferences.getInstance()
        .then((p) => p.setInt('metronome_screen_bpm', newBpm));
      if (isRunning) _tickService.updateBpm(newBpm);
    }

    if (soundOn && !sequencerEnabled) {
      AudioService.playClick();
      _lastClickTime = DateTime.now();

      // Suppress metronome clicks for 2× expected interval
      final suppressionDuration = bpm > 0
          ? Duration(milliseconds: (60000 / bpm * 1.5).round())
          : Duration(milliseconds: 1000); // fallback
      _tapSuppressionUntil = _lastClickTime!.add(suppressionDuration);

    }
 
  }

  void _openSequencerSettings() {
    _tickService.stop();
    _tickSub?.cancel();
    _tickSub = null;
    MetronomeSequencerService().stop();
    setState(() => isRunning = false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => MetronomeSequencerSettingsModal(
        initialEnabled: sequencerEnabled,
        onToggle: (enabled) {
          if (!enabled) {
            MetronomeSequencerService().saveCurrentState();
          }          
          if (!mounted) return;
          setState(() => sequencerEnabled = enabled);
          SharedPreferences.getInstance().then(
            (prefs) => prefs.setBool('metronome_sequencer_enabled', enabled),
          );
        },
      ),
      ).then((_) {
      // once the modal closes, pull in whatever BPM the sequencer just loaded
      final seq = MetronomeSequencerService();
      final loadedBpm = seq.bpm.clamp(10, 240);
      setState(() => bpm = loadedBpm);
      SharedPreferences.getInstance().then(
        (p) => p.setInt('metronome_screen_bpm', loadedBpm),
      );
      if (isRunning) _tickService.updateBpm(loadedBpm);
    });
  }

  @override
  void dispose() {
    if (sequencerEnabled) {
      MetronomeSequencerService().saveCurrentState();
    }
    _tapResetTimer?.cancel();
    _tickSub?.cancel();
    _tickService.stop();
    MetronomeSequencerService().stop();
    super.dispose();
  }

@override
Widget build(BuildContext context) {
  if (!_prefsLoaded) return const SizedBox.shrink();

  final media = MediaQuery.of(context);
  final screenWidth = media.size.width;
  final wheelHeight = screenWidth * 0.8;
  final controlHeight = 100.0;

  return SafeArea(
    top: true,
    bottom: true,
    child: Column(
      children: [
        // ─── Sequencer (fills available space only) ─────────────
        sequencerEnabled
          ? Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 8),
                child: MetronomeSequencerWidget(
                  key: _seqKey,
                  onStop: _stopMetronome,    // ← add this
                ),
              ),
            )
          : const Spacer(),

        // ─── Wheel Picker (fixed height) ───────────────────────
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
                // also update service.bpm so saveToPrefs picks it up
                MetronomeSequencerService().bpm = val;
                SharedPreferences.getInstance()
                    .then((p) => p.setInt('metronome_screen_bpm', val));
                if (isRunning) _tickService.updateBpm(bpm);
              },
            ),
          ),
        ),

        // ─── Controls (fixed height) ───────────────────────────
        SizedBox(
          height: controlHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                iconSize: 40,
                onPressed: () {
                  setState(() => soundOn = !soundOn);
                  MetronomeSequencerService().setSoundOn(soundOn);
                  SharedPreferences.getInstance()
                      .then((p) => p.setBool('metronome_screen_sound', soundOn));
                },
                icon: Icon(soundOn ? Icons.volume_up : Icons.volume_off, color: Colors.white),
              ),
              IconButton(
                iconSize: 40,
                onPressed: () => isRunning ? _stopMetronome() : _startMetronome(),
                icon: Icon(isRunning ? Icons.stop_circle : Icons.play_circle, color: Colors.white),
              ),
              IconButton(
                iconSize: 40,
                onPressed: _tapTempo,
                icon: const Icon(Icons.touch_app, color: Colors.white),
              ),
              IconButton(
                iconSize: 40,
                onPressed: _openSequencerSettings,
                icon: const Icon(Icons.settings, color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
}