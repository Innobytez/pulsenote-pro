// File: lib/widgets/metronome_settings_modal.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state_service.dart';

class MetronomeSettingsModal extends StatelessWidget {
  const MetronomeSettingsModal({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateService>();
    final submenuStyle =
        Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 12);

    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        // Grey outline at the very top to indicate the modal top edge
        border: Border(
          top: BorderSide(color: Colors.grey.shade800, width: 1),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: SwitchTheme(
        // Force tealAccent styling for all Switches inside this modal
        data: SwitchThemeData(
          thumbColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return Colors.tealAccent;
            }
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
          // (Optional) slightly larger splash radius feels nicer in a modal
          splashRadius: 22,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min, // Only take up needed vertical space
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text('Tempo Increase', style: TextStyle(color: Colors.white)),
              value: appState.tempoIncreaseEnabled,
              onChanged: appState.setTempoIncreaseEnabled,
              // Ensure tile visuals match the dark modal
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            if (appState.tempoIncreaseEnabled)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DefaultTextStyle(
                  style: submenuStyle.copyWith(color: Colors.white70),
                  child: Row(
                    children: [
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
                        onChanged: (newX) {
                          if (newX == null) return;
                          appState.setTempoIncreaseValues(newX, appState.tempoIncreaseY);
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
                        onChanged: (newY) {
                          if (newY == null) return;
                          appState.setTempoIncreaseValues(appState.tempoIncreaseX, newY);
                        },
                      ),
                      const SizedBox(width: 8),
                      const Text('beats'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}