import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_state_service.dart';
import '../services/tick_service.dart';
import '../services/audio_service.dart';
import '../widgets/wheel_picker.dart';
import '../widgets/polyrhythm_settings_modal.dart';

class PolyrhythmScreen extends StatefulWidget {
  final bool active;
  const PolyrhythmScreen({super.key, required this.active});

  @override
  State<PolyrhythmScreen> createState() => _PolyrhythmScreenState();
}

class _PolyrhythmScreenState extends State<PolyrhythmScreen> {
  late int _bpm;
  bool _isRunning = false;
  bool _polyAccented = false;
  int _polyP = 4, _polyQ = 1;

  final TickService _tickService = TickService();
  StreamSubscription<void>? _polySub, _tempoIncSub;
  int _tempoIncCounter = 0;

  final List<DateTime> _tapTimes = [];
  Timer? _tapResetTimer;
  DateTime? _tapSuppressionUntil;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppStateService>();
    _bpm = app.bpm;
    app.addListener(_onGlobalBpmChanged);
    _loadAccentPref();
  }

  void _onGlobalBpmChanged() {
    final newBpm = context.read<AppStateService>().bpm;
    setState(() {
      _bpm = newBpm;
      if (_isRunning) _tickService.updateBpm(_bpm);
    });
  }

  Future<void> _loadAccentPref() async {
    final p = await SharedPreferences.getInstance();
    setState(() => _polyAccented = p.getBool('polyrhythm_accented') ?? false);
  }

  @override
  void didUpdateWidget(covariant PolyrhythmScreen old) {
    super.didUpdateWidget(old);
    if (old.active && !widget.active && _isRunning) _stop();
  }

  @override
  void dispose() {
    _polySub?.cancel();
    _tempoIncSub?.cancel();
    _tickService.stop();
    context.read<AppStateService>().removeListener(_onGlobalBpmChanged);
    super.dispose();
  }

  void _start() {
    final app = context.read<AppStateService>();
    _polySub?.cancel();
    _tempoIncSub?.cancel();
    _tempoIncCounter = 0;

    // Start main crotchet tick sequence (right-hand number _polyQ)
    _tickService.start(_bpm);

    // Main crotchet clicks (right number)
    _tempoIncSub = _tickService.tickStream.listen((_) {
      if (_tapSuppressionUntil != null &&
          DateTime.now().isBefore(_tapSuppressionUntil!)) {
        return;
      }

      AudioService.playClick();  // Regular click for _polyQ (right number)

      // Global tempo increase logic
      if (app.tempoIncreaseEnabled) {
        _tempoIncCounter++;
        if (_tempoIncCounter >= app.tempoIncreaseY) {
          _tempoIncCounter = 0;
          final newBpm = (_bpm + app.tempoIncreaseX).clamp(10, 240);
          context.read<AppStateService>().setBpm(newBpm);
        }
      }
    });

    // Polyrhythm clicks (left number _polyP)
    final totalPolyClicks = _polyP;
    final beatsPerCycle = _polyQ;

    // Duration for each polyrhythm cycle
    final cycleDurationMs = (60000 / _bpm) * beatsPerCycle;

    // Interval between polyrhythm clicks
    final polyClickIntervalMs = cycleDurationMs / totalPolyClicks;

    // Sub-click stream (left number _polyP)
    _polySub = Stream.periodic(
      Duration(milliseconds: polyClickIntervalMs.round()),
    ).listen((_) {
      if (_tapSuppressionUntil != null &&
          DateTime.now().isBefore(_tapSuppressionUntil!)) {
        return;
      }

      // Use accented click if enabled (LEFT number)
      if (_polyAccented) {
        AudioService.playAccentClick();
      } else {
        AudioService.playClick();
      }
    });

    setState(() => _isRunning = true);
  }

  void _stop() {
    _tickService.stop();
    _polySub?.cancel();
    _tempoIncSub?.cancel();
    setState(() => _isRunning = false);
  }

  void _onDragBpm(int v) => context.read<AppStateService>().setBpm(v);
  
  void _tapTempo() {
    final now = DateTime.now();
    _tapTimes.add(now);
    _tapResetTimer?.cancel();
    _tapResetTimer = Timer(const Duration(seconds: 6), () => _tapTimes.clear());
    if (_tapTimes.length > 4) _tapTimes.removeAt(0);

    if (_tapTimes.length >= 2) {
      final intervals = <int>[];
      for (var i = 1; i < _tapTimes.length; i++) {
        intervals.add(_tapTimes[i]
            .difference(_tapTimes[i - 1])
            .inMilliseconds);
      }
      final last = intervals.last;
      final dev = (last * 0.2).round();
      final filtered =
          intervals.where((ms) => (ms - last).abs() <= dev);
      final avg = filtered.isNotEmpty
          ? filtered.reduce((a, b) => a + b) ~/ filtered.length
          : last;
      context.read<AppStateService>().setBpm(
            (60000 / avg).clamp(10, 240).round(),
          );
    }

    AudioService.playClick();
    _tapSuppressionUntil = now.add(
      Duration(milliseconds: (60000 / _bpm * 1.5).round()),
    );
  }

  Future<void> _openSettings() async {
    _stop();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PolyrhythmSettingsModal(),
    );
    await _loadAccentPref();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppStateService>();
    final w = MediaQuery.of(context).size.width;
    final wheelH = w * 0.8;
    final boxSize = (w - 48) / 2;

    return SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const SizedBox(height: 24),
          SizedBox(
            height: boxSize,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _cupertinoPicker(_polyP, (v) => setState(() => _polyP = v), boxSize),
                const SizedBox(width: 24),
                _cupertinoPicker(_polyQ, (v) => setState(() => _polyQ = v), boxSize),
              ],
            ),
          ),
          const SizedBox(height: 56),
          SizedBox(
            height: wheelH,
            child: WheelPicker(
              initialBpm: _bpm,
              minBpm: 10,
              maxBpm: 240,
              wheelSize: wheelH,
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
                  icon: Icon(app.soundOn ? Icons.volume_up : Icons.volume_off),
                  onPressed: () => app.setSoundOn(!app.soundOn),
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

  Widget _cupertinoPicker(int val, void Function(int) onChanged, double size) {
    final itemExtent = size / 2;
    return Container(
      width: size,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.tealAccent, width: 3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: CupertinoPicker(
          scrollController: FixedExtentScrollController(initialItem: val - 1),
          itemExtent: itemExtent,
          diameterRatio: 1.5,
          selectionOverlay: const SizedBox(),
          onSelectedItemChanged: (idx) => onChanged(idx + 1),
          children: List.generate(
            10,
            (i) => Center(
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  fontSize: itemExtent * 0.7,
                  fontWeight: FontWeight.bold,
                  color: (i + 1) == val ? Colors.white : Colors.white70,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}