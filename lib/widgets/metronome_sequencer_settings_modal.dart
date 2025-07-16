// ─── metronome_sequencer_settings_modal.dart ──────────────────────────

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/metronome_sequencer_service.dart';

class MetronomeSequencerSettingsModal extends StatefulWidget {
  final bool initialEnabled;
  final Function(bool enabled) onToggle;

  const MetronomeSequencerSettingsModal({
    super.key,
    required this.initialEnabled,
    required this.onToggle,
  });

  @override
  State<MetronomeSequencerSettingsModal> createState() => _MetronomeSequencerSettingsModalState();
}

class _MetronomeSequencerSettingsModalState extends State<MetronomeSequencerSettingsModal> {
  late bool sequencerEnabled;
  List<String> savedSequences = [];

  @override
  void initState() {
    super.initState();
    sequencerEnabled = widget.initialEnabled;
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    savedSequences = await MetronomeSequencerService().listSavedSequences();
    if (mounted) setState(() {});
  }

  Future<void> _setSequencerEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('metronome_sequencer_enabled', value);
    widget.onToggle(value);

    if (mounted) setState(() => sequencerEnabled = value);

    if (value) {
      final loaded = savedSequences.isNotEmpty
          ? await MetronomeSequencerService().loadFromPrefs(savedSequences.first)
          : false;
      if (!loaded) {
        MetronomeSequencerService().initDefault();
      }
    }
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
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, nameController.text), child: Text("OK")),
        ],
      ),
    );

    if (entered != null) {
      String label;
      final trimmed = entered.trim();
      if (trimmed.isNotEmpty) {
        label = trimmed;
      } else {
        // generate default sequencer name
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
      await _loadSaved();
    }
  }

  Future<void> _confirmAndLoad(String label) async {
    if (!sequencerEnabled) {
      await _setSequencerEnabled(true);
    }
    await MetronomeSequencerService().loadFromPrefs(label);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirmAndDelete(String label) async {
    await MetronomeSequencerService().deleteSequence(label);
    await _loadSaved();
  }

  Future<void> _addNewDefault() async {
    if (!sequencerEnabled) {
      await _setSequencerEnabled(true);
    }
    MetronomeSequencerService().initDefault();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      builder: (_, controller) => SingleChildScrollView(
        controller: controller,
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            SwitchListTile(
              title: Text("Enable Sequencer"),
              value: sequencerEnabled,
              onChanged: (value) async {
                await _setSequencerEnabled(value);
                if (mounted) Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: Icon(Icons.add),
              title: Text("Add New Sequencer"),
              onTap: _addNewDefault,
            ),
            if (savedSequences.isNotEmpty) ...[
              SizedBox(height: 16),
              for (final label in savedSequences)
                ListTile(
                  title: Text(label),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.upload),
                        onPressed: () => _confirmAndLoad(label),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete),
                        onPressed: () => _confirmAndDelete(label),
                      ),
                    ],
                  ),
                ),
            ],
            ListTile(
              leading: Icon(Icons.save),
              title: Text("Save Sequencer"),
              onTap: _saveAsNew,
            ),
          ],
        ),
      ),
    );
  }
}