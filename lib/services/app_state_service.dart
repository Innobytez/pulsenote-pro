// File: lib/services/app_state_service.dart

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppStateService extends ChangeNotifier {
  static final AppStateService _instance = AppStateService._internal();
  factory AppStateService() => _instance;
  AppStateService._internal() {
    _loadFromPrefs();
  }

  // ─── BPM ────────────────────────────────────────────
  int _bpm = 60;
  int get bpm => _bpm;
  Future<void> setBpm(int v) async {
    v = v.clamp(10, 240);
    if (v == _bpm) return;
    _bpm = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('metronome_screen_bpm', _bpm);
    notifyListeners();
  }

  // ─── SOUND-ON ───────────────────────────────────────
  bool _soundOn = true;
  bool get soundOn => _soundOn;
  Future<void> setSoundOn(bool v) async {
    _soundOn = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sound_on', v);
    notifyListeners();
  }

  // ─── TEMPO-INCREASE ─────────────────────────────────
  bool _tempoIncreaseEnabled = false;
  int  _tempoIncreaseX       = 1;
  int  _tempoIncreaseY       = 1;

  bool get tempoIncreaseEnabled => _tempoIncreaseEnabled;
  int  get tempoIncreaseX       => _tempoIncreaseX;
  int  get tempoIncreaseY       => _tempoIncreaseY;

  Future<void> setTempoIncreaseEnabled(bool v) async {
    _tempoIncreaseEnabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tempo_increase_enabled', v);
    notifyListeners();
  }

  Future<void> setTempoIncreaseValues(int x, int y) async {
    _tempoIncreaseX = x;
    _tempoIncreaseY = y;
    final prefs = await SharedPreferences.getInstance();
    await prefs
      ..setInt('tempo_increase_x', x)
      ..setInt('tempo_increase_y', y);
    notifyListeners();
  }

  // ─── LOAD ONCE ─────────────────────────────────────
  Future<void> _loadFromPrefs() async {
    final p = await SharedPreferences.getInstance();
    _bpm                    = (p.getInt('metronome_screen_bpm') ?? 60).clamp(10, 240);
    _soundOn                = p.getBool('sound_on') ?? true;
    _tempoIncreaseEnabled   = p.getBool('tempo_increase_enabled') ?? false;
    _tempoIncreaseX         = p.getInt('tempo_increase_x') ?? 1;
    _tempoIncreaseY         = p.getInt('tempo_increase_y') ?? 1;
    notifyListeners();
  }
}