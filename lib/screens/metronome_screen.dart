// File: lib/screens/metronome_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_state_service.dart';
import '../services/audio_service.dart';
import '../services/tick_service.dart';
import '../services/playback_coordinator.dart';
import '../services/system_media_handler.dart';
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
  final _coord = PlaybackCoordinator.instance;

  StreamSubscription<void>? _clickSub;
  StreamSubscription<void>? _tempoIncSub;
  bool _isRunning = false;

  // For tap-tempo
  final List<DateTime> _tapTimes = [];
  Timer? _tapResetTimer;
  DateTime? _tapSuppressionUntil;

  // Local (screen-scoped) preferences
  bool _showTempoText = false;

  // Skip Beats Mode (local, persisted)
  bool _skipEnabled = false;
  int _skipX = 4; // play this many beats…
  int _skipY = 4; // …then skip this many beats
  int _skipCounter = 0;
  bool _skipPhasePlay = true; // true=playing phase, false=skipping phase

  void _publishMeta() {
    final bpm = context.read<AppStateService>().bpm;
    SystemMediaHandler.last?.setNowPlaying(title: 'Metronome', subtitle: '$bpm BPM');
  }

  @override
  void initState() {
    super.initState();
    _loadLocalPrefs();

    _coord.bind(
      id: 'metronome',
      onPlay: () async {
        if (!_isRunning) _start();
      },
      onPause: () async {
        if (_isRunning) _stop();
      },
      isPlaying: () => _isRunning,
    );

    if (widget.active) {
      _coord.activate('metronome');
      _publishMeta();
    }
  }

  Future<void> _loadLocalPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _showTempoText = p.getBool('met_show_tempo_name') ?? false;
      _skipEnabled   = p.getBool('met_skip_enabled') ?? false;
      _skipX         = p.getInt('met_skip_x') ?? 4;
      _skipY         = p.getInt('met_skip_y') ?? 4;
      _skipX = _skipX.clamp(1, 16);
      _skipY = _skipY.clamp(1, 16);
    });
  }

  Future<void> _setShowTempoText(bool v) async {
    setState(() => _showTempoText = v);
    final p = await SharedPreferences.getInstance();
    await p.setBool('met_show_tempo_name', v);
  }

  Future<void> _setSkipEnabled(bool v) async {
    setState(() => _skipEnabled = v);
    final p = await SharedPreferences.getInstance();
    await p.setBool('met_skip_enabled', v);
    _resetSkipCycle();
  }

  Future<void> _setSkipValues(int x, int y) async {
    setState(() {
      _skipX = x.clamp(1, 16);
      _skipY = y.clamp(1, 16);
    });
    final p = await SharedPreferences.getInstance();
    await p.setInt('met_skip_x', _skipX);
    await p.setInt('met_skip_y', _skipY);
    _resetSkipCycle();
  }

  void _resetSkipCycle() {
    _skipCounter = 0;
    _skipPhasePlay = true;
  }

  @override
  void didUpdateWidget(covariant MetronomeScreen old) {
    super.didUpdateWidget(old);

    if (!old.active && widget.active) {
      _coord.activate('metronome');
      _publishMeta();
    }

    if (old.active && !widget.active && _isRunning) {
      _stop();
    }
  }

  String _tempoName(int bpm) {
    if (bpm < 24) return 'Larghissimo';
    if (bpm < 40) return 'Grave';
    if (bpm < 60) return 'Largo';
    if (bpm < 66) return 'Larghetto';
    if (bpm < 76) return 'Adagio';
    if (bpm < 108) return 'Andante';
    if (bpm < 120) return 'Moderato';
    if (bpm < 156) return 'Allegro';
    if (bpm < 176) return 'Vivace';
    if (bpm < 200) return 'Presto';
    return 'Prestissimo';
  }

  void _start() {
    final appState = context.read<AppStateService>();
    final bpm = appState.bpm;

    _coord.activate('metronome');
    _publishMeta();

    _clickSub?.cancel();
    _tempoIncSub?.cancel();

    _resetSkipCycle();

    _tickService.start(bpm);

    if (appState.tempoIncreaseEnabled) {
      int counter = 0;
      _tempoIncSub = _tickService.tickStream.skip(1).listen((_) {
        counter++;
        if (counter >= appState.tempoIncreaseY) {
          counter = 0;
          final newBpm = (appState.bpm + appState.tempoIncreaseX).clamp(10, 240);
          appState.setBpm(newBpm);
          _tickService.updateBpm(newBpm);
          _publishMeta(); // live subtitle
        }
      });
    }

    _clickSub = _tickService.tickStream.listen((_) {
      final now = DateTime.now();
      if (_tapSuppressionUntil != null && now.isBefore(_tapSuppressionUntil!)) return;

      bool shouldClick = context.read<AppStateService>().soundOn;
      if (_skipEnabled) {
        if (_skipPhasePlay) {
          shouldClick = shouldClick && true;
          _skipCounter++;
          if (_skipCounter >= _skipX) {
            _skipCounter = 0;
            _skipPhasePlay = false;
          }
        } else {
          shouldClick = false;
          _skipCounter++;
          if (_skipCounter >= _skipY) {
            _skipCounter = 0;
            _skipPhasePlay = true;
          }
        }
      }

      if (shouldClick) {
        AudioService.playClick();
      }
    });

    setState(() => _isRunning = true);
  }

  void _stop() {
    _tickService.stop();
    _clickSub?.cancel();
    _tempoIncSub?.cancel();
    _resetSkipCycle();
    setState(() => _isRunning = false);
  }

  void _onDragBpm(int val) {
    final bpm = val.clamp(10, 240);
    final appState = context.read<AppStateService>();
    appState.setBpm(bpm);
    if (_isRunning) _tickService.updateBpm(bpm);
    _publishMeta(); // live subtitle even when paused
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
      _publishMeta(); // live subtitle
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
    if (_isRunning) _stop();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => MetronomeSettingsModal(
        showTempoText: _showTempoText,
        onShowTempoTextChanged: _setShowTempoText,

        // Skip Beats bindings
        skipEnabled: _skipEnabled,
        skipX: _skipX,
        skipY: _skipY,
        onSkipEnabledChanged: _setSkipEnabled,
        onSkipValuesChanged: _setSkipValues,
      ),
    );
  }

  @override
  void dispose() {
    _clickSub?.cancel();
    _tempoIncSub?.cancel();
    _tickService.stop();
    _tapResetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateService>();
    final width = MediaQuery.of(context).size.width;
    final wheelHeight = width * 0.8;

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: _showTempoText
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _tempoName(appState.bpm),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.tealAccent,
                          fontSize: 64,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.5,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),

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

          SizedBox(
            height: 100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  iconSize: 40,
                  icon: Icon(appState.soundOn ? Icons.volume_up : Icons.volume_off),
                  onPressed: _toggleSound,
                ),
                IconButton(
                  iconSize: 40,
                  icon: Icon(_isRunning ? Icons.stop_circle : Icons.play_circle),
                  onPressed: () => _isRunning ? _stop() : _start(),
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