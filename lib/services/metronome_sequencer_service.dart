// ─── metronome_sequencer_service.dart ─────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/audio_service.dart';
import '../services/tick_service.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:ui';

// ─── ENUMS AND EXTENSIONS ─────────────────────────────────────────────

enum RhythmType {
  minim,
  crotchet,
  quaver,
  semiquaver,
  crotchetTriplet,
  quaverTriplet,
  semiquaverTriplet
}

extension RhythmTypeExtension on RhythmType {
  String get assetPath {
    switch (this) {
      case RhythmType.minim:
        return 'assets/notes/minim.svg';
      case RhythmType.crotchet:
        return 'assets/notes/crotchet.svg';
      case RhythmType.quaver:
        return 'assets/notes/quaver.svg';
      case RhythmType.semiquaver:
        return 'assets/notes/semiquaver.svg';
      default:
        return ''; // Triplets not yet implemented as SVG
    }
  }

  bool get hasSvg => assetPath.isNotEmpty;

  double get durationInBeats {
    switch (this) {
      case RhythmType.minim:
        return 2;
      case RhythmType.crotchet:
        return 1;
      case RhythmType.quaver:
        return 0.5;
      case RhythmType.semiquaver:
        return 0.25;
      case RhythmType.crotchetTriplet:
        return 2 / 3;
      case RhythmType.quaverTriplet:
        return 1 / 3;
      case RhythmType.semiquaverTriplet:
        return 1 / 6;
    }
  }
}

// ─── DATA MODELS ───────────────────────────────────────────────────────

class TimeSignature {
  final int beatsPerBar;
  final int noteValue;

  TimeSignature({required this.beatsPerBar, required this.noteValue});

  Map<String, dynamic> toJson() => {
        'beatsPerBar': beatsPerBar,
        'noteValue': noteValue,
      };

  factory TimeSignature.fromJson(Map<String, dynamic> json) => TimeSignature(
        beatsPerBar: json['beatsPerBar'],
        noteValue: json['noteValue'],
      );
}

class MetronomeStep {
  RhythmType rhythm;
  bool isMuted;
  bool isAccented;

  MetronomeStep({required this.rhythm, this.isMuted = false, this.isAccented = false});

  Map<String, dynamic> toJson() => {
        'rhythm': rhythm.name,
        'isMuted': isMuted,
        'isAccented': isAccented,
      };

  factory MetronomeStep.fromJson(Map<String, dynamic> json) => MetronomeStep(
        rhythm: RhythmType.values.firstWhere((e) => e.name == json['rhythm']),
        isMuted: json['isMuted'] ?? false,
        isAccented: json['isAccented'] ?? false,
      );
}

class MetronomeBar {
  TimeSignature timeSig;
  List<MetronomeStep> steps;

  MetronomeBar({required this.timeSig, required this.steps});

  Map<String, dynamic> toJson() => {
        'timeSig': timeSig.toJson(),
        'steps': steps.map((e) => e.toJson()).toList(),
      };

  factory MetronomeBar.fromJson(Map<String, dynamic> json) => MetronomeBar(
        timeSig: TimeSignature.fromJson(json['timeSig']),
        steps: (json['steps'] as List)
            .map((e) => MetronomeStep.fromJson(e))
            .toList(),
      );

  static MetronomeBar crotchets(int count) => MetronomeBar(
        timeSig: TimeSignature(beatsPerBar: count, noteValue: 4),
        steps: List.generate(count, (_) => MetronomeStep(rhythm: RhythmType.crotchet)),
      );

