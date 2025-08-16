// File: lib/screens/polyrhythm_screen.dart
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_state_service.dart';
import '../services/audio_service.dart';
import '../services/tick_service.dart';
import '../services/system_media_handler.dart'; // <-- added
import '../widgets/bouncing_dot.dart';            // has inlined PolyrhythmVizBus
import '../widgets/wheel_picker.dart';
import '../widgets/polyrhythm_settings_modal.dart';

class PolyrhythmScreen extends StatefulWidget {
  final bool active;
  const PolyrhythmScreen({super.key, required this.active});

  @override
  State<PolyrhythmScreen> createState() => _PolyrhythmScreenState();
}

class _PolyrhythmScreenState extends State<PolyrhythmScreen> {
  bool _isRunning = false;

  int _polyP = 4; // left voice: p-in-q
  int _polyQ = 3; // right voice & base beat: once per beat

  bool _polyAccented = false; // accent left voice (from settings modal)
  bool _leftMuted = false;    // per-voice mutes (UI icons + number tap)
  bool _rightMuted = false;

  final TickService _tick = TickService();
  StreamSubscription<void>? _subTickSub;
  StreamSubscription<void>? _tempoIncSub; // <-- tempo increase

  // --- Subdivision math (q is the base beat) ---
  int _cycleN = 1;     // N = lcm(_polyP, _polyQ)
  int _subPerBeat = 1; // N / q
  int _leftStep = 1;   // N / p
  int _rightStep = 1;  // N / q
  int _cycleIndex = 0; // 0..N-1

  // Tap tempo
  final List<DateTime> _tapTimes = [];
  Timer? _tapResetTimer;
  DateTime? _tapSuppressionUntil;

  void _publishMeta() {
    final bpm = context.read<AppStateService>().bpm;
    SystemMediaHandler.last?.setNowPlaying(
      title: 'Polyrhythm $_polyP:$_polyQ',
      subtitle: '$bpm BPM',
    );
  }

  @override
  void initState() {
    super.initState();
    _loadAccentPref();
    _recomputeGrid(); // based on initial p/q
  }

  Future<void> _loadAccentPref() async {
    final p = await SharedPreferences.getInstance();
    setState(() => _polyAccented = p.getBool('polyrhythm_accented') ?? false);
  }

  Future<void> _reloadSettingsFromPrefs() => _loadAccentPref();

  @override
  void didUpdateWidget(covariant PolyrhythmScreen old) {
    super.didUpdateWidget(old);
    if (!old.active && widget.active) {
      PolyrhythmVizBus.instance.setEnabled(true);
      PolyrhythmVizBus.instance.setMuted(left: _leftMuted, right: _rightMuted);
      _publishMeta(); // update CC when entering tab
    }
    if (old.active && !widget.active) {
      _stop();
      PolyrhythmVizBus.instance.setEnabled(false);
    }
  }

  @override
  void dispose() {
    _tempoIncSub?.cancel();
    _subTickSub?.cancel();
    _tick.stop();
    PolyrhythmVizBus.instance.setEnabled(false);
    _tapResetTimer?.cancel();
    super.dispose();
  }

  int _gcd(int a, int b) {
    while (b != 0) {
      final t = b;
      b = a % b;
      a = t;
    }
    return a.abs();
  }

  int _lcm(int a, int b) => (a ~/ _gcd(a, b)) * b;

  void _recomputeGrid() {
    _cycleN     = _lcm(_polyP, _polyQ);
    _subPerBeat = (_cycleN ~/ _polyQ);
    _leftStep   = (_cycleN ~/ _polyP);
    _rightStep  = (_cycleN ~/ _polyQ);
    _cycleIndex = 0;
  }

  void _bindTempoIncrease() {
    _tempoIncSub?.cancel();
    final app = context.read<AppStateService>();
    if (!app.tempoIncreaseEnabled) return;

    int counter = 0;
    _tempoIncSub = _tick.tickStream.skip(1).listen((_) {
      counter++;
      if (counter >= app.tempoIncreaseY) {
        counter = 0;
        final newBpm = (app.bpm + app.tempoIncreaseX).clamp(10, 240);
        app.setBpm(newBpm);
        _tick.updateBpm(newBpm);
        _publishMeta(); // live BPM
      }
    });
  }

  void _start() {
    final app = context.read<AppStateService>();
    _recomputeGrid();

    _tick.start(app.bpm, unitFraction: 1.0 / _subPerBeat);

    _subTickSub?.cancel();
    _subTickSub = _tick.subTickStream.listen((_) => _advanceOneSub());

    _bindTempoIncrease();

    setState(() => _isRunning = true);
    PolyrhythmVizBus.instance.setEnabled(true);
    PolyrhythmVizBus.instance.setMuted(left: _leftMuted, right: _rightMuted);
    _publishMeta();
  }

  void _stop() {
    _tempoIncSub?.cancel();
    _subTickSub?.cancel();
    _tick.stop();
    if (mounted) setState(() => _isRunning = false);
  }

  void _advanceOneSub() {
    final app = context.read<AppStateService>();
    final now = DateTime.now();
    final suppress = _tapSuppressionUntil != null && now.isBefore(_tapSuppressionUntil!);

    final leftHit  = (_cycleIndex % _leftStep  == 0);
    final rightHit = (_cycleIndex % _rightStep == 0);

    if (leftHit)  PolyrhythmVizBus.instance.emitLeft();
    if (rightHit) PolyrhythmVizBus.instance.emitRight();

    if (!suppress && app.soundOn) {
      if (leftHit && !_leftMuted) {
        _polyAccented ? AudioService.playAccentClick() : AudioService.playClick();
      }
      if (rightHit && !_rightMuted) {
        AudioService.playClick();
      }
    }

    _cycleIndex++;
    if (_cycleIndex >= _cycleN) _cycleIndex = 0;
  }

