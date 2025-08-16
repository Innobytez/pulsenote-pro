// File: lib/services/system_media_handler.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:audio_service/audio_service.dart' as sys_audio;
import 'package:audio_session/audio_session.dart';

import 'playback_coordinator.dart';
import 'tick_service.dart';

class SystemMediaHandler extends sys_audio.BaseAudioHandler {
  static SystemMediaHandler? last;

  final PlaybackCoordinator _coord;
  StreamSubscription? _coordSub;
  VoidCallback? _tickListener;

  String _title = 'PulseNote';
  String _subtitle = ''; // <- NEW (e.g., "120 BPM")
  bool _cleanedUp = false;

  SystemMediaHandler(this._coord) {
    last = this;
    _init();
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.setActive(true);

    mediaItem.add(sys_audio.MediaItem(
      id: 'pulsenote.playback',
      album: 'PulseNote',
      title: _title,
      artist: _subtitle,   // <- we show subtitle here
    ));

    _coordSub = _coord.stateStream.listen((snap) {
      _publishPlaying(snap.isPlaying);
    });

    _tickListener = () => _publishPlaying(TickService().isRunning);
    TickService().isRunningNotifier.addListener(_tickListener!);

    _publishPlaying(false);
  }

  void _publishPlaying(bool playing) {
    playbackState.add(sys_audio.PlaybackState(
      controls: const [
        sys_audio.MediaControl.skipToPrevious,
        sys_audio.MediaControl.pause,
        sys_audio.MediaControl.play,
        sys_audio.MediaControl.skipToNext,
        sys_audio.MediaControl.stop,
      ],
      androidCompactActionIndices: const [0, 1, 3],
      systemActions: const {
        sys_audio.MediaAction.play,
        sys_audio.MediaAction.pause,
        sys_audio.MediaAction.stop,
        sys_audio.MediaAction.skipToNext,
        sys_audio.MediaAction.skipToPrevious,
      },
      processingState: sys_audio.AudioProcessingState.ready,
      playing: playing,
    ));
  }

  // --- NEW: richer setter (title + subtitle) ---
  void setNowPlayingTitle(String title) => setNowPlaying(title: title);

  void setNowPlaying({String? title, String? subtitle, Uri? artUri}) {
    if (title != null) _title = title;
    if (subtitle != null) _subtitle = subtitle;

    final curr = mediaItem.valueOrNull;
    mediaItem.add(sys_audio.MediaItem(
      id: 'pulsenote.playback',
      album: 'PulseNote',
      title: _title,
      artist: _subtitle,        // iOS/Android show this under title
      artUri: artUri ?? curr?.artUri,
      extras: curr?.extras,
    ));
  }

  // Remote controls → coordinator
  @override
  Future<void> play() => _coord.requestPlay();

  @override
  Future<void> pause() => _coord.requestPause();

  @override
  Future<void> stop() async {
    await _coord.requestPause();
    _cleanupOnce();
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }

  @override
  Future<void> skipToNext() => _coord.requestNext();

  @override
  Future<void> skipToPrevious() => _coord.requestPrevious();

  void _cleanupOnce() {
    if (_cleanedUp) return;
    _cleanedUp = true;
    _coordSub?.cancel();
    if (_tickListener != null) {
      TickService().isRunningNotifier.removeListener(_tickListener!);
    }
  }
}