// File: lib/widgets/note_generator_settings_modal.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state_service.dart';

class NoteGeneratorSettingsModal extends StatelessWidget {
  const NoteGeneratorSettingsModal({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateService>();
    final submenuStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70)
        ?? const TextStyle(fontSize: 12, color: Colors.white70);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: const Text('Tempo Increase', style: TextStyle(color: Colors.white)),
            value: appState.tempoIncreaseEnabled,
            onChanged: (v) => context.read<AppStateService>().setTempoIncreaseEnabled(v),
          ),
          if (appState.tempoIncreaseEnabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DefaultTextStyle(
                style: submenuStyle,
                child: Row(
                  children: [
                    const Text('Increase BPM by'),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: appState.tempoIncreaseX,
                      dropdownColor: Colors.black,
                      style: const TextStyle(color: Colors.white),
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
                    const Text('ticks'),
                  ],
                ),
              ),
            ),
          const Divider(color: Colors.white24),
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.black,
                backgroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Select Notes'),
            ),
          ),
        ],
      ),
    );
  }
}