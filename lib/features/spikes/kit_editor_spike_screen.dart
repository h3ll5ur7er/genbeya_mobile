import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../access/kit/kit_host.dart';
import '../kit/kit_view.dart';
import 'editor_samples.dart';
import '../kit/editor_toolbar.dart';

/// GM-4: the kit's editor (CodeMirror 6 with Genbeya's Markdown completions)
/// filling the screen, with a native toolbar above the keyboard.
class KitEditorSpikeScreen extends StatefulWidget {
  const KitEditorSpikeScreen({super.key});

  @override
  State<KitEditorSpikeScreen> createState() => _KitEditorSpikeScreenState();
}

class _KitEditorSpikeScreenState extends State<KitEditorSpikeScreen> {
  late final KitHost _host;
  bool _long = false;
  String _status = 'Starting the kit…';
  int _drafts = 0;
  final _opened = Stopwatch();

  @override
  void initState() {
    super.initState();
    _host = KitHost(
      files: _NoFiles(),
      onEditorState: (state) {
        if (_opened.isRunning) _opened.stop();
        setState(
          () => _status =
              '${state.dirty ? 'Edited' : 'Saved'} · selection ${state.from}–${state.to}${state.completing ? ' · completing' : ''} · $_drafts drafts',
        );
      },
      onDraft: (_, _) => _drafts++,
      onSave: (_, text) => setState(
        () => _status =
            'Save asked: ${text.length} characters (not written in the spike)',
      ),
      onLog: (line) => setState(() => _status = line),
    )..updateContext(_context);
    _open();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _host.setTheme(dark: Theme.of(context).brightness == Brightness.dark);
  }

  void _open() {
    final text = _long ? longSample() : shortSample;
    _opened
      ..reset()
      ..start();
    _host.edit(
      KitEdit(
        area: 'wiki',
        path: 'docs/Notes.md',
        text: text,
        hash: 'notes-${text.length}',
      ),
    );
    _status = 'Opened ${text.split('\n').length} lines';
  }

  void _command(String command) => command.startsWith('insert:')
      ? _host.command('insert', text: command.substring(7))
      : _host.command(command);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editor (kit)'),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _long = !_long);
              _open();
            },
            child: Text(_long ? 'Short page' : '2,000 lines'),
          ),
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.save_outlined),
            onPressed: () => _command('save'),
          ),
        ],
      ),
      // The toolbar stays above Android's navigation bar.
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _status,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            Expanded(
              child: KitView(
                host: _host,
                onRefused: (reason) =>
                    setState(() => _status = 'Refused: $reason'),
              ),
            ),
            EditorToolbar(onCommand: _command),
          ],
        ),
      ),
    );
  }
}

class _NoFiles implements KitFiles {
  @override
  Future<Uint8List> image(String path) =>
      Future.error(KitReadException('No images in the spike.'));
  @override
  Future<String> file(String path) =>
      Future.error(KitReadException('No files in the spike.'));
  @override
  Future<String> fileAt(String path, String revision) =>
      Future.error(KitReadException('No history in the spike.'));
  @override
  Future<String> planHistory(String? baseline) =>
      Future.error(KitReadException('No plan in the spike.'));
}

final _context = <String, KitContextPart>{
  'tasks': (
    version: 't1',
    value: [
      for (var i = 1; i <= 28; i++)
        {
          'id': 'GM-$i',
          'path': 'tasks/GM-$i.md',
          'title': 'Task $i of the plan',
          'status': 'todo',
        },
    ],
  ),
  'people': (
    version: 'p1',
    value: [
      {
        'handle': 'alex',
        'name': 'Alex Chen',
        'email': null,
        'aliases': <String>[],
        'commits': 3,
      },
      {
        'handle': 'sam',
        'name': 'Sam Rivera',
        'email': null,
        'aliases': <String>[],
        'commits': 2,
      },
    ],
  ),
  'wiki': (
    version: 'w1',
    value: [
      {
        'title': 'Home',
        'path': 'docs/Home.md',
        'folder': null,
        'children': <Object>[],
      },
    ],
  ),
  'settings': (
    version: 's1',
    value: {
      'wikiRoot': 'docs',
      'statuses': ['backlog', 'todo', 'in-progress', 'review', 'done'],
    },
  ),
  'files': (version: 'f1', value: ['README.md']),
  'plan': (version: 'n1', value: <Object>[]),
  'author': (version: 'a1', value: 'Alex Chen'),
};
