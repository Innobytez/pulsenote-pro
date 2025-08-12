// File: lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/app_state_service.dart';
import 'services/audio_service.dart';
import 'services/tick_service.dart';
import 'screens/sequencer_screen.dart';
import 'screens/polyrhythm_screen.dart';
import 'screens/metronome_screen.dart';
import 'screens/note_generator_screen.dart';
import 'screens/setlist_screen.dart';
import 'widgets/bouncing_dot.dart';
import 'widgets/tick_glow_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AudioService.warmUp();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppStateService(),
      child: const PulseNoteApp(),
    ),
  );
}

class PulseNoteApp extends StatefulWidget {
  const PulseNoteApp({Key? key}) : super(key: key);

  @override
  State<PulseNoteApp> createState() => _PulseNoteAppState();
}

class _PulseNoteAppState extends State<PulseNoteApp> {
  int _currentIndex = 2;  // default to Metronome tab

  @override
  Widget build(BuildContext context) {
    // listen to global BPM
    context.watch<AppStateService>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PulseNote',
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Stack(
          children: [
            IndexedStack(
              index: _currentIndex,
              children: [
                SequencerScreen(
                  active: _currentIndex == 0,
                ),
                PolyrhythmScreen(
                  active: _currentIndex == 1,
                ),
                MetronomeScreen(
                  active: _currentIndex == 2,
                ),
                NoteGeneratorScreen(
                  active: _currentIndex == 3,
                ),
                SetlistScreen(),
              ],
            ),

            // keep your tick‐glow & bouncing dots on top
            const TickGlowOverlay(),
            ValueListenableBuilder<bool>(
              valueListenable: TickService().isRunningNotifier,
              builder: (_, isRunning, __) => ValueListenableBuilder<int>(
                valueListenable: TickService().bpmNotifier,
                builder: (_, tickBpm, __) => Stack(
                  children: [
                    Positioned(
                      top: 0, bottom: 0, left: 0, width: 40,
                      child: BouncingDot(
                        bpm: tickBpm,
                        isRunning: isRunning,
                        side: DotSide.left,
                      ),
                    ),
                    Positioned(
                      top: 0, bottom: 0, right: 0, width: 40,
                      child: BouncingDot(
                        bpm: tickBpm,
                        isRunning: isRunning,
                        side: DotSide.right,
                      ),
                    ),
                  ],
                ),
              ),
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
              icon: Icon(Icons.av_timer, size: 36), label: 'Sequencer'),
            BottomNavigationBarItem(
              icon: Icon(Icons.shuffle, size: 36), label: 'Polyrhythms'),
            BottomNavigationBarItem(
              icon: Icon(Icons.speed, size: 36), label: 'Metronome'),
            BottomNavigationBarItem(
              icon: Icon(Icons.music_note, size: 36), label: 'Generator'),
            BottomNavigationBarItem(
              icon: Icon(Icons.list_alt, size: 36), label: 'Setlists'),
          ],
        ),
      ),
    );
  }
}