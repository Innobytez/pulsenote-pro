import 'package:flutter/material.dart';
import 'screens/metronome_screen.dart';
import 'screens/note_generator_screen.dart';
import 'screens/setlist_screen.dart';
import 'services/audio_service.dart';
import 'services/tick_service.dart';
import 'widgets/bouncing_dot.dart';
import 'widgets/tick_glow_overlay.dart'; // ✅ Added import

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
  int _currentIndex = 0;

  final List<Widget> _screens = [
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

            const TickGlowOverlay(), // ✅ Added glow effect

            // Reactive global bouncing dots
            ValueListenableBuilder<bool>(
              valueListenable: TickService().isRunningNotifier,
              builder: (context, isRunning, _) {
                return ValueListenableBuilder<int>(
                  valueListenable: TickService().bpmNotifier,
                  builder: (context, bpm, _) {
                    return Stack(
                      children: [
                        Positioned(
                          top: 0,
                          bottom: 0,
                          left: 0,
                          width: 40,
                          child: BouncingDot(
                            bpm: bpm,
                            isRunning: isRunning,
                            side: DotSide.left,
                          ),
                        ),
                        Positioned(
                          top: 0,
                          bottom: 0,
                          right: 0,
                          width: 40,
                          child: BouncingDot(
                            bpm: bpm,
                            isRunning: isRunning,
                            side: DotSide.right,
                          ),
                        ),
                      ],
                    );
                  },
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
          showSelectedLabels: true,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.speed, size: 36), label: 'Metronome'),
            BottomNavigationBarItem(icon: Icon(Icons.music_note, size: 36), label: 'Note Generator'),
            BottomNavigationBarItem(icon: Icon(Icons.list_alt, size: 36), label: 'Tempo Setlist'),
          ],
        ),
      ),
    );
  }
}