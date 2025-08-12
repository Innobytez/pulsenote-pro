import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path_provider/path_provider.dart';

class AudioService {
  static final SoLoud _soloud = SoLoud.instance;
  static bool _initialized = false;
  static late Directory _tempDir;
  static final Map<String, AudioSource> _audioCache = {};

  static Future<void> _init() async {
    if (_initialized) return;
    await _soloud.init(bufferSize: 256);
    _tempDir = Directory('${(await getTemporaryDirectory()).path}/pulsenote');
    if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
    _tempDir.createSync();

    await _prepareAndCache('click', _generateSineWaveWav(frequency: 1000, durationMs: 25, fadeOut: true));
    await _prepareAndCache('silent', _generateSilentWav());
    await _prepareAndCache('accent_click', _generateSineWaveWav(frequency: 1500, durationMs: 25, amplitude: 1.0, fadeOut: true));
    for (final note in _noteFrequencies.keys) {
      final freq = _noteFrequencies[note]!;
      await _prepareAndCache('note_$note', _generateSineWaveWav(frequency: freq, durationMs: 300));
    }

    _initialized = true;
  }

  static Future<void> warmUp() async {
    await _init();
    _soloud.play(_audioCache['silent']!);
  }

  static Future<void> playClick() async {
    await _init();
    _soloud.play(_audioCache['click']!);
  }

  static Future<void> playAccentClick() async {
    await _init();
    _soloud.play(_audioCache['accent_click']!);
  }

  static Future<void> playNote(String note) async {
    await _init();
    final src = _audioCache['note_$note'] ?? _audioCache['note_A']!;
    _soloud.play(src);
  }

  static Future<void> _prepareAndCache(String name, Uint8List wavBytes) async {
    final path = '${_tempDir.path}/$name.wav';
    await File(path).writeAsBytes(wavBytes, flush: true);
    _audioCache[name] = await _soloud.loadFile(path);
  }

  static Uint8List _generateSilentWav() {
    const sr = 44100, dur = 30;
    final samples = (sr * dur / 1000).round();
    return _wrapWav(Uint8List.view(Int16List(samples).buffer), sr);
  }

  static Uint8List _generateSineWaveWav({
    required double frequency,
    required int durationMs,
    double amplitude = 0.9,
    bool fadeOut = true,
  }) {
    const sr = 44100;
    final samples = (sr * durationMs / 1000).round();
    final buffer = Int16List(samples);
    for (var i = 0; i < samples; i++) {
      final t = i / sr;
      final env = fadeOut ? (1 - i / samples) : 1.0;
      buffer[i] = (sin(2 * pi * frequency * t) * env * amplitude * 32767).toInt();
    }
    return _wrapWav(Uint8List.view(buffer.buffer), sr);
  }

  static Uint8List _wrapWav(Uint8List pcm, int sr) {
    const ch = 1, bits = 16;
    final br = sr * ch * bits ~/ 8;
    final ba = ch * bits ~/ 8;
    final dl = pcm.length;
    final cs = 36 + dl;
    final builder = BytesBuilder()
      ..add(ascii.encode('RIFF'))
      ..add(_i32LE(cs))
      ..add(ascii.encode('WAVEfmt '))
      ..add(_i32LE(16))
      ..add(_i16LE(1))
      ..add(_i16LE(ch))
      ..add(_i32LE(sr))
      ..add(_i32LE(br))
      ..add(_i16LE(ba))
      ..add(_i16LE(bits))
      ..add(ascii.encode('data'))
      ..add(_i32LE(dl))
      ..add(pcm);
    return builder.toBytes();
  }

  static List<int> _i16LE(int v) => [v & 0xFF, (v >> 8) & 0xFF];
  static List<int> _i32LE(int v) => [
    v & 0xFF,
    (v >> 8) & 0xFF,
    (v >> 16) & 0xFF,
    (v >> 24) & 0xFF,
  ];

  static final _noteFrequencies = <String, double>{
    'C': 261.63, 'C#': 277.18, 'Db': 277.18, 'D': 293.66,
    'D#': 311.13, 'Eb': 311.13, 'E': 329.63, 'F': 349.23,
    'F#': 369.99, 'Gb': 369.99, 'G': 392.00, 'G#': 415.30,
    'Ab': 415.30, 'A': 440.00, 'A#': 466.16, 'Bb': 466.16,
    'B': 493.88, 'Cb': 493.88, 'B#': 523.25,
  };
}