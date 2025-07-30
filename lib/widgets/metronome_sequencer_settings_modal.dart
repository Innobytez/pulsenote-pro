// ─── metronome_sequencer_settings_modal.dart ──────────────────────────

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/metronome_sequencer_service.dart';
import 'dart:convert';

class MetronomeSequencerSettingsModal extends StatefulWidget {
  final bool initialEnabled;
  final Function(bool enabled) onToggle;

  const MetronomeSequencerSettingsModal({
    super.key,
    required this.initialEnabled,
    required this.onToggle,
  });

  @override
  State<MetronomeSequencerSettingsModal> createState() =>
      _MetronomeSequencerSettingsModalState();
}

class _MetronomeSequencerSettingsModalState
    extends State<MetronomeSequencerSettingsModal> {
  late bool sequencerEnabled;
  List<String> savedSequences = [];

  bool tempoIncreaseEnabled = false;
  int tempoIncreaseX = 1;
  int tempoIncreaseY = 1;

  bool polyrhythmEnabled = false;
  bool polyrhythmAccented = false;

  double swingValue = 0;
  double shuffleValue = 0;

  @override
  void initState() {
    super.initState();
    sequencerEnabled = widget.initialEnabled;
    _loadAll();
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    savedSequences = await MetronomeSequencerService().listSavedSequences();

    tempoIncreaseEnabled = prefs.getBool('tempo_increase_enabled') ?? false;
    tempoIncreaseX = prefs.getInt('tempo_increase_x') ?? 1;
    tempoIncreaseY = prefs.getInt('tempo_increase_y') ?? 1;

    polyrhythmEnabled = prefs.getBool('polyrhythm_enabled') ?? false;
    polyrhythmAccented = prefs.getBool('polyrhythm_accented') ?? false;

    swingValue = prefs.getDouble('swing') ?? 0.0;
    shuffleValue = prefs.getDouble('shuffle') ?? 0.0;

    if (mounted) setState(() {});
  }

  Future<void> _setSequencerEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('metronome_sequencer_enabled', value);
    widget.onToggle(value);
    setState(() => sequencerEnabled = value);

    if (value && polyrhythmEnabled) {
      await prefs.setBool('polyrhythm_enabled', false);
      setState(() => polyrhythmEnabled = false);
    }

    if (value) {
      final loaded = savedSequences.isNotEmpty
          ? await MetronomeSequencerService().loadFromPrefs(savedSequences.first)
          : false;
      if (!loaded) {
        MetronomeSequencerService().initDefault();
      }
    }
  }

  Future<void> _setTempoIncreaseEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tempo_increase_enabled', value);
    setState(() => tempoIncreaseEnabled = value);
  }

  Future<void> _setPolyrhythmEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('polyrhythm_enabled', value);
    setState(() => polyrhythmEnabled = value);

    if (value && sequencerEnabled) {
      await prefs.setBool('metronome_sequencer_enabled', false);
      widget.onToggle(false);
      setState(() => sequencerEnabled = false);
    }
  }

  Future<void> _saveTempoValues() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tempo_increase_x', tempoIncreaseX);
    await prefs.setInt('tempo_increase_y', tempoIncreaseY);
  }

  Future<void> _setSwing(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('swing', value);
    setState(() => swingValue = value);
  }

  Future<void> _setShuffle(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('shuffle', value);
    setState(() => shuffleValue = value);
  }

  Future<void> _saveAsNew() async {
    final nameController = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Save As"),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(hintText: 'Enter name (optional)'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: Theme.of(context).textTheme.bodySmall),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: Text("OK", style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );

    if (entered != null) {
      String label;
      final trimmed = entered.trim();
      if (trimmed.isNotEmpty) {
        label = trimmed;
      } else {
        const base = "Sequencer ";
        int index = 1;
        final existing = Set<String>.from(savedSequences);
        String candidate;
        do {
          candidate = '$base$index';
          index++;
        } while (existing.contains(candidate));
        label = candidate;
      }
      await MetronomeSequencerService().saveToPrefs(label);
      await _loadAll();
    }
  }

  Future<void> _confirmAndLoad(String label) async {
    if (!sequencerEnabled) await _setSequencerEnabled(true);
    // 1) load the sequence itself
    final loaded = await MetronomeSequencerService().loadFromPrefs(label);
    if (loaded) {
      final prefs = await SharedPreferences.getInstance();
      // 2) re-read its saved swing/shuffle (0–100) from your JSON
      final raw = prefs.getString('sequencer_metronome_$label');
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final sv = (data['swing']   as int? ?? 0).toDouble().clamp(0.0, 75.0);
        final sh = (data['shuffle'] as int? ?? 0).toDouble().clamp(0.0, 75.0);
        // 3) store back into prefs so _loadAll() picks it up next time
        await prefs.setDouble('swing',   sv);
        await prefs.setDouble('shuffle', sh);
        // 4) update this modal's sliders immediately
        setState(() {
          swingValue   = sv;
          shuffleValue = sh;
        });
      }
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirmAndDelete(String label) async {
    await MetronomeSequencerService().deleteSequence(label);
    await _loadAll();
  }

  Future<void> _addNewDefault() async {
    if (!sequencerEnabled) await _setSequencerEnabled(true);
    MetronomeSequencerService().initDefault();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // submenu text style fallback
    final TextStyle submenuStyle =
        Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 12);

    return DraggableScrollableSheet(
      expand: false,
      builder: (_, controller) => SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Tempo Increase Mode ─────────────────
            SwitchListTile(
              title: Text("Tempo Increase"),
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
                      Text("Increase bpm by"),
                      SizedBox(width: 8),
                      DropdownButton<int>(
                        value: tempoIncreaseX,
                        items: List.generate(16, (i) => i + 1)
                            .map((i) => DropdownMenuItem(
                                  value: i,
                                  child: Text("$i"),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => tempoIncreaseX = v);
                          _saveTempoValues();
                        },
                      ),
                      SizedBox(width: 8),
                      Text("every"),
                      SizedBox(width: 8),
                      DropdownButton<int>(
                        value: tempoIncreaseY,
                        items: List.generate(16, (i) => i + 1)
                            .map((i) => DropdownMenuItem(
                                  value: i,
                                  child: Text("$i"),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => tempoIncreaseY = v);
                          _saveTempoValues();
                        },
                      ),
                      SizedBox(width: 8),
                      Text("beats"),
                    ],
                  ),
                ),
              ),
            Divider(),

            // ─── Polyrhythm Mode ────────────────────
            SwitchListTile(
              title: Text("Polyrhythm Mode"),
              value: polyrhythmEnabled,
              onChanged: _setPolyrhythmEnabled,
            ),
            if (polyrhythmEnabled)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 24),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 0),
                  title: Text(
                    "Polyrhythm uses accented clicks",
                    style: submenuStyle,
                  ),
                  trailing: Transform.scale(
                    scale: 0.8,    // 80% of normal switch size
                    child: Switch(
                      value: polyrhythmAccented,
                      onChanged: (v) async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('polyrhythm_accented', v);
                        setState(() => polyrhythmAccented = v);
                      },
                    ),
                  ),
                ),
              ),
            Divider(),

            // ─── Sequencer Mode ─────────────────────
            SwitchListTile(
              title: Text("Sequencer Mode"),
              value: sequencerEnabled,
              onChanged: _setSequencerEnabled,
            ),

            if (sequencerEnabled) ...[
              DefaultTextStyle(
                style: submenuStyle,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // swing & shuffle
                    Text("Swing: ${swingValue.round()}", style: submenuStyle),
                    Slider(
                      value: swingValue,
                      min: 0,
                      max: 75,
                      divisions: 75,
                      label: swingValue.round().toString(),
                      onChanged: _setSwing,
                    ),
                    Text("Shuffle: ${shuffleValue.round()}", style: submenuStyle),
                    Slider(
                      value: shuffleValue,
                      min: 0,
                      max: 75,
                      divisions: 75,
                      label: shuffleValue.round().toString(),
                      onChanged: _setShuffle,
                    ),

                    Divider(thickness: 0.5, height: 8),

                    // add & save
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 16),
                      leading: const Icon(Icons.add, size: 20),
                      title: Text("Add New Sequencer"),
                      onTap: _addNewDefault,
                    ),
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 16),
                      leading: const Icon(Icons.save, size: 20),
                      title: Text("Save Sequencer"),
                      onTap: _saveAsNew,
                    ),

                    if (savedSequences.isNotEmpty) ...[
                      Divider(thickness: 0.5, height: 8),
                      for (final label in savedSequences)
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.only(left: 32),
                          title: Text(label),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.upload),
                                iconSize: 20,
                                onPressed: () => _confirmAndLoad(label),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                iconSize: 20,
                                onPressed: () => _confirmAndDelete(label),
                              ),
                            ],
                          ),
                        ),
                    ],

                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}