import 'package:material_ui/material_ui.dart';

/// Test screens for the M0 spikes (GM-2, GM-3, GM-4). They go once the spikes are done.
class SpikesScreen extends StatelessWidget {
  const SpikesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Spikes')),
      body: ListView(
        children: const [
          ListTile(
            title: Text('Git core'),
            subtitle: Text('GM-2: clone, commit, sync'),
          ),
          ListTile(
            title: Text('Web kit'),
            subtitle: Text('GM-3: Genbeya pages rendered offline'),
          ),
          ListTile(
            title: Text('Editor'),
            subtitle: Text('GM-4: CodeMirror 6 on the phone'),
          ),
        ],
      ),
    );
  }
}
