// File: lib/screens/setlist_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_state_service.dart';
import '../services/audio_service.dart';
import '../services/tick_service.dart';
import '../services/system_media_handler.dart';
import '../services/playback_coordinator.dart';
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
  final bool active; // stop metronome when leaving tab
  const SetlistScreen({super.key, required this.active});

  @override
  State<SetlistScreen> createState() => _SetlistScreenState();
}

class _SetlistScreenState extends State<SetlistScreen> {
  Map<String, List<BpmEntry>> _setlists = {};
  String _currentSetlist = 'Setlist 1';
  List<BpmEntry> get _setlist => _setlists[_currentSetlist] ?? <BpmEntry>[];

  late final ScrollController _scrollController;
  final TickService _tick = TickService();
  StreamSubscription<void>? _tickSub;

  int? _playingIndex; // null when stopped
  int _cursorIndex = 0; // where media controls start if not already playing

  final _coord = PlaybackCoordinator.instance;

  void _publishMeta({int? bpm}) {
    final useBpm = bpm ??
        (_playingIndex != null
            ? _setlist[_playingIndex!].bpm
            : (context.mounted ? context.read<AppStateService>().bpm : 0));
    if (useBpm > 0) {
      SystemMediaHandler.last?.setNowPlaying(
        title: _currentSetlist,
        subtitle: '$useBpm BPM',
      );
    } else {
      SystemMediaHandler.last?.setNowPlaying(title: _currentSetlist, subtitle: '');
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _loadSetlists();

    _coord.bind(
      id: 'setlist',
      onPlay: _coordPlay,
      onPause: _coordPause,
      onNext: _coordNext,
      onPrevious: _coordPrevious,
      isPlaying: () => _tick.isRunning,
    );
  }

  @override
  void didUpdateWidget(covariant SetlistScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!oldWidget.active && widget.active) {
      _coord.activate('setlist');
      if (_setlist.isNotEmpty) {
        SystemMediaHandler.last?.setNowPlayingTitle(
          _setlist[_clampCursor()].displayLabel,
        );
        _publishMeta(bpm: _setlist[_clampCursor()].bpm); // <-- enforce setlist title + BPM
      } else {
        SystemMediaHandler.last?.setNowPlayingTitle('Setlists');
        _publishMeta(); // title to current setlist name (empty list → no BPM)
      }
    }

    if (oldWidget.active && !widget.active) {
      _stopMetronome();
    }
  }

  @override
  void dispose() {
    _tickSub?.cancel();
    _tick.stop();
    _scrollController.dispose();
    super.dispose();
  }

  // ─────────────── Persistence + migration ───────────────

  Future<void> _loadSetlists() async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString('setlist');
    final packed = prefs.getString('setlists');
    final cur    = prefs.getString('current_setlist');

    if (packed == null && legacy != null) {
      final List decoded = json.decode(legacy);
      _setlists = {'Setlist 1': decoded.map((e) => BpmEntry.fromJson(e)).toList()};
      _currentSetlist = 'Setlist 1';
      await _saveSetlists();
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

    _cursorIndex = _setlist.isEmpty ? 0 : _setlist.length - 1;
    setState(() {});
    _publishMeta(); // reflect current setlist as soon as data loads
  }

  Future<void> _saveSetlists() async {
    final prefs = await SharedPreferences.getInstance();
    final mapJson = _setlists.map((k, v) => MapEntry(k, v.map((e) => e.toJson()).toList()));
    await prefs.setString('setlists', json.encode(mapJson));
    await prefs.setString('current_setlist', _currentSetlist);
  }

  String _firstOrDefaultName() =>
      _setlists.keys.isNotEmpty ? _setlists.keys.first : 'Setlist 1';

  String _generateSetlistName() {
    int i = 1;
    while (_setlists.containsKey('Setlist $i')) i++;
    return 'Setlist $i';
  }

  int _clampCursor() {
    if (_setlist.isEmpty) return 0;
    if (_cursorIndex < 0) return 0;
    if (_cursorIndex >= _setlist.length) return _setlist.length - 1;
    return _cursorIndex;
  }

  // ─────────────── Setlist ops ───────────────

