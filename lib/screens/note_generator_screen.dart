// File: lib/screens/note_generator_screen.dart

import 'dart:async';
import 'dart:ui'; // for lerpDouble
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/audio_service.dart';
import '../services/tick_service.dart';
import '../services/app_state_service.dart';
import '../widgets/wheel_picker.dart';
import '../widgets/note_generator_settings_modal.dart';

class NoteGeneratorScreen extends StatefulWidget {
  final bool active;
  const NoteGeneratorScreen({
    Key? key,
    required this.active,
  }) : super(key: key);

  @override
  State<NoteGeneratorScreen> createState() => _NoteGeneratorScreenState();
}

class _NoteGeneratorScreenState extends State<NoteGeneratorScreen>
    with SingleTickerProviderStateMixin {
  static const _defaultNotes = [
    'C','C#','D','Eb','E','F','F#','G','Ab','A','Bb','B'
  ];
  static const _extraNotes = [
    'B#','Db','D#','Fb','E#','Gb','G#','A#','Cb'
  ];

  late Set<String> _selectedNotes;
  String _prev = '', _current = '', _next = '';

  bool _autoMode = false;
  bool _prefsLoaded = false;

  late final TickService _tickService;
  StreamSubscription<void>? _tickSub;
  StreamSubscription<void>? _tempoIncSub;
  late final AnimationController _slideController;

  @override
  void initState() {
    super.initState();
    _tickService = TickService();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _loadNotePrefs();
  }

  Future<void> _loadNotePrefs() async {
    final p = await SharedPreferences.getInstance();
    final notesList = p.getStringList('selectedNotes');
    _selectedNotes = (notesList?.toSet() ?? _defaultNotes.toSet());

    // pick first three
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

  Future<void> _advanceNote() async {
    await _slideController.forward();
    setState(() {
      _prev    = _current;
      _current = _next;
      _next    = _randomNote(exclude: _current);
    });
    _slideController.reset();

    if (context.read<AppStateService>().soundOn) {
      AudioService.playNote(_current);
    }
  }

  void _toggleAuto() {
    final appState = context.read<AppStateService>();
    final bpm = appState.bpm;
    final tempoX = appState.tempoIncreaseX;
    final tempoY = appState.tempoIncreaseY;
    final tempoOn = appState.tempoIncreaseEnabled;

    if (!_autoMode) {
      // start sub-beat playback
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
          }
        });
      }
      _tickSub?.cancel();
      _tickSub = _tickService.tickStream.listen((_) => _advanceNote());
      _tickService.start(bpm);
    } else {
      _tickSub?.cancel();
      _tempoIncSub?.cancel();
      _tickService.stop();
    }

    setState(() => _autoMode = !_autoMode);
  }

  void _manualNext() => _advanceNote();

  Future<void> _openSettings() async {
    final wasAuto = _autoMode;
    if (wasAuto) {
      _tickSub?.cancel();
      _tempoIncSub?.cancel();
      _tickService.stop();
      setState(() => _autoMode = false);
    }

    final wantSelect = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const NoteGeneratorSettingsModal(),
    );

    // Reload note‐prefs and app state (tempo-increase) immediately
    await _loadNotePrefs();
    if (wantSelect == true) {
      _showNoteSelector();
    }
    if (wasAuto) _toggleAuto();
  }

  void _showNoteSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final all = [..._defaultNotes, ..._extraNotes];
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      setModalState(() => _selectedNotes = _defaultNotes.toSet());
                      _saveNotePrefs();
                    },
                    child: const Text('Reset'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  shrinkWrap: true,
                  children: all.map((note) {
                    final sel = _selectedNotes.contains(note);
                    return CheckboxListTile(
                      title: Text(note, style: const TextStyle(color: Colors.white)),
                      value: sel,
                      onChanged: (v) {
                        setModalState(() {
                          if (v == true) _selectedNotes.add(note);
                          else _selectedNotes.remove(note);
                        });
                        _saveNotePrefs();
                      },
                    );
                  }).toList(),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }

  @override
  void didUpdateWidget(covariant NoteGeneratorScreen old) {
    super.didUpdateWidget(old);
    if (old.active && !widget.active && _autoMode) {
      _tickSub?.cancel();
      _tempoIncSub?.cancel();
      _tickService.stop();
      setState(() => _autoMode = false);
    }
  }

  @override
  void dispose() {
    _tickSub?.cancel();
    _tempoIncSub?.cancel();
    _tickService.stop();
    _slideController.dispose();
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
              onBpmChanged: (val) => appState.setBpm(val),
            ),
          ),

          // 3: Controls
          SizedBox(
            height: 100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // sound toggle
                IconButton(
                  iconSize: 40,
                  icon: Icon(soundOn ? Icons.volume_up : Icons.volume_off),
                  onPressed: () => context.read<AppStateService>().setSoundOn(!soundOn),
                ),
                // play/pause
                IconButton(
                  iconSize: 40,
                  icon: Icon(_autoMode ? Icons.pause_circle : Icons.play_circle),
                  onPressed: _toggleAuto,
                ),
                // next note
                IconButton(
                  iconSize: 40,
                  icon: const Icon(Icons.skip_next),
                  onPressed: _manualNext,
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