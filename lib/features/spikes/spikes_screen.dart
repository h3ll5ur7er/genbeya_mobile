import 'package:material_ui/material_ui.dart';

import 'git_spike_screen.dart';
import 'kit_editor_spike_screen.dart';
import 'kit_spike_screen.dart';
import 'native_editor_spike_screen.dart';

/// Test screens for the M0 spikes (GM-2, GM-3, GM-4). They go once the spikes are done.
class SpikesScreen extends StatelessWidget {
  const SpikesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Spikes')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Git core'),
            subtitle: const Text('GM-2: clone, commit, sync'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const GitSpikeScreen()),
            ),
          ),
          ListTile(
            title: const Text('Web kit'),
            subtitle: const Text('GM-3: Genbeya pages rendered offline'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const KitSpikeScreen()),
            ),
          ),
          ListTile(
            title: const Text('Editor (kit)'),
            subtitle: const Text(
              'GM-4: CodeMirror 6 with Genbeya\'s completions',
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const KitEditorSpikeScreen(),
              ),
            ),
          ),
          ListTile(
            title: const Text('Editor (native)'),
            subtitle: const Text('GM-4: re_editor, to compare'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NativeEditorSpikeScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