  // ───────────────────── Interactions ─────────────────────
  void _onDragBpm(int v) {
    final bpm = v.clamp(10, 240);
    context.read<AppStateService>().setBpm(bpm);
    if (_isRunning) _tick.updateBpm(bpm);
    _publishMeta(); // live BPM
  }

  void _togglePlay() => _isRunning ? _stop() : _start();

  void _toggleGlobalMute() {
    final app = context.read<AppStateService>();
    app.setSoundOn(!app.soundOn);
  }

  void _toggleLeftMute() {
    setState(() => _leftMuted = !_leftMuted);
    PolyrhythmVizBus.instance.setMuted(left: _leftMuted);
  }

  void _toggleRightMute() {
    setState(() => _rightMuted = !_rightMuted);
    PolyrhythmVizBus.instance.setMuted(right: _rightMuted);
  }

  void _setP(int v) {
    setState(() => _polyP = v);
    _publishMeta(); // title “Polyrhythm P:Q”
    if (_isRunning) {
      final bpm = context.read<AppStateService>().bpm;
      _recomputeGrid();
      _tick.start(bpm, unitFraction: 1.0 / _subPerBeat);
      _subTickSub?.cancel();
      _subTickSub = _tick.subTickStream.listen((_) => _advanceOneSub());
      _bindTempoIncrease();
    }
  }

  void _setQ(int v) {
    setState(() => _polyQ = v);
    _publishMeta(); // title “Polyrhythm P:Q”
    if (_isRunning) {
      final bpm = context.read<AppStateService>().bpm;
      _recomputeGrid();
      _tick.start(bpm, unitFraction: 1.0 / _subPerBeat);
      _subTickSub?.cancel();
      _subTickSub = _tick.subTickStream.listen((_) => _advanceOneSub());
      _bindTempoIncrease();
    }
  }

  void _tapTempo() {
    final app = context.read<AppStateService>();
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
      app.setBpm(newBpm);
      if (_isRunning) _tick.updateBpm(newBpm);
      _publishMeta(); // live BPM
    }

    if (app.soundOn) {
      AudioService.playClick();
      _tapSuppressionUntil = now.add(
        Duration(milliseconds: (60000 / context.read<AppStateService>().bpm * 1.5).round()),
      );
    }
  }

  Future<void> _openSettings() async {
    final wasRunning = _isRunning;
    if (wasRunning) _stop();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PolyrhythmSettingsModal(),
    );
    await _reloadSettingsFromPrefs();
  }

  // ───────────────────── UI ─────────────────────
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppStateService>();
    final w = MediaQuery.of(context).size.width;
    final wheelH = w * 0.8;
    final boxSize = (w - 48) / 2;

    final leftBorder  = _leftMuted  ? Colors.grey.shade700 : Colors.tealAccent;
    final rightBorder = _rightMuted ? Colors.grey.shade700 : Colors.tealAccent;

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
                _pickerBox(
                  label: 'P',
                  muted: _leftMuted,
                  borderColor: leftBorder,
                  size: boxSize,
                  onTapNumber: _toggleLeftMute,
                  muteIconOnPressed: _toggleLeftMute,
                  child: _cupertinoPicker(
                    val: _polyP,
                    onChanged: _setP,
                    size: boxSize,
                    muted: _leftMuted,
                  ),
                ),
                const SizedBox(width: 24),
                _pickerBox(
                  label: 'Q',
                  muted: _rightMuted,
                  borderColor: rightBorder,
                  size: boxSize,
                  onTapNumber: _toggleRightMute,
                  muteIconOnPressed: _toggleRightMute,
                  child: _cupertinoPicker(
                    val: _polyQ,
                    onChanged: _setQ,
                    size: boxSize,
                    muted: _rightMuted,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 56),

          SizedBox(
            height: wheelH,
            child: WheelPicker(
              initialBpm: app.bpm,
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
                  onPressed: _toggleGlobalMute,
                ),
                IconButton(
                  iconSize: 40,
                  icon: Icon(_isRunning ? Icons.stop_circle : Icons.play_circle),
                  onPressed: _togglePlay,
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

  Widget _pickerBox({
    required String label,
    required bool muted,
    required Color borderColor,
    required double size,
    required VoidCallback onTapNumber,
    required VoidCallback muteIconOnPressed,
    required Widget child,
  }) {
    return Container(
      width: size,
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Positioned.fill(child: child),
            Positioned(
              right: 6,
              top: 6,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 28,
                splashRadius: 22,
                color: muted ? Colors.white38 : Colors.tealAccent,
                icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
                onPressed: muteIconOnPressed,
                tooltip: muted ? 'Unmute $label' : 'Mute $label',
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cupertinoPicker({
    required int val,
    required void Function(int) onChanged,
    required double size,
    bool muted = false,
  }) {
    final itemExtent = size / 2;
    return CupertinoPicker(
      scrollController: FixedExtentScrollController(initialItem: val - 1),
      itemExtent: itemExtent,
      diameterRatio: 1.5,
      selectionOverlay: const SizedBox(),
      onSelectedItemChanged: (idx) => onChanged(idx + 1),
      children: List.generate(10, (i) {
        final selected = (i + 1) == val;
        final baseColor = selected ? Colors.white : Colors.white70;
        final color = muted ? Colors.white38 : baseColor;
        return Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (onChanged == _setP) {
                _toggleLeftMute();
              } else if (onChanged == _setQ) {
                _toggleRightMute();
              }
            },
            child: Text(
              '${i + 1}',
              style: TextStyle(
                fontSize: itemExtent * 0.7,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        );
      }),
    );
  }
}