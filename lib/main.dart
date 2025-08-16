// File: lib/main.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// App services/widgets
import 'services/app_state_service.dart';
import 'services/audio_service.dart' as click_audio; // SoLoud service (aliased)
import 'services/tick_service.dart';
import 'screens/sequencer_screen.dart';
import 'screens/polyrhythm_screen.dart';
import 'screens/metronome_screen.dart';
import 'screens/note_generator_screen.dart';
import 'screens/setlist_screen.dart';
import 'widgets/bouncing_dot.dart';
import 'widgets/tick_glow_overlay.dart';

// Media session / routing
import 'package:audio_service/audio_service.dart' as sys_audio;
import 'package:audio_session/audio_session.dart';
import 'services/system_media_handler.dart';
import 'services/playback_coordinator.dart';

// For caching artwork to a file:// URI
import 'package:path_provider/path_provider.dart';

late sys_audio.AudioHandler audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Configure & activate the platform audio session FIRST
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  await session.setActive(true);

  // 2) Warm up SoLoud AFTER the session is active so it binds to the current route
  await click_audio.AudioService.warmUp();

  // 3) Start audio_service (media session + notifications / control center)
  //    Note: androidNotificationOngoing=true requires androidStopForegroundOnPause=true
  audioHandler = await sys_audio.AudioService.init(
    builder: () => SystemMediaHandler(PlaybackCoordinator.instance),
    config: const sys_audio.AudioServiceConfig(
      androidNotificationChannelId: 'pulsenote_channel',
      androidNotificationChannelName: 'PulseNote',
      androidNotificationIcon: 'mipmap/ic_launcher',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  // 3b) Set media artwork once (PulseNote icon) — shown in iOS Control Center & Android notif
  final artUri = await _cacheArtwork('assets/icon/PN_android_icon.png');
  if (artUri != null) {
    // This method should exist in your SystemMediaHandler per earlier changes.
    SystemMediaHandler.last?.setNowPlaying(artUri: artUri);
  }

  // 4) Hook platform events → single coordinator (one source of truth)
  final coord = PlaybackCoordinator.instance;

  // Headphones unplugged / Bluetooth route lost
  session.becomingNoisyEventStream.listen((_) async {
    await coord.requestPause();
  });

  // Phone calls, Siri, nav prompts, etc.
  session.interruptionEventStream.listen((event) async {
    if (event.begin) {
      await coord.requestPause();
    } else {
      // Optionally auto-resume on certain interruption types.
      // if (event.type == AudioInterruptionType.duck) {
      //   await coord.requestPlay();
      // }
    }
  });

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
  // Keep Metronome as default (index 2)
  int _currentIndex = 2;

  @override
  Widget build(BuildContext context) {
    // Listen to global BPM so wheel/dots reflect changes
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
                // 0: Polyrhythms
                PolyrhythmScreen(active: _currentIndex == 0),

                // 1: Sequencer
                SequencerScreen(active: _currentIndex == 1),

                // 2: Metronome
                MetronomeScreen(active: _currentIndex == 2),

                // 3: Setlists
                SetlistScreen(active: _currentIndex == 3),

                // 4: Generator
                NoteGeneratorScreen(active: _currentIndex == 4),
              ],
            ),

            // Visual tick effects
            const TickGlowOverlay(),

            // Left/right bouncing dots driven by TickService notifiers
            ValueListenableBuilder<bool>(
              valueListenable: TickService().isRunningNotifier,
              builder: (_, isRunning, __) => ValueListenableBuilder<int>(
                valueListenable: TickService().bpmNotifier,
                builder: (_, tickBpm, __) => Stack(
                  children: [
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: 0,
                      width: 40,
                      child: BouncingDot(
                        bpm: tickBpm,
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
          onTap: (i) {
            if (i != _currentIndex) {
              HapticFeedback.selectionClick(); // haptic on change
            }
            setState(() => _currentIndex = i);
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.shuffle, size: 36),
              label: 'Polyrhythms',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.av_timer, size: 36),
              label: 'Sequencer',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.speed, size: 36),
              label: 'Metronome',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.list_alt, size: 36),
              label: 'Setlists',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.music_note, size: 36),
              label: 'Generator',
            ),
          ],
        ),
      ),
    );
  }
}

/// Cache an asset image to a local file and return its file:// URI for media artwork.
/// Uses the existing asset declared in pubspec: assets/icon/PN_android_icon.png
Future<Uri?> _cacheArtwork(String assetPath) async {
  try {
    final data = await rootBundle.load(assetPath);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/pulsenote_art.png');
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return file.uri;
  } catch (_) {
    return null;
  }
}