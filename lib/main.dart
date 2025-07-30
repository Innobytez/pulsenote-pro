import 'package:flutter/material.dart';
import 'screens/sequencer_screen.dart';
import 'screens/polyrhythm_screen.dart';
import 'screens/metronome_screen.dart';
import 'screens/note_generator_screen.dart';
import 'screens/setlist_screen.dart';
import 'services/audio_service.dart';
import 'services/tick_service.dart';
import 'widgets/bouncing_dot.dart';
import 'widgets/tick_glow_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AudioService.warmUp();
  runApp(const PulseNoteApp());
}

class PulseNoteApp extends StatefulWidget {
  const PulseNoteApp({super.key});

  @override
  State<PulseNoteApp> createState() => _PulseNoteAppState();
}

class _PulseNoteAppState extends State<PulseNoteApp> {
  // default to Metronome (third tab)
  int _currentIndex = 2;

  final List<Widget> _screens = [
    SequencerScreen(),
    PolyrhythmScreen(),
    MetronomeScreen(),
    NoteGeneratorScreen(),
    SetlistScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PulseNote',
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Stack(
          children: [
            _screens[_currentIndex],
            const TickGlowOverlay(),
            ValueListenableBuilder<bool>(
              valueListenable: TickService().isRunningNotifier,
              builder: (context, isRunning, _) {
                return ValueListenableBuilder<int>(
                  valueListenable: TickService().bpmNotifier,
                  builder: (context, bpm, _) => Stack(
                    children: [
                      Positioned(
                        top: 0, bottom: 0, left: 0, width: 40,
                        child: BouncingDot(
                          bpm: bpm,
                          isRunning: isRunning,
                          side: DotSide.left,
                        ),
                      ),
                      Positioned(
                        top: 0, bottom: 0, right: 0, width: 40,
                        child: BouncingDot(
                          bpm: bpm,
                          isRunning: isRunning,
                          side: DotSide.right,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          backgroundColor: Colors.black,
          selectedItemColor: Colors.tealAccent,
          unselectedItemColor: Colors.white70,
          type: BottomNavigationBarType.fixed,
          onTap: (i) => setState(() => _currentIndex = i),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.view_list, size:  36), label: 'Sequencer'),
            BottomNavigationBarItem(
              icon: Icon(Icons.shuffle, size: 36), label: 'Polyrhythms'),
            BottomNavigationBarItem(
              icon: Icon(Icons.speed, size: 36), label: 'Metronome'),
            BottomNavigationBarItem(
              icon: Icon(Icons.music_note, size: 36), label: 'Note Generator'),
            BottomNavigationBarItem(
              icon: Icon(Icons.list_alt, size: 36), label: 'Setlists'),
          ],
        ),
      ),
    );
  }
}