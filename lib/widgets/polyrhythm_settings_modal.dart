// File: lib/widgets/polyrhythm_settings_modal.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_state_service.dart';

class PolyrhythmSettingsModal extends StatefulWidget {
  const PolyrhythmSettingsModal({super.key});
  @override
  State<PolyrhythmSettingsModal> createState() => _PolyrhythmSettingsModalState();
}

class _PolyrhythmSettingsModalState extends State<PolyrhythmSettingsModal> {
  bool _polyAccented = false;

  @override
  void initState() {
    super.initState();
    _loadAccent();
  }

  Future<void> _loadAccent() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _polyAccented = prefs.getBool('polyrhythm_accented') ?? false;
    });
  }

  Future<void> _setAccent(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('polyrhythm_accented', v);
    setState(() => _polyAccented = v);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateService>();
    final style = Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 12);

    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        // Grey outline at the very top edge
        border: Border(top: BorderSide(color: Colors.grey.shade800, width: 1)),
      ),
      padding: const EdgeInsets.all(16),
      child: SwitchTheme(
        // Force tealAccent theme for all Switches in this modal
        data: SwitchThemeData(
          thumbColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) return Colors.tealAccent;
            return Colors.white70;
          }),
          trackColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) return Colors.tealAccent.withOpacity(0.35);
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
            SwitchListTile(
              title: const Text('Accented clicks', style: TextStyle(color: Colors.white)),
              value: _polyAccented,
              onChanged: _setAccent,
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}