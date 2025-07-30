// File: lib/widgets/sequencer_settings_modal.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/metronome_sequencer_service.dart';

class SequencerSettingsModal extends StatefulWidget {
  final bool initialEnabled;
  final Function(bool enabled) onToggle;
  const SequencerSettingsModal({super.key, required this.initialEnabled, required this.onToggle});

  @override
  State<SequencerSettingsModal> createState() => _SequencerSettingsModalState();
}

class _SequencerSettingsModalState extends State<SequencerSettingsModal> {
  late bool sequencerEnabled;
  List<String> savedSequences = [];

  bool tempoIncreaseEnabled = false;
  int tempoIncreaseX = 1;
  int tempoIncreaseY = 1;

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
    swingValue = prefs.getDouble('swing') ?? 0.0;
    shuffleValue = prefs.getDouble('shuffle') ?? 0.0;
    if (mounted) setState(() {});
  }

  Future<void> _setSequencerEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('metronome_sequencer_enabled', v);
    widget.onToggle(v);
    setState(() => sequencerEnabled = v);
    if (v) {
      final loaded = savedSequences.isNotEmpty
          ? await MetronomeSequencerService().loadFromPrefs(savedSequences.first)
          : false;
      if (!loaded) MetronomeSequencerService().initDefault();
    }
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
  Future<void> _setSwing(double v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('swing', v);
    setState(() => swingValue = v);
  }
  Future<void> _setShuffle(double v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('shuffle', v);
    setState(() => shuffleValue = v);
  }
  Future<void> _saveAsNew() async { /* same as previous */ }
  Future<void> _confirmAndLoad(String label) async { /* same as previous */ }
  Future<void> _confirmAndDelete(String label) async { /* same as previous */ }
  Future<void> _addNewDefault() async { /* same as previous */ }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize:12);
    return DraggableScrollableSheet(
      expand:false,
      builder: (_, ctrl) => SingleChildScrollView(
        controller: ctrl,
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
                padding: const EdgeInsets.symmetric(horizontal:16),
                child: DefaultTextStyle(
                  style: style,
                  child: Row(
                    children:[
                      const Text('Increase bpm by'),
                      const SizedBox(width:8),
                      DropdownButton<int>(value: tempoIncreaseX, items: List.generate(16,(i)=>i+1).map((v)=>DropdownMenuItem(value:v,child:Text('$v'))).toList(), onChanged:(v){if(v==null)return;setState(()=>tempoIncreaseX=v);_saveTempoValues();}),
                      const SizedBox(width:8),
                      const Text('every'),
                      const SizedBox(width:8),
                      DropdownButton<int>(value:tempoIncreaseY,items: List.generate(16,(i)=>i+1).map((v)=>DropdownMenuItem(value:v,child:Text('$v'))).toList(), onChanged:(v){if(v==null)return;setState(()=>tempoIncreaseY=v);_saveTempoValues();}),
                      const SizedBox(width:8),
                      const Text('beats'),
                    ],
                  ),
                ),
              ),
            const Divider(),
            SwitchListTile(
              title: const Text('Sequencer Mode'),
              value: sequencerEnabled,
              onChanged: _setSequencerEnabled,
            ),
            if (sequencerEnabled) ...[
              Text('Swing: \${swingValue.round()}', style: style),
              Slider(value:swingValue,min:0,max:75,divisions:75,label:swingValue.round().toString(),onChanged:_setSwing),
              Text('Shuffle: \${shuffleValue.round()}', style: style),
              Slider(value:shuffleValue,min:0,max:75,divisions:75,label:shuffleValue.round().toString(),onChanged:_setShuffle),
              const Divider(thickness:0.5,height:8),
              ListTile(dense:true,contentPadding:const EdgeInsets.only(left:16),leading:const Icon(Icons.add,size:20),title:const Text('Add New Sequencer'),onTap:_addNewDefault),
              ListTile(dense:true,contentPadding:const EdgeInsets.only(left:16),leading:const Icon(Icons.save,size:20),title:const Text('Save Sequencer'),onTap:_saveAsNew),
              if(savedSequences.isNotEmpty) ...[
                const Divider(thickness:0.5,height:8),
                for(final label in savedSequences)
                  ListTile(
                    dense:true,
                    contentPadding:const EdgeInsets.only(left:32),
                    title:Text(label),
                    trailing:Row(mainAxisSize:MainAxisSize.min,children:[
                      IconButton(icon:const Icon(Icons.upload), iconSize:20, onPressed:() => _confirmAndLoad(label)),
                      IconButton(icon:const Icon(Icons.delete), iconSize:20, onPressed:() => _confirmAndDelete(label)),
                    ]),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}