  void replaceStepAt(int index, RhythmType newRhythm) {
    // total bar length in crotchet‐beats (so 7/8 → 3.5, 3/8 → 1.5, 4/4 → 4.0, etc.)
    final double barMax =
      timeSig.beatsPerBar * (4.0 / timeSig.noteValue);

    // Compute start beat of the target step
    double startBeat = 0;
    for (int i = 0; i < index; i++) {
      startBeat += steps[i].rhythm.durationInBeats;
    }

    double newDur = newRhythm.durationInBeats;
    double endBeat = startBeat + newDur;

    // Trim inserted rhythm duration if it would exceed bar
    if (endBeat > barMax) {
      double available = barMax - startBeat;
      if (available >= 0.25) {
        final fillers = [RhythmType.semiquaver, RhythmType.quaver, RhythmType.crotchet];
        List<RhythmType> fill = [];

        for (final r in fillers.reversed) {
          while (r.durationInBeats <= available + 0.0001) {
            fill.insert(0, r); // insert at front so last rhythm lands later
            available -= r.durationInBeats;
          }
        }

        // Clean up right of insertion point
        double removed = 0;
        while (index < steps.length && (startBeat + removed) < barMax) {
          removed += steps[index].rhythm.durationInBeats;
          steps.removeAt(index);
        }

        steps.insertAll(index, fill.map((r) => MetronomeStep(rhythm: r)));
      }

      return; // Done – inserted trimmed version
    }

    // Otherwise, rhythm fits fully – proceed as usual

    // Remove overlapping steps to the right
    double removed = 0;
    while (index < steps.length && (startBeat + removed) < endBeat) {
      removed += steps[index].rhythm.durationInBeats;
      steps.removeAt(index);
    }

    // Insert the new rhythm
    steps.insert(index, MetronomeStep(rhythm: newRhythm));

    // Recalculate total duration
    double total = steps.fold(0.0, (sum, s) => sum + s.rhythm.durationInBeats);
    double fillRemaining = barMax - total;

    if (fillRemaining > 0.0001) {
      final fillers = [RhythmType.semiquaver, RhythmType.quaver, RhythmType.crotchet];
      List<RhythmType> fillSequence = [];

      for (final r in fillers.reversed) {
        while (r.durationInBeats <= fillRemaining + 0.0001) {
          fillSequence.insert(0, r); // insert at front to place smaller first, larger later
          fillRemaining -= r.durationInBeats;
        }
      }

      steps.insertAll(index + 1, fillSequence.map((r) => MetronomeStep(rhythm: r)));
    }

    // Final floating point trim if needed
    total = steps.fold(0.0, (sum, s) => sum + s.rhythm.durationInBeats);
    if (total > barMax + 0.0001) {
      double excess = total - barMax;
      for (int i = steps.length - 1; i >= 0 && excess > 0.0001; i--) {
        double dur = steps[i].rhythm.durationInBeats;
        if (dur <= excess + 0.0001) {
          steps.removeAt(i);
          excess -= dur;
        }
      }
    }
  }
}

// ─── SERVICE ───────────────────────────────────────────────────────────

class MetronomeSequencerService {
  static final MetronomeSequencerService _instance = MetronomeSequencerService._internal();
  factory MetronomeSequencerService() => _instance;
  MetronomeSequencerService._internal();

  final List<MetronomeBar> _bars = [];
  int _currentBarIndex = 0;
  int _currentStepIndex = 0;
  bool isRunning = false;
  bool _soundOn = true;
  double _swingFraction = 0.0;   
  double _shuffleFraction = 0.0;
  late double _subTickIntervalMs;

  final StreamController<void> _updateController = StreamController.broadcast();
  Stream<void> get updateStream => _updateController.stream;

  /// subscription to sub-beat ticks
  StreamSubscription<void>? _subBeatSub;
  int _currentTick = 0;
  late List<_StepTime> _schedule;
  late int _totalTicksPerCycle;
  /// LCM of all rhythm‐denominators (1,2,3,4,6) = 12
  static const int ticksPerBeat = 12;
  static const double unitFraction = 1 / ticksPerBeat;
  final StreamController<void> _barEndController = StreamController.broadcast();
  Stream<void> get barEndStream => _barEndController.stream;
  int _bpm = 60;
  final ValueNotifier<int> bpmNotifier = ValueNotifier<int>(60);

  /// The sequencer’s saved tempo
  int get bpm => _bpm;
  set bpm(int v) {
    _bpm = v;
    bpmNotifier.value = v;
    if (isRunning) {
      _subTickIntervalMs = 60000 / _bpm * unitFraction;
      TickService().updateBpm(_bpm);
    }
  }

  static const _currentKey = 'sequencer_current_state';

