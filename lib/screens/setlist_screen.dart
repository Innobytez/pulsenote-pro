import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import '../models/bpm_entry.dart';
import '../services/audio_service.dart';
import '../services/tick_service.dart';

class SetlistScreen extends StatefulWidget {
  @override
  _SetlistScreenState createState() => _SetlistScreenState();
}

class _SetlistScreenState extends State<SetlistScreen> {
  final List<BpmEntry> _setlist = [];
  late final ScrollController _scrollController;
  int? _playingIndex;
  StreamSubscription<void>? _tickSub;

  @override
  void initState() {
    _scrollController = ScrollController();
    super.initState();
    _loadSetlist();
  }

  Future<void> _loadSetlist() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('setlist');
    if (jsonString != null) {
      final List decoded = json.decode(jsonString);
      setState(() {
        _setlist.clear();
        _setlist.addAll(decoded.map((e) => BpmEntry.fromJson(e)).toList());
      });
    }
  }

  Future<void> _saveSetlist() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = json.encode(_setlist.map((e) => e.toJson()).toList());
    await prefs.setString('setlist', jsonString);
  }

  Future<void> _addEntry() async {
    final entry = await showDialog<BpmEntry>(
      context: context,
      builder: (context) => _BpmEntryDialog(),
    );
    if (entry != null) {
      setState(() => _setlist.insert(0, entry));
      await _saveSetlist();
      await Future.delayed(Duration(milliseconds: 100));
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  Future<void> _editEntry(int index) async {
    final entry = await showDialog<BpmEntry>(
      context: context,
      builder: (context) => _BpmEntryDialog(existing: _setlist[index]),
    );
    if (entry != null) {
      setState(() => _setlist[index] = entry);
      await _saveSetlist();
    }
  }

  Future<void> _deleteEntry(int index) async {
    _stopMetronome();
    setState(() => _setlist.removeAt(index));
    await _saveSetlist();
  }

  void _startMetronome(int bpm, int index) {
    _stopMetronome();
    TickService().start(bpm);
    _tickSub = TickService().tickStream.listen((_) => AudioService.playClick());
    setState(() => _playingIndex = index);
  }

  void _stopMetronome() {
    _tickSub?.cancel();
    TickService().stop();
    setState(() => _playingIndex = null);
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final item = _setlist.removeAt(oldIndex);
    _setlist.insert(newIndex, item);

    if (_playingIndex != null) {
      if (_playingIndex == oldIndex) {
        _playingIndex = newIndex;
      } else if (oldIndex < _playingIndex! && newIndex >= _playingIndex!) {
        _playingIndex = _playingIndex! - 1;
      } else if (oldIndex > _playingIndex! && newIndex <= _playingIndex!) {
        _playingIndex = _playingIndex! + 1;
      }
    }

    setState(() {});
    await _saveSetlist();
  }

  @override
  void dispose() {
    _tickSub?.cancel();
    TickService().stop();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  SizedBox(width: MediaQuery.of(context).size.width * 0.1),
                  Expanded(
                    child: ReorderableListView(
                      key: PageStorageKey('setlist'),
                      scrollController: _scrollController,
                      reverse: true,
                      padding: EdgeInsets.zero,
                      onReorder: _onReorder,
                      children: [
                        for (int index = 0; index < _setlist.length; index++)
                          _buildListItem(context, index),
                      ],
                    ),
                  ),
                  SizedBox(width: MediaQuery.of(context).size.width * 0.1),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16, top: 8),
              child: Center(
                child: ElevatedButton(
                  onPressed: _addEntry,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    backgroundColor: Colors.tealAccent,
                    foregroundColor: Colors.black,
                  ),
                  child: const Icon(Icons.add),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListItem(BuildContext context, int index) {
    final entry = _setlist[index];
    final isItemPlaying = _playingIndex == index;

    return ListTile(
      key: ValueKey(entry.hashCode),
      title: Text('${entry.label?.trim().isEmpty ?? true ? '${entry.bpm} BPM' : entry.label!}', overflow: TextOverflow.ellipsis),
      leading: IconButton(
        icon: Icon(isItemPlaying ? Icons.stop : Icons.play_arrow),
        onPressed: () =>
            isItemPlaying ? _stopMetronome() : _startMetronome(entry.bpm, index),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _editEntry(index),
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => _deleteEntry(index),
          ),
          ReorderableDragStartListener(
            index: index,
            child: const Icon(Icons.drag_handle),
          ),
        ],
      ),
    );
  }
}

class _BpmEntryDialog extends StatefulWidget {
  final BpmEntry? existing;
  const _BpmEntryDialog({this.existing});

  @override
  _BpmEntryDialogState createState() => _BpmEntryDialogState();
}

class _BpmEntryDialogState extends State<_BpmEntryDialog> {
  final TextEditingController _labelController = TextEditingController();
  int _bpm = 100;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _labelController.text = widget.existing!.label ?? '';
      _bpm = widget.existing!.bpm;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Add Setlist Entry'
          : 'Edit Setlist Entry'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _labelController,
            maxLength: 20,
            decoration: const InputDecoration(
              labelText: 'Label',
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Slider(
                value: _bpm.toDouble(),
                min: 10,
                max: 240,
                divisions: 230,
                label: '$_bpm',
                onChanged: (val) => setState(() => _bpm = val.round()),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'BPM: $_bpm',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Icon(Icons.cancel),
        ),
        ElevatedButton(
          onPressed: () {
            final label = _labelController.text.trim();
            Navigator.pop(
              context,
              BpmEntry(
                bpm: _bpm,
                label: label.isEmpty ? null : label,
              ),
            );
          },
          child: const Icon(Icons.check),
        ),
      ],
    );
  }
}
