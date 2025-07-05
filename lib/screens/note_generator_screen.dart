import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/audio_service.dart';
import '../services/tick_service.dart';
import '../widgets/wheel_picker.dart';

class NoteGeneratorScreen extends StatefulWidget {
  @override
  _NoteGeneratorScreenState createState() => _NoteGeneratorScreenState();
}

class _NoteGeneratorScreenState extends State<NoteGeneratorScreen> with SingleTickerProviderStateMixin {
  final List<String> defaultNotes = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];
  final List<String> extraNotes = ['B#', 'Db', 'D#', 'Fb', 'E#', 'Gb', 'G#', 'A#', 'Cb'];
  Set<String> selectedNotes = {};

  String? previousNote;
  String currentNote = 'C';
  String? nextNote;
  String? nextNextNote;

  bool autoMode = false;
  bool soundOn = true;
  int notesPerMinute = 60;
  bool _prefsLoaded = false;

  late final TickService _tickService;
  StreamSubscription<void>? _tickSub;
  late AnimationController _slideController;

  @override
  void initState() {
    super.initState();
    _tickService = TickService();
    _slideController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 150),
    );
    _loadPreferences();

    _tickSub = _tickService.tickStream.listen((_) {
      if (autoMode) _advanceNote();
    });
  }

  @override
  void dispose() {
    _tickSub?.cancel();
    _tickService.stop();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final storedNotes = prefs.getStringList('selectedNotes');
    final storedBpm = prefs.getInt('note_generator_bpm');
    final storedSound = prefs.getBool('note_generator_sound');

    setState(() {
      selectedNotes = storedNotes?.toSet() ?? defaultNotes.toSet();
      notesPerMinute = storedBpm?.clamp(10, 240) ?? 60;
      soundOn = storedSound ?? true;
      _prefsLoaded = true;
    });

    _generateInitialNotes();
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('selectedNotes', selectedNotes.toList());
  }

  Future<void> _saveBpm(int bpm) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('note_generator_bpm', bpm);
  }

  Future<void> _saveSound(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('note_generator_sound', value);
  }

  void _resetToDefault() {
    setState(() {
      selectedNotes = defaultNotes.toSet();
      _generateInitialNotes();
    });
    _savePreferences();
  }

  void _generateInitialNotes() {
    nextNote = _generateNextNote(exclude: currentNote);
    nextNextNote = _generateNextNote(exclude: nextNote);
  }

  String _generateNextNote({String? exclude}) {
    final pool = selectedNotes.toList()..shuffle();
    final filtered = pool.where((n) => n != exclude).toList();
    return filtered.isNotEmpty ? filtered.first : currentNote;
  }

  void _advanceNote() async {
    await _slideController.forward();
    setState(() {
      previousNote = currentNote;
      currentNote = nextNote ?? currentNote;
      nextNote = nextNextNote ?? currentNote;
      nextNextNote = _generateNextNote(exclude: currentNote);
    });
    _slideController.reset();

    if (soundOn) AudioService.playNote(currentNote);
  }

  void _toggleAutoMode() {
    setState(() => autoMode = !autoMode);
    if (autoMode) {
      _tickService.start(notesPerMinute);
    } else {
      _tickService.stop();
    }
  }

  void _manualTrigger() => _advanceNote();

  void _showEnharmonicSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          final allNotes = [...defaultNotes, ...extraNotes];

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 40),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          _resetToDefault();
                          Navigator.pop(context);
                        },
                        child: Text("Reset to Default"),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: allNotes.map((note) {
                          final isSelected = selectedNotes.contains(note);
                          final willBeTooFew = isSelected && selectedNotes.length <= 3;

                          return CheckboxListTile(
                            title: Text(note, style: TextStyle(color: Colors.white)),
                            value: isSelected,
                            onChanged: willBeTooFew && !isSelected
                                ? null
                                : (val) {
                                    setModalState(() {
                                      if (val == true) {
                                        selectedNotes.add(note);
                                      } else {
                                        selectedNotes.remove(note);
                                      }
                                    });
                                    _savePreferences();
                                    _generateInitialNotes();
                                  },
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_prefsLoaded) return SizedBox.shrink();

    return Column(
      children: [
        Expanded(
          child: Center(
            child: AnimatedBuilder(
              animation: _slideController,
              builder: (context, child) {
                final progress = _slideController.value;
                return SizedBox(
                  height: 500,
                  child: Stack(
                    children: [
                      if (previousNote != null)
                        Positioned(
                          top: 100 - 100 * progress,
                          left: 0,
                          right: 0,
                          child: Opacity(
                            opacity: 1.0 - progress,
                            child: Center(
                              child: Text(
                                previousNote!,
                                style: TextStyle(
                                  fontSize: 40 - 30 * progress,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 200 - 100 * progress,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Text(
                            currentNote,
                            style: TextStyle(
                              fontSize: 120 - 80 * progress,
                              fontWeight: FontWeight.bold,
                              color: Color.lerp(Colors.tealAccent, Colors.white54, progress),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 400 - 200 * progress,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Text(
                            nextNote ?? '',
                            style: TextStyle(
                              fontSize: 40 + 80 * progress,
                              fontWeight: FontWeight.bold,
                              color: Color.lerp(Colors.white54, Colors.tealAccent, progress),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 700 - 300 * progress,
                        left: 0,
                        right: 0,
                        child: Opacity(
                          opacity: progress,
                          child: Center(
                            child: Text(
                              nextNextNote ?? '',
                              style: TextStyle(
                                fontSize: 0 + 40 * progress,
                                fontWeight: FontWeight.bold,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        SizedBox(height: 20),
        WheelPicker(
          initialBpm: notesPerMinute,
          wheelSize: 160,
          minBpm: 10,
          maxBpm: 240,
          onBpmChanged: (val) {
            setState(() => notesPerMinute = val);
            _saveBpm(val);
            if (autoMode) _tickService.start(notesPerMinute);
          },
        ),
        SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              iconSize: 40,
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
              iconSize: 40,
              onPressed: _toggleAutoMode,
              icon: Icon(
                autoMode ? Icons.pause_circle : Icons.play_circle,
                color: Colors.white,
              ),
            ),
            IconButton(
              iconSize: 40,
              onPressed: _manualTrigger,
              icon: Icon(Icons.music_note, color: Colors.white),
            ),
            IconButton(
              iconSize: 40,
              onPressed: _showEnharmonicSelector,
              icon: Icon(Icons.settings, color: Colors.white),
            ),
          ],
        ),
        SizedBox(height: 20),
      ],
    );
  }
}