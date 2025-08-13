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
    } else {
      setState(() {}); // ensure rebuild to show sliders with loaded values
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

        final base = Theme.of(context);
        final themed = base.copyWith(
          textSelectionTheme: const TextSelectionThemeData(
            cursorColor: Colors.tealAccent,
            selectionColor: Color(0x4021FFC7),
            selectionHandleColor: Colors.tealAccent,
          ),
        );

        return Theme(
          data: themed,
          child: AlertDialog(
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8), // ↓ bottom from ~24 → 8
            backgroundColor: Colors.black,
            surfaceTintColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade800, width: 1), // <-- grey border
            ),
            content: TextField(
              controller: controller,
              maxLength: 20,
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.tealAccent,
              decoration: InputDecoration(
                labelText: 'New Name',
                labelStyle: const TextStyle(color: Colors.white70),
                counterText: '',
                filled: true,
                fillColor: Colors.white10,
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.white24),
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.tealAccent, width: 2),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(8, 2, 8, 8), // was vertical: 8
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.cancel, color: Colors.white70),
                label: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                icon: const Icon(Icons.check, color: Colors.black),
                label: const Text('OK', style: TextStyle(color: Colors.black)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (newName == null ||
        newName.isEmpty ||
        newName == oldLabel ||
        _sequenceLabels.contains(newName)) return;

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
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70) ??
        const TextStyle(fontSize: 12, color: Colors.white70);

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          // Grey outline at the top to indicate the modal top edge
          border: Border(top: BorderSide(color: Colors.grey.shade800, width: 1)),
        ),
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle(
          style: style,
          child: SwitchTheme(
            // Teal accent for all switches inside this modal
            data: SwitchThemeData(
              thumbColor: MaterialStateProperty.resolveWith((states) {
                if (states.contains(MaterialState.selected)) return Colors.tealAccent;
                return Colors.white70;
              }),
              trackColor: MaterialStateProperty.resolveWith((states) {
                if (states.contains(MaterialState.selected)) {
                  return Colors.tealAccent.withOpacity(0.35);
                }
                return Colors.white24;
              }),
              overlayColor: MaterialStateProperty.resolveWith((states) {
                if (states.contains(MaterialState.pressed) ||
                    states.contains(MaterialState.focused) ||
                    states.contains(MaterialState.hovered)) {
                  return Colors.tealAccent.withOpacity(0.15);
                }
                return Colors.transparent;
              }),
              splashRadius: 22,
            ),
            child: SliderTheme(
              // Teal accent for Swing/Shuffle sliders
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.tealAccent,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.tealAccent,
                overlayColor: Colors.tealAccent.withOpacity(0.15),
                valueIndicatorColor: Colors.tealAccent,
                tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 1.5),
                activeTickMarkColor: Colors.black87,
                inactiveTickMarkColor: Colors.white38,
                trackHeight: 2.5,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('Tempo Increase', style: TextStyle(color: Colors.white)),
                    value: appState.tempoIncreaseEnabled,
                    onChanged: appState.setTempoIncreaseEnabled,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
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
                            iconEnabledColor: Colors.white70,
                            items: List.generate(16, (i) => i + 1)
                                .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                                .toList(),
                            onChanged: (v) =>
                                appState.setTempoIncreaseValues(v!, appState.tempoIncreaseY),
                          ),
                          const SizedBox(width: 8),
                          const Text('every'),
                          const SizedBox(width: 8),
                          DropdownButton<int>(
                            value: appState.tempoIncreaseY,
                            dropdownColor: Colors.black,
                            style: const TextStyle(color: Colors.white),
                            iconEnabledColor: Colors.white70,
                            items: List.generate(16, (i) => i + 1)
                                .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                                .toList(),
                            onChanged: (v) =>
                                appState.setTempoIncreaseValues(appState.tempoIncreaseX, v!),
                          ),
                          const SizedBox(width: 8),
                          const Text('beats'),
                        ],
                      ),
                    ),

                  const Divider(color: Colors.white30),

                  Text('Swing: ${swingValue.round()}',
                      style: const TextStyle(color: Colors.white)),
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
                  Text('Shuffle: ${shuffleValue.round()}',
                      style: const TextStyle(color: Colors.white)),
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.tealAccent,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: _saveSequencer,
                        icon: const Icon(Icons.save),
                        label: const Text('Save'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.tealAccent,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    height: (_sequenceLabels.length * _tileHeight)
                        .clamp(0, _maxListHeight)
                        .toDouble(),
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
                          title: Text(label,
                              style: const TextStyle(color: Colors.tealAccent)),
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
        ),
      ),
    );
  }
}