// File: lib/screens/note_generator_screen.dart

import 'dart:async';
import 'dart:ui'; // for lerpDouble
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/audio_service.dart';
import '../services/tick_service.dart';
import '../services/app_state_service.dart';
import '../services/playback_coordinator.dart';
import '../services/system_media_handler.dart';
import '../widgets/wheel_picker.dart';
import '../widgets/note_generator_settings_modal.dart';

class NoteGeneratorScreen extends StatefulWidget {
  final bool active;
  const NoteGeneratorScreen({Key? key, required this.active}) : super(key: key);

  @override
  State<NoteGeneratorScreen> createState() => _NoteGeneratorScreenState();
}

class _NoteGeneratorScreenState extends State<NoteGeneratorScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _defaultNotes = [
    'C','C#','D','D#','E','F','F#','G','G#','A','A#','B'
  ];

  late Set<String> _selectedNotes;
  String _prev = '', _current = '', _next = '';

  bool _autoMode = false;
  bool _prefsLoaded = false;

  bool _appInForeground = true;

  late final TickService _tickService;
  StreamSubscription<void>? _tickSub;
  StreamSubscription<void>? _tempoIncSub;
  late final AnimationController _slideController;

  void _publishMeta() {
    final bpm = context.read<AppStateService>().bpm;
    SystemMediaHandler.last?.setNowPlaying(
      title: 'Random Note Generator',
      subtitle: '$bpm BPM',
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _tickService = TickService();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _loadNotePrefs();

    PlaybackCoordinator.instance.bind(
      id: 'generator',
      onPlay: () async {
        if (!_autoMode) _toggleAuto();
      },
      onPause: () async {
        if (_autoMode) _toggleAuto();
      },
      isPlaying: () => _autoMode,
    );

    if (widget.active) {
      PlaybackCoordinator.instance.activate('generator');
      _publishMeta();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = (state == AppLifecycleState.resumed);
  }

  @override
  void didUpdateWidget(covariant NoteGeneratorScreen old) {
    super.didUpdateWidget(old);
    if (old.active && !widget.active && _autoMode) {
      _stopInternal();
    }
    if (!old.active && widget.active) {
      PlaybackCoordinator.instance.activate('generator');
      _publishMeta();
    }
  }

  Future<void> _loadNotePrefs() async {
    final p = await SharedPreferences.getInstance();
    final notesList = p.getStringList('selectedNotes');
    _selectedNotes = (notesList?.toSet() ?? _defaultNotes.toSet());

    _prev    = _randomNote();
    _current = _randomNote(exclude: _prev);
    _next    = _randomNote(exclude: _current);

    setState(() => _prefsLoaded = true);
  }

  Future<void> _saveNotePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('selectedNotes', _selectedNotes.toList());
  }

  String _randomNote({String? exclude}) {
    final pool = _selectedNotes.toList()..shuffle();
    final filtered = exclude == null
        ? pool
        : pool.where((n) => n != exclude).toList();
    return filtered.isNotEmpty ? filtered.first : _selectedNotes.first;
  }

  void _advanceNote() {
    if (!_prefsLoaded) return;

    final newCurrent = _next.isNotEmpty ? _next : _randomNote(exclude: _current);
    final newNext = _randomNote(exclude: newCurrent);

    if (context.read<AppStateService>().soundOn) {
      AudioService.playNote(newCurrent);
    }

    final isVisible = mounted && widget.active && _appInForeground;

    if (isVisible) {
      void commit() {
        if (!mounted) return;
        setState(() {
          _prev = _current;
          _current = newCurrent;
          _next = newNext;
        });
        _slideController.reset();
      }

      void statusListener(AnimationStatus s) {
        if (s == AnimationStatus.completed) {
          _slideController.removeStatusListener(statusListener);
          commit();
        }
      }

      _slideController.removeStatusListener(statusListener);
      _slideController.addStatusListener(statusListener);
      _slideController.forward(from: 0);
    } else {
      _prev = _current;
      _current = newCurrent;
      _next = newNext;
      if (mounted) setState(() {});
    }
  }

  void _installResumer() {
    TickService().setBackgroundResumer(() async {
      if (!_autoMode) _toggleAuto();
    });
  }

  void _clearResumer() => TickService().setBackgroundResumer(null);

  void _startInternal() {
    final appState = context.read<AppStateService>();
    final bpm = appState.bpm;
    final tempoX = appState.tempoIncreaseX;
    final tempoY = appState.tempoIncreaseY;
    final tempoOn = appState.tempoIncreaseEnabled;

    SystemMediaHandler.last?.setNowPlaying(
      title: 'Random Note Generator',
      subtitle: '$bpm BPM',
    );

    if (tempoOn) {
      _tempoIncSub?.cancel();
      bool first = false;
      int count = 0;
      _tempoIncSub = _tickService.tickStream.listen((_) {
        if (!first) { first = true; return; }
        count++;
        if (count >= tempoY) {
          count = 0;
          appState.setBpm((appState.bpm + tempoX).clamp(10, 240));
          _tickService.updateBpm(appState.bpm);
          _publishMeta(); // live BPM
        }
      });
    }

    _tickSub?.cancel();
    _tickSub = _tickService.tickStream.listen((_) => _advanceNote());
    _tickService.start(bpm);

    setState(() => _autoMode = true);
    _installResumer();
    PlaybackCoordinator.instance.activate('generator');
  }

  void _stopInternal() {
    _tickSub?.cancel();
    _tempoIncSub?.cancel();
    _tickService.stop();
    setState(() => _autoMode = false);
    _clearResumer();
  }

  void _toggleAuto() {
    if (!_autoMode) {
      _startInternal();
    } else {
      _stopInternal();
    }
  }

  void _manualNext() => _advanceNote();

  Future<void> _openSettings() async {
    final wasAuto = _autoMode;
    if (wasAuto) _stopInternal();

    final wantSelect = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const NoteGeneratorSettingsModal(),
    );

    if (wantSelect == true) {
      _showNoteSelector();
    }
  }

  void _showNoteSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          const pairs = <List<String?>>[
            ['C',  'B#'],
            ['C#', 'Db'],
            ['D',  null],
            ['D#', 'Eb'],
            ['E',  'Fb'],
            ['F',  'E#'],
            ['F#', 'Gb'],
            ['G',  null],
            ['G#', 'Ab'],
            ['A',  null],
            ['A#', 'Bb'],
            ['B',  'Cb'],
          ];

          Widget noteTile(String note) {
            final sel = _selectedNotes.contains(note);
            return CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(note, style: const TextStyle(color: Colors.white)),
              value: sel,
              activeColor: Colors.tealAccent,
              checkColor: Colors.black,
              onChanged: (v) {
                setModalState(() {
                  if (v == true) _selectedNotes.add(note);
                  else _selectedNotes.remove(note);
                });
                _saveNotePrefs();
              },
            );
          }

          return Wrap(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border(top: BorderSide(color: Colors.grey.shade800, width: 1)),
                ),
                padding: EdgeInsets.fromLTRB(
                  16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            setModalState(() => _selectedNotes = _defaultNotes.toSet());
                            _saveNotePrefs();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.tealAccent,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Reset'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: pairs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (_, i) {
                        final left = pairs[i][0]!;
                        final right = pairs[i][1];
                        return Row(
                          children: [
                            Expanded(child: noteTile(left)),
                            const SizedBox(width: 16),
                            Expanded(child: right == null ? const SizedBox.shrink() : noteTile(right)),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickSub?.cancel();
    _tempoIncSub?.cancel();
    _tickService.stop();
    _slideController.dispose();
    _clearResumer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_prefsLoaded) return const SizedBox.shrink();

    final appState = context.watch<AppStateService>();
    final bpm = appState.bpm;
    final soundOn = appState.soundOn;

    final w = MediaQuery.of(context).size.width;
    final colW = w / 3;

    return SafeArea(
      child: Column(
        children: [
          // 1: Note carousel
          Expanded(
            child: AnimatedBuilder(
              animation: _slideController,
              builder: (_, __) {
                final v = _slideController.value;
                final dx = -colW * v;
                final prevSize    = 48.0;
                final currentSize = lerpDouble(96, 48, v)!;
                final nextSize    = lerpDouble(48, 96, v)!;

                return ClipRect(
                  child: SizedBox(
                    width: colW * 3,
                    child: Transform.translate(
                      offset: Offset(dx, 0),
                      child: Row(
                        children: [
                          _noteColumn(_prev,    prevSize,    Colors.white54,   colW),
                          _noteColumn(_current, currentSize, Colors.tealAccent, colW),
                          _noteColumn(_next,    nextSize,    Colors.white54,   colW),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // 2: BPM wheel
          SizedBox(
            height: w * 0.8,
            child: WheelPicker(
              initialBpm: bpm,
              minBpm: 10,
              maxBpm: 240,
              wheelSize: w * 0.8,
              onBpmChanged: (val) {
                appState.setBpm(val);
                if (_autoMode) _tickService.updateBpm(val);
                _publishMeta(); // live BPM even when paused
              },
            ),
          ),

          // 3: Controls
          SizedBox(
            height: 100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  iconSize: 40,
                  icon: Icon(soundOn ? Icons.volume_up : Icons.volume_off),
                  onPressed: () => context.read<AppStateService>().setSoundOn(!soundOn),
                ),
                IconButton(
                  iconSize: 40,
                  icon: Icon(_autoMode ? Icons.pause_circle : Icons.play_circle),
                  onPressed: _toggleAuto,
                ),
                IconButton(
                  iconSize: 40,
                  icon: const Icon(Icons.skip_next),
                  onPressed: _manualNext,
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

  Widget _noteColumn(String note, double fontSize, Color color, double width) {
    return SizedBox(
      width: width,
      child: Center(
        child: Text(
          note,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }
}