// File: lib/services/playback_coordinator.dart

import 'dart:async';

typedef BoolFn = bool Function();
typedef AsyncFn = Future<void> Function();

class _Client {
  final String id;
  final AsyncFn play;
  final AsyncFn pause;
  final BoolFn isPlaying;
  final AsyncFn? next;
  final AsyncFn? previous;

  _Client({
    required this.id,
    required this.play,
    required this.pause,
    required this.isPlaying,
    this.next,
    this.previous,
  });
}

class CoordinatorSnapshot {
  final String? activeId;
  final bool isPlaying;
  const CoordinatorSnapshot({required this.activeId, required this.isPlaying});
}

class PlaybackCoordinator {
  PlaybackCoordinator._();
  static final PlaybackCoordinator instance = PlaybackCoordinator._();

  final Map<String, _Client> _clients = {};
  String? _activeId;

  final _stateCtl = StreamController<CoordinatorSnapshot>.broadcast();
  Stream<CoordinatorSnapshot> get stateStream => _stateCtl.stream;

  void bind({
    required String id,
    required AsyncFn onPlay,
    required AsyncFn onPause,
    required BoolFn isPlaying,
    AsyncFn? onNext,
    AsyncFn? onPrevious,
  }) {
    _clients[id] = _Client(
      id: id,
      play: onPlay,
      pause: onPause,
      isPlaying: isPlaying,
      next: onNext,
      previous: onPrevious,
    );
  }

  void activate(String id) {
    _activeId = id;
    _emit();
  }

  Future<void> requestPlay() async {
    final c = _current;
    if (c == null) return;
    if (!c.isPlaying()) {
      await c.play();
      _emit();
    }
  }

  Future<void> requestPause() async {
    final c = _current;
    if (c == null) return;
    if (c.isPlaying()) {
      await c.pause();
      _emit();
    }
  }

  Future<void> requestNext() async {
    final c = _current;
    if (c?.next == null) return;
    await c!.next!();
    _emit();
  }

  Future<void> requestPrevious() async {
    final c = _current;
    if (c?.previous == null) return;
    await c!.previous!();
    _emit();
  }

  _Client? get _current => _activeId == null ? null : _clients[_activeId!];

  void _emit() {
    _stateCtl.add(CoordinatorSnapshot(
      activeId: _activeId,
      isPlaying: _current?.isPlaying() ?? false,
    ));
  }
}