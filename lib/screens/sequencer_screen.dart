// File: lib/screens/sequencer_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/audio_service.dart';
import '../services/tick_service.dart';
import '../services/metronome_sequencer_service.dart';
import '../services/app_state_service.dart';
import '../services/playback_coordinator.dart';
import '../services/system_media_handler.dart';
import '../widgets/wheel_picker.dart';
import '../widgets/sequencer_settings_modal.dart';

class SequencerScreen extends StatefulWidget {
  /// Whether this tab is active (so we can stop playback when switching away)
  final bool active;

  const SequencerScreen({super.key, required this.active});

  @override
  State<SequencerScreen> createState() => _SequencerScreenState();
}

class _SequencerScreenState extends State<SequencerScreen> {
  late final TickService _tickService;
  StreamSubscription<void>? _tempoIncSub;
  bool _isRunning = false;

  final List<DateTime> _tapTimes = [];
  Timer? _tapResetTimer;

  String _seqTitle() {
    final svc = MetronomeSequencerService();
    // Try to grab a user-facing title if your service exposes one.
    // (Safe: dynamic access guarded with try/catch.)
    try {
      final dyn = svc as dynamic;
      final t = dyn.title ?? dyn.name ?? dyn.projectName;
      if (t is String && t.trim().isNotEmpty) return t;
    } catch (_) {}
    return 'Sequencer';
  }

  void _publishMeta() {
    final bpm = context.read<AppStateService>().bpm;
    SystemMediaHandler.last?.setNowPlaying(
      title: _seqTitle(),
      subtitle: '$bpm BPM',
    );
  }

  @override
  void initState() {
    super.initState();
    _tickService = TickService();
    final bpm = context.read<AppStateService>().bpm;
    MetronomeSequencerService().bpm = bpm.clamp(10, 240);

    PlaybackCoordinator.instance.bind(
      id: 'sequencer',
      onPlay: () async {
        if (!_isRunning) _start();
      },
      onPause: () async {
        if (_isRunning) _stop();
      },
      isPlaying: () => _isRunning,
    );

    if (widget.active) {
      PlaybackCoordinator.instance.activate('sequencer');
      _publishMeta();
    }
  }

  @override
  void didUpdateWidget(covariant SequencerScreen old) {
    super.didUpdateWidget(old);
    if (old.active && !widget.active && _isRunning) _stop();
    if (!old.active && widget.active) {
      PlaybackCoordinator.instance.activate('sequencer');
      _publishMeta();
    }
  }

  void _installResumer() {
    TickService().setBackgroundResumer(() async {
      if (!_isRunning) _start();
    });
  }

  void _clearResumer() => TickService().setBackgroundResumer(null);

  void _start() {
    final appState = context.read<AppStateService>();
    final seq = MetronomeSequencerService();

    _publishMeta();

    _tempoIncSub?.cancel();
    if (appState.tempoIncreaseEnabled) {
      bool first = false;
      int count = 0;
      _tempoIncSub = _tickService.tickStream.listen((_) {
        if (!first) { first = true; return; }
        count++;
        if (count >= appState.tempoIncreaseY) {
          count = 0;
          final updated =
              (appState.bpm + appState.tempoIncreaseX).clamp(10, 240);
          appState.setBpm(updated);
          _tickService.updateBpm(updated);
          seq.bpm = updated;
          _publishMeta(); // live BPM
        }
      });
    }

    if (seq.bars.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No bars created in sequencer!')),
      );
      return;
    }

    seq.start(
      bpm: appState.bpm,
      soundOn: appState.soundOn,
    );

    _tickService.start(appState.bpm);

    setState(() => _isRunning = true);
    _installResumer();
    PlaybackCoordinator.instance.activate('sequencer');
  }

  void _stop() {
    _tempoIncSub?.cancel();
    MetronomeSequencerService().stop();
    _tickService.stop();
    setState(() => _isRunning = false);
    _clearResumer();
  }

  void _onDragBpm(int val) {
    val = val.clamp(10, 240);
    final appState = context.read<AppStateService>();
    appState.setBpm(val);
    MetronomeSequencerService().bpm = val;
    if (_isRunning) _tickService.updateBpm(val);
    _publishMeta(); // live BPM even when paused
  }

  void _toggleSound() {
    final appState = context.read<AppStateService>();
    appState.setSoundOn(!appState.soundOn);
    MetronomeSequencerService().setSoundOn(appState.soundOn);
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
      final filtered =
          intervals.where((ms) => (ms - last).abs() <= dev).toList();
      final avg = filtered.isNotEmpty
          ? filtered.reduce((a, b) => a + b) ~/ filtered.length
          : last;
      final newBpm = (60000 / avg).clamp(10, 240).round();
      appState.setBpm(newBpm);
      MetronomeSequencerService().bpm = newBpm;
      if (_isRunning) _tickService.updateBpm(newBpm);
      _publishMeta(); // live BPM
    }

    if (appState.soundOn) {
      AudioService.playClick();
    }
  }

  Future<void> _openSettings() async {
    _stop();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const SequencerSettingsModal(),
    );
  }

  @override
  void dispose() {
    _tempoIncSub?.cancel();
    _tickService.stop();
    MetronomeSequencerService().stop();
    _clearResumer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateService>();
    final wheelHeight = MediaQuery.of(context).size.width * 0.8;

    return SafeArea(
      child: Column(
        children: [
          // 1) Sequencer bars + editor
          Expanded(child: MetronomeSequencerWidget(onStop: _stop)),

          // 2) BPM wheel picker
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

          // 3) Sound / Play / Tap‐Tempo / Settings controls
          SizedBox(
            height: 100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  iconSize: 40,
                  icon: Icon(
                    appState.soundOn ? Icons.volume_up : Icons.volume_off,
                  ),
                  onPressed: _toggleSound,
                ),
                IconButton(
                  iconSize: 40,
                  icon: Icon(
                    _isRunning ? Icons.stop_circle : Icons.play_circle,
                  ),
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