  /// Silently persist the live bars + bpm + swing/shuffle to a hidden prefs key.
  Future<void> saveCurrentState() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'bpm': _bpm,
      'bars': _bars.map((b) => b.toJson()).toList(),
      'swing': (_swingFraction * 100).round(),
      'shuffle': (_shuffleFraction * 100).round(),
    };
    await prefs.setString(_currentKey, jsonEncode(payload));
  }

  /// Try to load the hidden “current” sequencer if present.
  Future<bool> loadCurrentState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_currentKey);
    if (raw == null) return false;
    final Map<String, dynamic> decoded = jsonDecode(raw);
    bpm = decoded['bpm'] as int? ?? 60;
    _bars
      ..clear()
      ..addAll((decoded['bars'] as List)
        .map((e) => MetronomeBar.fromJson(e as Map<String, dynamic>)));
    // restore swing & shuffle values
    _swingFraction   = ((decoded['swing'] as int?)   ?? 0) / 100.0;
    _shuffleFraction = ((decoded['shuffle'] as int?) ?? 0) / 100.0;
    reset();
    return true;
  }

  /// Recompute the internal tick‐schedule on the fly
  /// Call this after any add/remove/replaceStepAt so the live sequencer
  /// picks up your edits immediately (without stop/start).
  void rebuildSchedule() {
    _schedule = _buildSchedule();
    // Clamp current pointer into new cycle length
    if (_currentTick >= _totalTicksPerCycle && _totalTicksPerCycle > 0) {
      _currentTick = _currentTick % _totalTicksPerCycle;
    }
  }

  void init(List<MetronomeBar> initialBars) {
    _bars..clear()..addAll(initialBars);
    reset();
  }

  void initDefault() {
    init([MetronomeBar.crotchets(4)]);
    bpm = 60;
  }

  Future<bool> loadMostRecent() async {
    if (await loadCurrentState()) return true;
    final saved = await listSavedSequences();
    if (saved.isNotEmpty) {
      initDefault();
    }
    return false;
  }

  void setSoundOn(bool enabled) {
    _soundOn = enabled;
  }

  Future<void> start({ required int bpm, required bool soundOn }) async {
    if (_bars.isEmpty || isRunning) return;
    stop();
    isRunning = true;
    _soundOn = soundOn;

    // 1) compute sub-tick interval from BPM
    _subTickIntervalMs = 60000 / bpm * unitFraction;

    // 2) load user swing/shuffle at start
    final prefs = await SharedPreferences.getInstance();
    _swingFraction   = (prefs.getDouble('swing')   ?? 0.0) / 100.0;
    _shuffleFraction = (prefs.getDouble('shuffle') ?? 0.0) / 100.0;

    // 1) Build a tick‐based schedule (with swing/shuffle flags)
    _schedule = _buildSchedule();
    _currentTick = 0;

    // 2) Kick off TickService at [unitFraction] of a beat
    final ts = TickService();
    ts.start(bpm, unitFraction: unitFraction);

    // 3) Listen to each sub‐beat tick
    _subBeatSub = ts.subTickStream.listen((_) => _onTick());
  }

  void stop() {
    _subBeatSub?.cancel();
    _subBeatSub = null;
    TickService().stop();
    isRunning = false;
  }
  /// Recomputes schedule in ticks
  List<_StepTime> _buildSchedule() {
    final out = <_StepTime>[];
    int cursor = 0;
    for (int b = 0; b < _bars.length; b++) {
      final bar = _bars[b];
      // 1) gather base times
      final List<_StepTime> barTimes = [];
      var local = cursor;
      for (int s = 0; s < bar.steps.length; s++) {
        final step = bar.steps[s];
        final len = (step.rhythm.durationInBeats * ticksPerBeat).round();
        barTimes.add(_StepTime(
          b, s, local, len,
          step.isMuted, step.isAccented,
          false, false
        ));
        local += len;
      }
      // 2) mark swing on odd quaver pairs (6‑tick)
      for (int i = 0; i < barTimes.length - 1; ) {
        if (barTimes[i].durationTicks == 6 && barTimes[i+1].durationTicks == 6) {
          barTimes[i+1] = barTimes[i+1].copyWith(swingStep: true);
          i += 2;
        } else {
          i += 1;
        }
      }
      // 3) mark shuffle on odd semiquaver pairs (3‑tick)
      for (int i = 0; i < barTimes.length - 1; ) {
        if (barTimes[i].durationTicks == 3 && barTimes[i+1].durationTicks == 3) {
          barTimes[i+1] = barTimes[i+1].copyWith(shuffleStep: true);
          i += 2;
        } else {
          i += 1;
        }
      }
      out.addAll(barTimes);
      cursor = local;
    }
    _totalTicksPerCycle = cursor;
    return out;
  }

  /// Called on every sub‐beat tick
  void _onTick() {
    // wrap around at end of cycle
    if (_currentTick >= _totalTicksPerCycle) {
      _currentTick = 0;
      _barEndController.add(null);  // signal end of cycle
    }

    for (final step in _schedule) {
      if (step.startTick == _currentTick) {
        // update indices
        _currentBarIndex = step.barIndex;
        _currentStepIndex = step.stepIndex;

        // fetch the live MetronomeStep so toggles take effect immediately
        final liveStep = _bars[step.barIndex].steps[step.stepIndex];

        // compute swing/shuffle delay fraction
        final delayFrac = step.swingStep   ? _swingFraction
                        : step.shuffleStep ? _shuffleFraction
                        : 0.0;
        // convert to milliseconds
        final stepMs = (_subTickIntervalMs * step.durationTicks).round();
        final extra  = (stepMs * delayFrac).round();

        if (delayFrac > 0) {
          Future.delayed(Duration(milliseconds: extra), () {
            // play click (accented or not)
            if (!liveStep.isMuted && _soundOn) {
              if (liveStep.isAccented) AudioService.playAccentClick();
              else                     AudioService.playClick();
            }
            // now trigger the UI update in sync with the audio
            _updateController.add(null);
          });
        } else {
          // no delay: play & highlight immediately
          if (!liveStep.isMuted && _soundOn) {
            if (liveStep.isAccented) AudioService.playAccentClick();
            else                     AudioService.playClick();
          }
          _updateController.add(null);
        }
      }
    }
    _currentTick++;
  }

  void reset() {
    _currentBarIndex = 0;
    _currentStepIndex = 0;
    _updateController.add(null);
  }

  /// Jump playback start position (UI + next play)
  void jumpTo(int barIdx, int stepIdx) {
    _currentBarIndex = barIdx;
    _currentStepIndex = stepIdx;
    _updateController.add(null);
  }

  List<MetronomeBar> get bars => _bars;
  int get currentBarIndex => _currentBarIndex;
  int get currentStepIndex => _currentStepIndex;

  Future<void> saveToPrefs(String label) async {
    final prefs = await SharedPreferences.getInstance();
    final swing   = (prefs.getDouble('swing')   ?? 0.0).round();
    final shuffle = (prefs.getDouble('shuffle') ?? 0.0).round();
    final payload = {
      'bpm': _bpm,
      'bars': _bars.map((b) => b.toJson()).toList(),
      'swing': swing,
      'shuffle': shuffle,
    };
    final jsonStr = jsonEncode(payload);
    await prefs.setString('sequencer_metronome_$label', jsonStr);
  }

  Future<bool> loadFromPrefs(String label) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('sequencer_metronome_$label');
    if (jsonStr == null) return false;

    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    // restore BPM
    bpm = decoded['bpm'] as int? ?? 60;
    // restore bars
    final barsJson = decoded['bars'] as List<dynamic>;
    _bars
      ..clear()
      ..addAll(barsJson.map((e) => MetronomeBar.fromJson(e as Map<String, dynamic>)));
    // restore swing & shuffle
    _swingFraction   = ((decoded['swing'] as int?)   ?? 0) / 100.0;
    _shuffleFraction = ((decoded['shuffle'] as int?) ?? 0) / 100.0;
    reset();
    return true;
  }

  Future<List<String>> listSavedSequences() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs
        .getKeys()
        .where((k) => k.startsWith('sequencer_metronome_'))
        .map((k) => k.replaceFirst('sequencer_metronome_', ''))
        .toList();
  }

  Future<void> deleteSequence(String label) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sequencer_metronome_$label');
  }

}

