import 'package:flutter_sound/flutter_sound.dart';
import 'package:audio_session/audio_session.dart';
import 'dart:math';
import 'dart:typed_data';

class AudioService {
  static final FlutterSoundPlayer _player = FlutterSoundPlayer();
  static bool _isInitialized = false;
  static Uint8List? _clickBuffer;
  static Uint8List? _silentBuffer;

  static Future<void> _init() async {
    if (_isInitialized) return;

    // Configure audio session for silent mode + background support
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.music());

    await _player.openPlayer();
    _generateClickBuffer();
    _generateSilentBuffer();
    _isInitialized = true;
  }

  static void _generateClickBuffer() {
    const sampleRate = 44100;
    const durationMs = 80;
    final samples = (durationMs / 1000 * sampleRate).round();
    const amplitude = 0.3;
    const frequency = 1000.0;

    final buffer = Int16List(samples);
    for (int i = 0; i < samples; i++) {
      final t = i / sampleRate;
      final value = sin(2 * pi * frequency * t);
      buffer[i] = (value * amplitude * 32767).toInt();
    }

    _clickBuffer = Uint8List.view(buffer.buffer);
  }

  static void _generateSilentBuffer() {
    const sampleRate = 44100;
    const durationMs = 30;
    final samples = (durationMs / 1000 * sampleRate).round();
    final buffer = Int16List(samples); // silent = zeros
    _silentBuffer = Uint8List.view(buffer.buffer);
  }

  static Future<void> warmUp() async {
    await _init();
    await _player.startPlayer(
      fromDataBuffer: _silentBuffer!,
      codec: Codec.pcm16,
      sampleRate: 44100,
      numChannels: 1,
      whenFinished: () async {
        await _player.stopPlayer();
      },
    );
  }

  static Future<void> playClick() async {
    await _init();
    if (_player.isPlaying) await _player.stopPlayer();
    await _player.startPlayer(
      fromDataBuffer: _clickBuffer!,
      codec: Codec.pcm16,
      sampleRate: 44100,
      numChannels: 1,
    );
  }

  static Future<void> playNote(String note) async {
    await _init();
    final freq = _noteFrequencies[note] ?? 440.0;

    const sampleRate = 44100;
    const durationMs = 300;
    final samples = (durationMs / 1000 * sampleRate).round();
    const amplitude = 0.3;

    final buffer = Int16List(samples);
    for (int i = 0; i < samples; i++) {
      final t = i / sampleRate;
      final value = sin(2 * pi * freq * t);
      buffer[i] = (value * amplitude * 32767).toInt();
    }

    final bytes = Uint8List.view(buffer.buffer);

    if (_player.isPlaying) await _player.stopPlayer();

    await _player.startPlayer(
      fromDataBuffer: bytes,
      codec: Codec.pcm16,
      sampleRate: sampleRate,
      numChannels: 1,
    );
  }

  static final Map<String, double> _noteFrequencies = {
    'C': 261.63, 'C#': 277.18, 'Db': 277.18, 'D': 293.66, 'D#': 311.13, 'Eb': 311.13,
    'E': 329.63, 'Fb': 329.63, 'E#': 349.23, 'F': 349.23, 'F#': 369.99, 'Gb': 369.99,
    'G': 392.00, 'G#': 415.30, 'Ab': 415.30, 'A': 440.00, 'A#': 466.16, 'Bb': 466.16,
    'B': 493.88, 'Cb': 493.88, 'B#': 523.25,
  };
}