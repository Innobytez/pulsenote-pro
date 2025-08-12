import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_state_service.dart';
import '../services/metronome_sequencer_service.dart';

class SequencerSettingsModal extends StatefulWidget {
  const SequencerSettingsModal({Key? key}) : super(key: key);

  @override
  State<SequencerSettingsModal> createState() => _SequencerSettingsModalState();
}

class _SequencerSettingsModalState extends State<SequencerSettingsModal>
    with TickerProviderStateMixin {
  List<String> _sequenceLabels = [];
  double swingValue = 0;
  double shuffleValue = 0;
  int? _selectedIndex;
  late SharedPreferences _prefs;

  static const double _tileHeight = 64;
  static const double _maxListHeight = 320;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    _prefs = await SharedPreferences.getInstance();
    swingValue = _prefs.getDouble('swing') ?? 0;
    shuffleValue = _prefs.getDouble('shuffle') ?? 0;
    final jsonString = _prefs.getString('saved_sequences');
    if (jsonString != null) {
      final List decoded = json.decode(jsonString);
      setState(() => _sequenceLabels = List<String>.from(decoded));
    }
  }

  Future<void> _saveLabelList() async {
    await _prefs.setString('saved_sequences', json.encode(_sequenceLabels));
  }

  Future<void> _saveSequencer() async {
    final label = _selectedIndex == null
        ? _generateNewName()
        : _sequenceLabels[_selectedIndex!];
    await MetronomeSequencerService().saveToPrefs(label);
    if (!_sequenceLabels.contains(label)) {
      setState(() => _sequenceLabels.insert(0, label));
      await _saveLabelList();
    }
  }

  String _generateNewName() {
    int i = 1;
    while (_sequenceLabels.contains('Sequencer $i')) {
      i++;
    }
    return 'Sequencer $i';
  }

  Future<void> _loadSequencer(int index) async {
    final label = _sequenceLabels[index];
    await MetronomeSequencerService().loadFromPrefs(label);
  }

  Future<void> _deleteSequencer(int index) async {
    final label = _sequenceLabels[index];
    await MetronomeSequencerService().deleteSequence(label);
    setState(() => _sequenceLabels.removeAt(index));
    await _saveLabelList();
  }

  Future<void> _renameSequencer(int index) async {
    final oldLabel = _sequenceLabels[index];
    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: oldLabel);
        return AlertDialog(
          title: const Text('Rename Sequencer'),
          content: TextField(
            controller: controller,
            maxLength: 20,
            decoration: const InputDecoration(
              labelText: 'New Name',
              counterText: '',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Icon(Icons.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Icon(Icons.check),
            ),
          ],
        );
      },
    );

    if (newName == null || newName.isEmpty || newName == oldLabel || _sequenceLabels.contains(newName)) return;

    final seqService = MetronomeSequencerService();
    final loaded = await seqService.loadFromPrefs(oldLabel);
    if (!loaded) return;

    await seqService.saveToPrefs(newName);
    await seqService.deleteSequence(oldLabel);

    setState(() => _sequenceLabels[index] = newName);
    await _saveLabelList();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateService>();
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70) ?? const TextStyle(fontSize: 12, color: Colors.white70);

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle(
          style: style,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Tempo Increase', style: TextStyle(color: Colors.white)),
                value: appState.tempoIncreaseEnabled,
                onChanged: appState.setTempoIncreaseEnabled,
              ),
              if (appState.tempoIncreaseEnabled)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text('Increase bpm by'),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: appState.tempoIncreaseX,
                        dropdownColor: Colors.black,
                        style: const TextStyle(color: Colors.white),
                        items: List.generate(16, (i) => i + 1).map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
                        onChanged: (v) => appState.setTempoIncreaseValues(v!, appState.tempoIncreaseY),
                      ),
                      const SizedBox(width: 8),
                      const Text('every'),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: appState.tempoIncreaseY,
                        dropdownColor: Colors.black,
                        style: const TextStyle(color: Colors.white),
                        items: List.generate(16, (i) => i + 1).map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
                        onChanged: (v) => appState.setTempoIncreaseValues(appState.tempoIncreaseX, v!),
                      ),
                      const SizedBox(width: 8),
                      const Text('beats'),
                    ],
                  ),
                ),

              const Divider(color: Colors.white30),

              Text('Swing: ${swingValue.round()}'),
              Slider(
                value: swingValue,
                min: 0,
                max: 75,
                divisions: 75,
                label: swingValue.round().toString(),
                onChanged: (v) async {
                  await _prefs.setDouble('swing', v);
                  setState(() => swingValue = v);
                },
              ),
              Text('Shuffle: ${shuffleValue.round()}'),
              Slider(
                value: shuffleValue,
                min: 0,
                max: 75,
                divisions: 75,
                label: shuffleValue.round().toString(),
                onChanged: (v) async {
                  await _prefs.setDouble('shuffle', v);
                  setState(() => shuffleValue = v);
                },
              ),

              const Divider(color: Colors.white30),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      MetronomeSequencerService().initDefault();
                      _loadInitial();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Create'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _saveSequencer,
                    icon: const Icon(Icons.save),
                    label: const Text('Save'),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              SizedBox(
                height: (_sequenceLabels.length * _tileHeight).clamp(0, _maxListHeight).toDouble(),
                child: ReorderableListView.builder(
                  itemCount: _sequenceLabels.length,
                  buildDefaultDragHandles: false,
                  physics: const ClampingScrollPhysics(),
                  onReorder: (oldIndex, newIndex) async {
                    if (newIndex > oldIndex) newIndex--;
                    setState(() {
                      final item = _sequenceLabels.removeAt(oldIndex);
                      _sequenceLabels.insert(newIndex, item);
                    });
                    await _saveLabelList();
                  },
                  itemBuilder: (context, i) {
                    final label = _sequenceLabels[i];
                    return ListTile(
                      key: ValueKey(label),
                      title: Text(label, style: const TextStyle(color: Colors.tealAccent)),
                      leading: ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle, color: Colors.white),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.white),
                            onPressed: () => _renameSequencer(i),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.white),
                            onPressed: () => _deleteSequencer(i),
                          ),
                        ],
                      ),
                      onTap: () => _loadSequencer(i),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}