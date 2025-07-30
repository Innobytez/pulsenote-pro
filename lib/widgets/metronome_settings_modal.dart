// File: lib/widgets/metronome_settings_modal.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MetronomeSettingsModal extends StatefulWidget {
  const MetronomeSettingsModal({super.key});

  @override
  State<MetronomeSettingsModal> createState() => _MetronomeSettingsModalState();
}

class _MetronomeSettingsModalState extends State<MetronomeSettingsModal> {
  bool tempoIncreaseEnabled = false;
  int tempoIncreaseX = 1;
  int tempoIncreaseY = 1;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      tempoIncreaseEnabled = prefs.getBool('tempo_increase_enabled') ?? false;
      tempoIncreaseX = prefs.getInt('tempo_increase_x') ?? 1;
      tempoIncreaseY = prefs.getInt('tempo_increase_y') ?? 1;
    });
  }

  Future<void> _setTempoIncreaseEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tempo_increase_enabled', v);
    setState(() => tempoIncreaseEnabled = v);
  }

  Future<void> _saveTempoValues() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tempo_increase_x', tempoIncreaseX);
    await prefs.setInt('tempo_increase_y', tempoIncreaseY);
  }

  @override
  Widget build(BuildContext context) {
    final submenuStyle = Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 12);
    return DraggableScrollableSheet(
      expand: false,
      builder: (_, controller) => SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text('Tempo Increase'),
              value: tempoIncreaseEnabled,
              onChanged: _setTempoIncreaseEnabled,
            ),
            if (tempoIncreaseEnabled)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DefaultTextStyle(
                  style: submenuStyle,
                  child: Row(
                    children: [
                      const Text('Increase bpm by'),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: tempoIncreaseX,
                        items: List.generate(16, (i) => i + 1)
                            .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => tempoIncreaseX = v);
                          _saveTempoValues();
                        },
                      ),
                      const SizedBox(width: 8),
                      const Text('every'),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: tempoIncreaseY,
                        items: List.generate(16, (i) => i + 1)
                            .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => tempoIncreaseY = v);
                          _saveTempoValues();
                        },
                      ),
                      const SizedBox(width: 8),
                      const Text('beats'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}