class _StepTime {
  final int barIndex;        // which bar
  final int stepIndex;       // which step in that bar
  final int startTick;       // absolute tick when this step begins
  final int durationTicks;   // how many ticks this step lasts
  final bool isMuted;
  final bool isAccented;
  final bool swingStep;      // flagged in build
  final bool shuffleStep; 

  _StepTime(
    this.barIndex,
    this.stepIndex,
    this.startTick,
    this.durationTicks,
    this.isMuted,
    this.isAccented,
    this.swingStep,
    this.shuffleStep
  );

  _StepTime copyWith({bool? swingStep, bool? shuffleStep}) {
    return _StepTime(
      barIndex, stepIndex, startTick, durationTicks,
      isMuted, isAccented,
      swingStep ?? this.swingStep,
      shuffleStep ?? this.shuffleStep,
    );
  }
}

// ─── UI WIDGETS ─────────────────────────────────────────────────────────

class TimeSignatureWidget extends StatelessWidget {
  final TimeSignature timeSig;
  final Color color;
  final double size;

  /// `size` now drives only the height; width is intrinsic.
  const TimeSignatureWidget(
    this.timeSig, {
    Key? key,
    this.color = Colors.white,
    this.size = 42,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${timeSig.beatsPerBar}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: size * 0.33,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${timeSig.noteValue}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: size * 0.33,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws a vertical line at each beat boundary, and a slightly thicker one at the bar end.
class BeatLinePainter extends CustomPainter {
  final int beatsPerBar;
  final Color lineColor;
  final double lineWidth;
  final double endLineWidth;

  BeatLinePainter({
    required this.beatsPerBar,
    this.lineColor = const Color(0xFF888888),
    this.lineWidth = 1.0,
    this.endLineWidth = 2.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = lineColor;
    final double beatW = size.width / beatsPerBar;

    for (int i = 0; i <= beatsPerBar; i++) {
      paint.strokeWidth = (i == beatsPerBar) ? endLineWidth : lineWidth;
      final x = i * beatW;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant BeatLinePainter old) =>
      old.beatsPerBar != beatsPerBar ||
      old.lineColor != lineColor ||
      old.lineWidth != lineWidth ||
      old.endLineWidth != endLineWidth;
}

class MetronomeSequencerWidget extends StatefulWidget {
  /// Called whenever the sequencer is forced to stop (e.g. when you delete the last bar)
  final VoidCallback? onStop;

  const MetronomeSequencerWidget({
    super.key,
    this.onStop,
  });

  @override
  State<MetronomeSequencerWidget> createState() => MetronomeSequencerWidgetState();
}

class MetronomeSequencerWidgetState extends State<MetronomeSequencerWidget> with SingleTickerProviderStateMixin {
  final sequencer = MetronomeSequencerService();
  StreamSubscription<void>? _subscription;
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  final Map<int, GlobalKey> _barKeys = {};
  final ScrollController _scrollController = ScrollController();
  int? _selectedBarIndex;
  int? _selectedStepIndex;
  bool _popupVisible = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.1)
        .chain(CurveTween(curve: Curves.easeOutCubic))
        .animate(_animController);

    _subscription = sequencer.updateStream.listen((_) {
      if (!mounted) return;
      // clamp selection if new sequence is shorter than before
      setState(() {
        if (_selectedBarIndex != null && _selectedBarIndex! >= sequencer.bars.length) {
          _selectedBarIndex = null;
          _selectedStepIndex = null;
          _popupVisible = false;
        } else if (_selectedBarIndex != null &&
                   _selectedStepIndex != null &&
                   _selectedStepIndex! >= sequencer.bars[_selectedBarIndex!].steps.length) {
          _selectedStepIndex = null;
          _popupVisible = false;
        }
      });
      _animController.forward(from: 0);
      _scrollToCurrentBar();
      setState(() {});
    });
  }

  void _scrollToCurrentBar() {
    final key = _barKeys[sequencer.currentBarIndex];
    if (key == null) return;
    final ctx = key.currentContext;
    if (ctx == null) return;

    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      alignment: 0.1, // show near top of viewport
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _selectStep(int barIndex, int stepIndex) {
    // 1) update UI selection
    setState(() {
      _selectedBarIndex = barIndex;
      _selectedStepIndex = stepIndex;
      _popupVisible       = true;
    });
    // 2) then cue the service
    if (!sequencer.isRunning) {
      sequencer.jumpTo(barIndex, stepIndex);
    }
  }

  void closePopup() {
    _closePopup();
  }

  void _closePopup() {
    setState(() {
      _popupVisible     = false;
      _selectedBarIndex = null;
      _selectedStepIndex= null;
    });
    // if the sequencer is stopped, jump the play‐accent to 0/0
    if (!sequencer.isRunning) {
      sequencer.jumpTo(0, 0);
    }
  }

  void _showAddBarPopup(BuildContext context) {
    final options = <Map<String, int>>[
      {'beats': 1, 'note': 4},
      {'beats': 2, 'note': 4},
      {'beats': 3, 'note': 4},
      {'beats': 4, 'note': 4},
      {'beats': 1, 'note': 8},
      {'beats': 2, 'note': 8},
      {'beats': 3, 'note': 8},
      {'beats': 4, 'note': 8},
      {'beats': 5, 'note': 8},
      {'beats': 6, 'note': 8},
      {'beats': 7, 'note': 8},
      {'beats': 8, 'note': 8},
    ];

    showModalBottomSheet(
      context: context,
      builder: (_) {
        return Container(
          color: Colors.black,
          padding: const EdgeInsets.all(16),
          child: GridView.count(
            crossAxisCount: 4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
            shrinkWrap: true,
            children: options.map((opt) {
              final beats = opt['beats']!;
              final note  = opt['note']!;
              final ts    = TimeSignature(beatsPerBar: beats, noteValue: note);

              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: () {
                  final newBar = MetronomeBar(
                    timeSig: ts,
                    steps: List.generate(beats, (_) {
                      return MetronomeStep(
                        rhythm: note == 4 ? RhythmType.crotchet : RhythmType.quaver
                      );
                    }),
                  );

                  // calculate scroll offset
                  double scrollDelta = 0;
                  if (_selectedBarIndex != null) {
                    final box = (_barKeys[_selectedBarIndex!]!
                                .currentContext!
                                .findRenderObject() as RenderBox);
                    scrollDelta = box.size.height;
                  }

                  setState(() {
                    if (_selectedBarIndex != null) {
                      sequencer.bars.insert(_selectedBarIndex! + 1, newBar);
                      _selectedBarIndex = _selectedBarIndex! + 1;
                    } else {
                      sequencer.bars.add(newBar);
                      _selectedBarIndex = sequencer.bars.length - 1;
                    }
                    sequencer.rebuildSchedule();
                    _selectedStepIndex = 0;
                    _popupVisible      = true;
                    sequencer.jumpTo(_selectedBarIndex!, 0);
                  });

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (scrollDelta > 0) {
                      _scrollController.jumpTo(
                        _scrollController.offset - scrollDelta,
                      );
                    }
                  });

                  Navigator.pop(context);
                },
                child: Center(
                  child: TimeSignatureWidget(
                    ts,
                    color: Colors.black,
                    size: 56,
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

/// --- Helper that builds one bar (notes left-aligned, original selection bracket restored) ---
Widget _buildBar(int barIndex) {
  final bar = sequencer.bars[barIndex];
  if (!_barKeys.containsKey(barIndex)) {
    _barKeys[barIndex] = GlobalKey();
  }
  final barKey = _barKeys[barIndex]!;

  return LayoutBuilder(
    builder: (context, constraints) {
      const double horizontalPadding = 12.0;
      const double sigWidth = 24.0;    // TimeSignatureWidget width
      const double sigSpacing = 8.0;   // gap between signature & notes

      // compute widths
      final double availableWidth = constraints.maxWidth
        - horizontalPadding
        - sigWidth
        - sigSpacing;
      final double beatWidth = availableWidth / 4;
      final double totalBeats = bar.steps.fold(0.0, (sum, s) => sum + s.rhythm.durationInBeats);
      final double barWidth = totalBeats * beatWidth;
      final int subdivisions = bar.timeSig.beatsPerBar;
      final double tickSpacing = beatWidth * (4 / bar.timeSig.noteValue);

      return GestureDetector(
        key: barKey,
        onTap: () => _selectStep(barIndex, _selectedStepIndex ?? 0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: horizontalPadding/2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 1) Time signature, with active scale/color
              AnimatedBuilder(
                animation: _scaleAnim,
                builder: (c, child) {
                  final isActiveBar = barIndex == sequencer.currentBarIndex;
                  final scale = isActiveBar ? _scaleAnim.value : 1.0;
                  final sigColor = isActiveBar ? Colors.tealAccent : Colors.white;
                  return Transform.scale(
                    scale: scale,
                    child: TimeSignatureWidget(bar.timeSig, color: sigColor, size: 42),
                  );
                },
              ),
              const SizedBox(width: sigSpacing),

              // 2) Notes + tick markers inside a fixed width
              SizedBox(
                width: barWidth,
                child: Stack(
                  children: [
                    // a) start barline
                    Positioned(left:0, top:0, child: Container(width:2, height:42, color:Colors.grey.shade600)),
                    // b) subdivision ticks
                    for (int i = 1; i < subdivisions; i++)
                      Positioned(
                        left: i * tickSpacing - 0.5,
                        top: 0,
                        child: Container(width:1, height:12, color: Colors.grey.shade600),
                      ),
                    // c) end barline
                    Positioned(left: barWidth-1, top:0, child: Container(width:2, height:42, color:Colors.grey.shade600)),

                    // d) the actual note icons, left-aligned
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: bar.steps.asMap().entries.map((stepEntry) {
                        final stepIndex = stepEntry.key;
                        final step = stepEntry.value;
                        final isActive = barIndex == sequencer.currentBarIndex
                                         && stepIndex == sequencer.currentStepIndex;
                        final isSelected = _popupVisible
                                          && _selectedBarIndex == barIndex
                                          && _selectedStepIndex == stepIndex;
                        final noteColor = step.isMuted ? Colors.grey.shade800 : Colors.white;

                        return SizedBox(
                          width: step.rhythm.durationInBeats * beatWidth,
                          child: GestureDetector(
                            onTap: () => _selectStep(barIndex, stepIndex),
                            child: AnimatedBuilder(
                              animation: _scaleAnim,
                              builder: (ctx, child) {
                                final scale = isActive ? _scaleAnim.value : 1.0;
                                final fillColor = step.isMuted
                                    ? noteColor
                                    : (isActive ? Colors.tealAccent : noteColor);

                                return Align(
                                  alignment: Alignment.centerLeft,  // forces left alignment
                                  child: Stack(
                                    alignment: Alignment.topCenter,
                                    children: [
                                      if (isSelected) ...[
                                        // full-width top bar
                                        Positioned(
                                          top:0, left:0, right:0, height:1.6,
                                          child: Container(color: Colors.grey.shade400),
                                        ),
                                        // left fade
                                        Positioned(
                                          top:0, left:0, width:1.6, height:14,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  Colors.grey.shade400,
                                                  Colors.grey.shade400.withOpacity(0),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        // right fade
                                        Positioned(
                                          top:0, right:0, width:1.6, height:14,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  Colors.grey.shade400,
                                                  Colors.grey.shade400.withOpacity(0),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],

                                      Transform.scale(
                                        scale: step.isMuted ? 1.0 : scale,
                                        alignment: Alignment.centerLeft,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            if (step.isAccented)
                                              ImageFiltered(
                                                imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                                                child: SvgPicture.asset(
                                                  step.rhythm.assetPath,
                                                  height: 42,
                                                  colorFilter: ColorFilter.mode(
                                                    // use the same accent color you want: teal, grey, or white
                                                    isActive 
                                                      ? Colors.tealAccent 
                                                      : Colors.white.withOpacity(0.8),
                                                    BlendMode.srcIn,
                                                  ),
                                                ),
                                              ),
                                            SvgPicture.asset(
                                              step.rhythm.assetPath,
                                              height: 42,
                                              colorFilter: ColorFilter.mode(fillColor, BlendMode.srcIn),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 2) Your sliding editor panel
Widget _buildEditorPanel() {
  final isActive = _selectedBarIndex != null && _selectedStepIndex != null;
  final step = isActive
      ? sequencer.bars[_selectedBarIndex!].steps[_selectedStepIndex!]
      : null;

  return Container(
    margin: const EdgeInsets.symmetric(vertical: 6),
    height: 64,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: Colors.black,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: isActive ? Colors.tealAccent : Colors.grey.shade800,
        width: 1.2,
      ),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: Icon(
            (isActive && step!.isMuted) ? Icons.volume_off : Icons.volume_up,
            color: isActive
                ? (step!.isMuted ? Colors.white : Colors.tealAccent)
                : Colors.grey,
          ),
          onPressed: isActive
              ? () {
                  setState(() {
                    step!.isMuted = !step.isMuted;
                    sequencer.reset();
                  });
                }
              : null,
        ),
        // Accent toggle button
        IconButton(
          icon: Icon(
            Icons.chevron_right,
            color: isActive 
                ? (step!.isAccented ? Colors.tealAccent : Colors.white)
                : Colors.grey,
          ),
          onPressed: isActive
              ? () {
                  setState(() {
                    step!.isAccented = !step.isAccented;
                  });
                }
              : null,
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              RhythmType.minim,
              RhythmType.crotchet,
              RhythmType.quaver,
              RhythmType.semiquaver,
            ].map((r) {
              final selected = isActive && step!.rhythm == r;
              return GestureDetector(
                onTap: isActive
                    ? () {
                        setState(() {
                          sequencer.bars[_selectedBarIndex!]
                            .replaceStepAt(_selectedStepIndex!, r);
                          sequencer.rebuildSchedule();
                          sequencer.reset();
                        });
                      }
                    : null,
                child: SvgPicture.asset(
                  r.assetPath,
                  height: 42,
                  colorFilter: ColorFilter.mode(
                    selected ? Colors.tealAccent : (isActive ? Colors.white : Colors.grey),
                    BlendMode.srcIn,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete),
          color: isActive ? Colors.white : Colors.grey,
          onPressed: isActive ? _deleteSelectedBar : null,
        ),
        IconButton(
          icon: const Icon(Icons.add_circle),
          color: Colors.tealAccent,
          onPressed: () => _showAddBarPopup(context),
        ),
      ],
    ),
  );
}

/// Deletes the currently selected bar, with all the same behaviors you had inline before.
void _deleteSelectedBar() {
  final wasPlaying = sequencer.isRunning;
  // 1) remove it
  setState(() {
    sequencer.bars.removeAt(_selectedBarIndex!);
    sequencer.rebuildSchedule();
  });

  // 2) if none left, stop & clear selection
  if (sequencer.bars.isEmpty) {
    sequencer.stop();
    widget.onStop?.call();
    setState(() {
      _selectedBarIndex = null;
      _selectedStepIndex = null;
      _popupVisible = false;
    });
    if (wasPlaying) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No bars created in sequencer!')),
      );
    }
    return;
  }

  // 3) else clamp selection to a valid bar
  setState(() {
    if (_selectedBarIndex! >= sequencer.bars.length) {
      _selectedBarIndex = sequencer.bars.length - 1;
    }
    _selectedStepIndex = 0;
    _popupVisible = true;
  });

  // 4) jump playback
  sequencer.jumpTo(_selectedBarIndex!, _selectedStepIndex!);
}

@override
Widget build(BuildContext context) {
  final children = <Widget>[];

  for (var i = 0; i < sequencer.bars.length; i++) {
    children.add(
      // group the bar + its editor
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildBar(i),
          // animate the editor panel opening/closing
          AnimatedSize(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            child: (_selectedBarIndex == i && _popupVisible)
                ? _buildEditorPanel()
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // if nothing is selected, show a floating “+ bar” button at bottom
  if (_selectedBarIndex == null) {
    children.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: IconButton(
          iconSize: 32,
          icon: const Icon(Icons.add_circle_outline, color: Colors.tealAccent),
          onPressed: () => _showAddBarPopup(context),
        ),
      ),
    );
  }

  return SingleChildScrollView(
    controller: _scrollController,
    child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _closePopup,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    ),
  );
}
}