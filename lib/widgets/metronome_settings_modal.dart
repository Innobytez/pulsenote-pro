// File: lib/widgets/metronome_settings_modal.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state_service.dart';

class MetronomeSettingsModal extends StatefulWidget {
  // Existing props
  final bool showTempoText;
  final ValueChanged<bool> onShowTempoTextChanged;

  // NEW: Skip Beats Mode props
  final bool skipEnabled;
  final int skipX;
  final int skipY;
  final ValueChanged<bool> onSkipEnabledChanged;
  final void Function(int x, int y) onSkipValuesChanged;

  const MetronomeSettingsModal({
    super.key,
    required this.showTempoText,
    required this.onShowTempoTextChanged,
    required this.skipEnabled,
    required this.skipX,
    required this.skipY,
    required this.onSkipEnabledChanged,
    required this.onSkipValuesChanged,
  });

  @override
  State<MetronomeSettingsModal> createState() => _MetronomeSettingsModalState();
}

class _MetronomeSettingsModalState extends State<MetronomeSettingsModal> {
  late bool _showTempoText; // local visual state

  // Local mirrors for Skip Beats controls (so the dropdowns reflect instantly)
  late bool _skipEnabled;
  late int _skipX;
  late int _skipY;

  @override
  void initState() {
    super.initState();
    _showTempoText = widget.showTempoText;

    _skipEnabled = widget.skipEnabled;
    _skipX = widget.skipX;
    _skipY = widget.skipY;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateService>();
    final style = Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 12);

    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(top: BorderSide(color: Colors.grey.shade800, width: 1)),
      ),
      padding: const EdgeInsets.all(16),
      child: SwitchTheme(
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
        child: Column(
          mainAxisSize: MainAxisSize.min, // shrink to fit
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Tempo Increase (unchanged)
            SwitchListTile(
              title: const Text('Tempo Increase', style: TextStyle(color: Colors.white)),
              value: appState.tempoIncreaseEnabled,
              onChanged: (v) => context.read<AppStateService>().setTempoIncreaseEnabled(v),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            if (appState.tempoIncreaseEnabled)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DefaultTextStyle(
                  style: style.copyWith(color: Colors.white70),
                  child: Row(children: [
                    const Text('Increase BPM by'),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: appState.tempoIncreaseX,
                      dropdownColor: Colors.black,
                      style: const TextStyle(color: Colors.white),
                      iconEnabledColor: Colors.white70,
                      items: List.generate(16, (i) => i + 1)
                          .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          context.read<AppStateService>().setTempoIncreaseValues(
                                v,
                                appState.tempoIncreaseY,
                              );
                        }
                      },
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
                      onChanged: (v) {
                        if (v != null) {
                          context.read<AppStateService>().setTempoIncreaseValues(
                                appState.tempoIncreaseX,
                                v,
                              );
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    const Text('beats'),
                  ]),
                ),
              ),
              
            const Divider(color: Colors.white24),
            // ── NEW: Skip Beats Mode
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Skip Beats Mode', style: TextStyle(color: Colors.white)),
              value: _skipEnabled,
              onChanged: (v) {
                setState(() => _skipEnabled = v);       // update visual
                widget.onSkipEnabledChanged(v);          // persist + notify parent
              },
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            if (_skipEnabled)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DefaultTextStyle(
                  style: style.copyWith(color: Colors.white70),
                  child: Row(
                    children: [
                      const Text('Play'),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: _skipX,
                        dropdownColor: Colors.black,
                        style: const TextStyle(color: Colors.white),
                        iconEnabledColor: Colors.white70,
                        items: List.generate(16, (i) => i + 1)
                            .map((v) => DropdownMenuItem<int>(value: v, child: Text('$v')))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _skipX = v);
                          widget.onSkipValuesChanged(_skipX, _skipY);
                        },
                      ),
                      const SizedBox(width: 8),
                      const Text('beats then skip'),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: _skipY,
                        dropdownColor: Colors.black,
                        style: const TextStyle(color: Colors.white),
                        iconEnabledColor: Colors.white70,
                        items: List.generate(16, (i) => i + 1)
                            .map((v) => DropdownMenuItem<int>(value: v, child: Text('$v')))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _skipY = v);
                          widget.onSkipValuesChanged(_skipX, _skipY);
                        },
                      ),
                      const SizedBox(width: 8),
                      const Text('beats'),
                    ],
                  ),
                ),
              ),

            const Divider(color: Colors.white24),

            // Show Tempo Text
            SwitchListTile(
              title: const Text('Show Tempo Text', style: TextStyle(color: Colors.white)),
              value: _showTempoText,
              onChanged: (v) {
                setState(() => _showTempoText = v); // immediate visual update
                widget.onShowTempoTextChanged(v);   // notify parent (persists)
              },
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}