  Future<void> _renameSetlist(String oldName) async {
    final newName = await _promptForName(
      context, title: 'Rename Setlist', initial: oldName,
    );
    if (newName == null ||
        newName.isEmpty ||
        newName == oldName ||
        _setlists.containsKey(newName)) {
      return;
    }

    setState(() {
      final entries = _setlists.remove(oldName)!;
      _setlists[newName] = entries;
      if (_currentSetlist == oldName) _currentSetlist = newName;
      _cursorIndex = _setlist.isEmpty ? 0 : _setlist.length - 1;
    });
    await _saveSetlists();
    _publishMeta(); // title changed
  }

  Future<void> _deleteSetlist(String name) async {
    if (_setlists.length <= 1) return;
    _stopMetronome();
    setState(() {
      _setlists.remove(name);
      if (_currentSetlist == name) {
        _currentSetlist = _firstOrDefaultName();
      }
      _cursorIndex = _setlist.isEmpty ? 0 : _setlist.length - 1;
    });
    await _saveSetlists();
    _publishMeta();
  }

  // ─────────────── Entry CRUD ───────────────

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
    });
    await _saveSetlists();

    await Future.delayed(const Duration(milliseconds: 100));
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut,
      );
    }
    _publishMeta(); // BPM context might change where cursor points
  }

  Future<void> _editEntry(int index) async {
    _stopMetronome();
    final entry = await showDialog<BpmEntry>(
      context: context,
      builder: (_) => _BpmEntryDialog(existing: _setlist[index]),
    );
    if (entry == null) return;
    setState(() => _setlist[index] = entry);
    await _saveSetlists();

    if (_playingIndex == index) {
      SystemMediaHandler.last?.setNowPlayingTitle(_setlist[index].displayLabel);
      _publishMeta(bpm: _setlist[index].bpm); // enforce setlist title + BPM
    } else {
      _publishMeta();
    }
  }

  Future<void> _deleteEntry(int index) async {
    _stopMetronome();
    setState(() {
      _setlist.removeAt(index);
      if (_cursorIndex >= _setlist.length) _cursorIndex = _setlist.length - 1;
      if (_cursorIndex < 0) _cursorIndex = 0;
    });
    await _saveSetlists();
    _publishMeta();
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final item = _setlist.removeAt(oldIndex);
    _setlist.insert(newIndex, item);

    if (_playingIndex != null) {
      if (_playingIndex == oldIndex)        _playingIndex = newIndex;
      else if (oldIndex < _playingIndex! &&
               newIndex >= _playingIndex!)   _playingIndex = _playingIndex! - 1;
      else if (oldIndex > _playingIndex! &&
               newIndex <= _playingIndex!)   _playingIndex = _playingIndex! + 1;
    }
    if (_cursorIndex == oldIndex) _cursorIndex = newIndex;

    setState(() {});
    await _saveSetlists();
    _publishMeta();
  }

  // ─────────────── Playback core ───────────────

  Future<void> _playAt(int index) async {
    if (_setlist.isEmpty) return;
    index = index.clamp(0, _setlist.length - 1);
    final entry = _setlist[index];

    _stopMetronome();

    _coord.activate('setlist');
    SystemMediaHandler.last?.setNowPlayingTitle(entry.displayLabel);
    _publishMeta(bpm: entry.bpm); // enforce required title/subtitle

    _tick.start(entry.bpm);
    _tickSub = _tick.tickStream.listen((_) {
      if (context.read<AppStateService>().soundOn) {
        AudioService.playClick();
      }
    });

    setState(() {
      _playingIndex = index;
      _cursorIndex  = index;
    });
  }

  void _stopMetronome() {
    _tickSub?.cancel();
    _tick.stop();
    if (mounted) setState(() => _playingIndex = null);
  }

  // ─────────────── Coordinator callbacks (media controls) ───────────────

  Future<void> _coordPlay() async {
    if (_tick.isRunning || _setlist.isEmpty) return;
    final start = _playingIndex ?? _clampCursor();
    await _playAt(start);
  }

  Future<void> _coordPause() async {
    _stopMetronome();
  }

  // Because reverse:true, visually "Next" (▶▶) should move DOWN ⇒ index - 1
  Future<void> _coordNext() async {
    if (_setlist.isEmpty) return;

    final base = (_playingIndex ?? _clampCursor());
    final next = base - 1; // reverse:true → down the screen

    if (next < 0) return;

    if (_tick.isRunning) {
      await _playAt(next);
    } else {
      setState(() => _cursorIndex = next);
      SystemMediaHandler.last?.setNowPlayingTitle(_setlist[next].displayLabel);
      _publishMeta(bpm: _setlist[next].bpm); // enforce required title/subtitle
    }
  }

  // And "Previous" (◀◀) should move UP ⇒ index + 1
  Future<void> _coordPrevious() async {
    if (_setlist.isEmpty) return;

    final base = (_playingIndex ?? _clampCursor());
    final prev = base + 1; // reverse:true → up the screen

    if (prev >= _setlist.length) return;

    if (_tick.isRunning) {
      await _playAt(prev);
    } else {
      setState(() => _cursorIndex = prev);
      SystemMediaHandler.last?.setNowPlayingTitle(_setlist[prev].displayLabel);
      _publishMeta(bpm: _setlist[prev].bpm); // enforce required title/subtitle
    }
  }

  // ─────────────── Setlist picker dialog ───────────────

  Future<void> _openSetlistPicker() async {
    _stopMetronome();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        const rowHeight = 56.0;
        final maxBodyHeight = MediaQuery.of(ctx).size.height * 0.5;

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
              refreshDialog = setLocal;

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
                      setState(() {
                        _currentSetlist = v;
                        _cursorIndex = _setlists[v]!.isEmpty ? 0 : _setlists[v]!.length - 1;
                      });
                      _saveSetlists();
                      setLocal(() {});
                      _publishMeta(); // reflect newly chosen setlist
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
                          setLocal(() {});
                          _publishMeta();
                        },
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete, color: Colors.white70),
                        onPressed: () async {
                          await _deleteSetlist(name);
                          setLocal(() {});
                          _publishMeta();
                        },
                      ),
                    ],
                  ),
                );
              }

              final contentChild = (estimated <= maxBodyHeight)
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: names.map(buildTile).toList(),
                    )
                  : SizedBox(
                      height: maxBodyHeight,
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: names.length,
                        itemBuilder: (_, i) => buildTile(names[i]),
                      ),
                    );

              return contentChild;
            },
          ),
          actions: [
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
                  _currentSetlist = name;
                  _cursorIndex = 0;
                });
                await _saveSetlists();
                refreshDialog?.call(() {});
                _publishMeta();
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

  // ─────────────── UI (unchanged) ───────────────

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateService>();
    final w = MediaQuery.of(context).size.width;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Column(
                children: [
                  Text(
                    _currentSetlist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.tealAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.transparent,
                          Colors.grey,
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Row(
                children: [
                  SizedBox(width: w * 0.1),
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
                  SizedBox(width: w * 0.1),
                ],
              ),
            ),

            SizedBox(
              height: 100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    iconSize: 40,
                    icon: Icon(appState.soundOn ? Icons.volume_up : Icons.volume_off),
                    onPressed: () => appState.setSoundOn(!appState.soundOn),
                  ),
                  IconButton(
                    iconSize: 40,
                    icon: const Icon(Icons.add_circle),
                    onPressed: _addEntry,
                  ),
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

  Widget _buildListItem(BuildContext context, int index) {
    final entry = _setlist[index];
    final isPlaying = _playingIndex == index;

    return ListTile(
      key: ValueKey('$_currentSetlist-$index-${entry.hashCode}'),
      title: Text(entry.displayLabel, overflow: TextOverflow.ellipsis),
      leading: IconButton(
        icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
        onPressed: () => isPlaying ? _stopMetronome() : _playAt(index),
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
  State<_BpmEntryDialog> createState() => _BpmEntryDialogState();
}

class _BpmEntryDialogState extends State<_BpmEntryDialog> {
  final TextEditingController _labelController = TextEditingController();
  int _bpm = 100;

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
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _tapTempo,
              icon: const Icon(Icons.touch_app, color: Colors.tealAccent),
              label: const Text('Tap tempo', style: TextStyle(color: Colors.tealAccent)),
              style: TextButton.styleFrom(foregroundColor: Colors.tealAccent),
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