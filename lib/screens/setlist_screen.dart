// File: lib/screens/setlist_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_state_service.dart';
import '../services/audio_service.dart';
import '../services/tick_service.dart';
import '../widgets/wheel_picker.dart';

class BpmEntry {
  int bpm;
  String? label;

  BpmEntry({required this.bpm, this.label});

  Map<String, dynamic> toJson() => {'bpm': bpm, 'label': label};
  factory BpmEntry.fromJson(Map<String, dynamic> json) =>
      BpmEntry(bpm: json['bpm'], label: json['label']);

  String get displayLabel => (label?.isNotEmpty ?? false) ? label! : '$bpm BPM';
}

class SetlistScreen extends StatefulWidget {
  @override
  _SetlistScreenState createState() => _SetlistScreenState();
}

class _SetlistScreenState extends State<SetlistScreen> {
  // name -> entries
  Map<String, List<BpmEntry>> _setlists = {};
  String _currentSetlist = 'Setlist 1';

  List<BpmEntry> get _setlist => _setlists[_currentSetlist] ?? <BpmEntry>[];

  late final ScrollController _scrollController;
  final TickService _tick = TickService();
  StreamSubscription<void>? _tickSub;
  int? _playingIndex;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _loadSetlists();
  }

  // ---------- Persistence + migration ----------

  Future<void> _loadSetlists() async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString('setlist');     // old: single list
    final packed = prefs.getString('setlists');    // new: map<string, list>
    final cur    = prefs.getString('current_setlist');

    if (packed == null && legacy != null) {
      final List decoded = json.decode(legacy);
      _setlists = {'Setlist 1': decoded.map((e) => BpmEntry.fromJson(e)).toList()};
      _currentSetlist = 'Setlist 1';
      await _saveSetlists();
      // (optional) await prefs.remove('setlist');
    } else if (packed != null) {
      final Map<String, dynamic> map = json.decode(packed);
      _setlists = map.map((k, v) => MapEntry(
        k, (v as List).map((e) => BpmEntry.fromJson(e)).toList(),
      ));
      _currentSetlist = cur ?? _firstOrDefaultName();
      if (!_setlists.containsKey(_currentSetlist)) {
        _currentSetlist = _firstOrDefaultName();
      }
    } else {
      _setlists = {'Setlist 1': <BpmEntry>[]};
      _currentSetlist = 'Setlist 1';
      await _saveSetlists();
    }

    setState(() {});
  }

  Future<void> _saveSetlists() async {
    final prefs = await SharedPreferences.getInstance();
    final mapJson = _setlists.map((k, v) => MapEntry(k, v.map((e) => e.toJson()).toList()));
    await prefs.setString('setlists', json.encode(mapJson));
    await prefs.setString('current_setlist', _currentSetlist);
  }

  Future<void> _renameSetlist(String oldName) async {
    final newName = await _promptForName(
      context, title: 'Rename Setlist', initial: oldName,
    );
    if (newName == null || newName.isEmpty || newName == oldName || _setlists.containsKey(newName)) {
      return;
    }

    setState(() {
      final entries = _setlists.remove(oldName)!;
      _setlists[newName] = entries;
      if (_currentSetlist == oldName) _currentSetlist = newName;
    });
    await _saveSetlists();
  }

  Future<void> _deleteSetlist(String name) async {
    if (_setlists.length <= 1) return; // don't allow deleting the last setlist
    setState(() {
      _setlists.remove(name);
      if (_currentSetlist == name) {
        _currentSetlist = _firstOrDefaultName();
      }
    });
    await _saveSetlists();
  }

  String _firstOrDefaultName() => _setlists.keys.isNotEmpty ? _setlists.keys.first : 'Setlist 1';

  String _generateSetlistName() {
    int i = 1;
    while (_setlists.containsKey('Setlist $i')) i++;
    return 'Setlist $i';
  }

  // ---------- Entry CRUD ----------

  Future<void> _addEntry() async {
    _stopMetronome();

    final entry = await showDialog<BpmEntry>(
      context: context,
      builder: (_) => _BpmEntryDialog(),
    );
    if (entry == null) return;

    setState(() {
      _setlists[_currentSetlist] ??= <BpmEntry>[];
      _setlists[_currentSetlist]!.insert(0, entry);
      if (_playingIndex != null) _playingIndex = _playingIndex! + 1;
    });
    await _saveSetlists();

    await Future.delayed(const Duration(milliseconds: 100));
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut,
      );
    }
  }

  Future<void> _editEntry(int index) async {
    final entry = await showDialog<BpmEntry>(
      context: context,
      builder: (_) => _BpmEntryDialog(existing: _setlist[index]),
    );
    if (entry == null) return;
    setState(() => _setlist[index] = entry);
    await _saveSetlists();
  }

  Future<void> _deleteEntry(int index) async {
    _stopMetronome();
    setState(() => _setlist.removeAt(index));
    await _saveSetlists();
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
    await _saveSetlists();
  }

  // ---------- Playback ----------

  void _startMetronome(int bpm, int index) {
    _stopMetronome();
    _tick.start(bpm);
    _tickSub = _tick.tickStream.listen((_) {
      if (context.read<AppStateService>().soundOn) {
        AudioService.playClick();
      }
    });
    setState(() => _playingIndex = index);
  }

  void _stopMetronome() {
    _tickSub?.cancel();
    _tick.stop();
    setState(() => _playingIndex = null);
  }
  
  Future<void> _openSetlistPicker() async {
    _stopMetronome(); // ensure nothing is playing while picking

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        const rowHeight = 56.0;
        final maxBodyHeight = MediaQuery.of(ctx).size.height * 0.5;

        // Capture the StatefulBuilder's setState so actions can refresh content
        void Function(void Function())? refreshDialog;

        return AlertDialog(
          backgroundColor: Colors.black,
          surfaceTintColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade800, width: 1),
          ),
          title: const Text('Choose Setlist', style: TextStyle(color: Colors.white)),
          content: StatefulBuilder(
            builder: (ctx, setLocal) {
              refreshDialog = setLocal; // <-- capture for use in actions

              final names = _setlists.keys.toList()..sort();
              final estimated = names.length * rowHeight;

              Widget buildTile(String name) {
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Radio<String>(
                    value: name,
                    groupValue: _currentSetlist,
                    activeColor: Colors.tealAccent,
                    onChanged: (v) {
                      if (v == null) return;
                      // Update the screen behind the dialog immediately
                      setState(() => _currentSetlist = v);
                      _saveSetlists();
                      setLocal(() {}); // refresh selection highlight in the dialog
                    },
                  ),
                  title: Text(name, style: const TextStyle(color: Colors.white)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Rename',
                        icon: const Icon(Icons.edit, color: Colors.white70),
                        onPressed: () async {
                          await _renameSetlist(name);
                          setLocal(() {}); // refresh list
                        },
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete, color: Colors.white70),
                        onPressed: () async {
                          await _deleteSetlist(name);
                          setLocal(() {});
                        },
                      ),
                    ],
                  ),
                );
              }

              final contentChild = (estimated <= maxBodyHeight)
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...names.map(buildTile),
                        // (New setlist button moved to actions row)
                      ],
                    )
                  : SizedBox(
                      height: maxBodyHeight,
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: names.length, // only tiles here
                        itemBuilder: (_, i) => buildTile(names[i]),
                      ),
                    );

              return contentChild;
            },
          ),
          actions: [
            // ⬇️ New setlist now inline with Close
            ElevatedButton.icon(
              icon: const Icon(Icons.add, color: Colors.black),
              label: const Text('New setlist', style: TextStyle(color: Colors.black)),
              onPressed: () async {
                final defaultName = _generateSetlistName();
                final name = await _promptForName(
                  context, title: 'New Setlist', initial: defaultName,
                );
                if (name == null || name.isEmpty || _setlists.containsKey(name)) return;
                setState(() {
                  _setlists[name] = <BpmEntry>[];
                  _currentSetlist = name; // select it immediately
                });
                await _saveSetlists();
                refreshDialog?.call(() {}); // refresh dialog content without closing
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.tealAccent,
                foregroundColor: Colors.black,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Icon(Icons.close, color: Colors.white70),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _promptForName(BuildContext context,
      {required String title, String? initial}) {
    final controller = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade800, width: 1),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLength: 24,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Name',
            counterText: '',
            labelStyle: TextStyle(color: Colors.white70),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.tealAccent, width: 2),
            ),
            filled: true,
            fillColor: Colors.white10,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Icon(Icons.cancel, color: Colors.white70),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.tealAccent,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Icon(Icons.check, color: Colors.black),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tickSub?.cancel();
    _tick.stop();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateService>();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // List
            Expanded(
              child: Row(
                children: [
                  SizedBox(width: MediaQuery.of(context).size.width * 0.1),
                  Expanded(
                    child: ReorderableListView(
                      key: const PageStorageKey('setlist'),
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

            // Bottom controls: match other screens (iconSize=40, no divider)
            SizedBox(
              height: 100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // mute
                  IconButton(
                    iconSize: 40,
                    icon: Icon(appState.soundOn ? Icons.volume_up : Icons.volume_off),
                    onPressed: () => appState.setSoundOn(!appState.soundOn),
                  ),
                  // add entry
                  IconButton(
                    iconSize: 40,
                    icon: const Icon(Icons.add_circle),
                    onPressed: _addEntry,
                  ),
                  // settings (choose setlist)
                  IconButton(
                    iconSize: 40,
                    icon: const Icon(Icons.settings),
                    onPressed: _openSetlistPicker,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- List item ----------

  Widget _buildListItem(BuildContext context, int index) {
    final entry = _setlist[index];
    final isItemPlaying = _playingIndex == index;

    return ListTile(
      key: ValueKey('$_currentSetlist-$index-${entry.hashCode}'),
      title: Text(
        entry.displayLabel,
        overflow: TextOverflow.ellipsis,
      ),
      leading: IconButton(
        icon: Icon(isItemPlaying ? Icons.stop : Icons.play_arrow),
        onPressed: () => isItemPlaying
            ? _stopMetronome()
            : _startMetronome(entry.bpm, index),
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

/// ===== Add/Edit entry dialog (with Tap Tempo) =====
class _BpmEntryDialog extends StatefulWidget {
  final BpmEntry? existing;
  const _BpmEntryDialog({this.existing});

  @override
  _BpmEntryDialogState createState() => _BpmEntryDialogState();
}

class _BpmEntryDialogState extends State<_BpmEntryDialog> {
  final TextEditingController _labelController = TextEditingController();
  int _bpm = 100;

  // tap tempo state
  final List<DateTime> _tapTimes = [];
  Timer? _tapResetTimer;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _labelController.text = widget.existing!.label ?? '';
      _bpm = widget.existing!.bpm;
    }
  }

  void _tapTempo() {
    final now = DateTime.now();
    _tapTimes.add(now);

    _tapResetTimer?.cancel();
    _tapResetTimer = Timer(const Duration(seconds: 6), () => _tapTimes.clear());
    if (_tapTimes.length > 4) _tapTimes.removeAt(0);

    if (_tapTimes.length >= 2) {
      final intervals = <int>[];
      for (int i = 1; i < _tapTimes.length; i++) {
        intervals.add(_tapTimes[i].difference(_tapTimes[i - 1]).inMilliseconds);
      }
      final last = intervals.last;
      final dev = (last * 0.2).round();
      final filtered = intervals.where((ms) => (ms - last).abs() <= dev).toList();
      final avg = filtered.isNotEmpty
          ? filtered.reduce((a, b) => a + b) ~/ filtered.length
          : last;
      final newBpm = (60000 / avg).clamp(10, 240).round();
      setState(() => _bpm = newBpm);
    }

    if (context.read<AppStateService>().soundOn) {
      AudioService.playClick();
    }
  }

  @override
  void dispose() {
    _tapResetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.black,
      surfaceTintColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade800, width: 1),
      ),
      title: Text(
        widget.existing == null ? 'Add Setlist Entry' : 'Edit Setlist Entry',
        style: const TextStyle(color: Colors.white),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _labelController,
            maxLength: 20,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Label',
              counterText: '',
              labelStyle: TextStyle(color: Colors.white70),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.tealAccent, width: 2),
              ),
              filled: true,
              fillColor: Colors.white10,
            ),
          ),
          const SizedBox(height: 10),
          WheelPicker(
            initialBpm: _bpm,
            minBpm: 10,
            maxBpm: 240,
            wheelSize: 160,
            onBpmChanged: (val) => setState(() => _bpm = val),
          ),
          const SizedBox(height: 8),
          // Tap tempo button
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _tapTempo,
              icon: const Icon(Icons.touch_app, color: Colors.tealAccent),
              label: const Text('Tap tempo', style: TextStyle(color: Colors.tealAccent)),
              style: TextButton.styleFrom(
                foregroundColor: Colors.tealAccent,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Icon(Icons.cancel, color: Colors.white70),
        ),
        ElevatedButton(
          onPressed: () {
            final label = _labelController.text.trim();
            Navigator.pop(
              context,
              BpmEntry(bpm: _bpm, label: label.isEmpty ? null : label),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.tealAccent,
            foregroundColor: Colors.black,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Icon(Icons.check, color: Colors.black),
        ),
      ],
    );
  }
}