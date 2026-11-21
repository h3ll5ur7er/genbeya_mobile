import 'package:material_ui/material_ui.dart';

import '../../access/kit/kit_protocol.dart';
import '../kit/kit_view.dart';
import 'editor_samples.dart';
import 'editor_toolbar.dart';

/// GM-4: the kit's editor (CodeMirror 6 with Genbeya's Markdown completions)
/// filling the screen, with a native toolbar above the keyboard.
class KitEditorSpikeScreen extends StatefulWidget {
  const KitEditorSpikeScreen({super.key});

  @override
  State<KitEditorSpikeScreen> createState() => _KitEditorSpikeScreenState();
}

class _KitEditorSpikeScreenState extends State<KitEditorSpikeScreen> {
  KitSend? _send;
  bool _long = false;
  String _status = 'Starting the kit…';
  int _drafts = 0;
  final _opened = Stopwatch();

  void _open() {
    final send = _send;
    if (send == null) return;
    final text = _long ? longSample() : shortSample;
    _opened
      ..reset()
      ..start();
    send(
      editMessage(
        area: 'wiki',
        path: 'docs/Notes.md',
        text: text,
        hash: 'notes-${text.length}',
      ),
    );
    setState(() => _status = 'Opened ${text.split('\n').length} lines');
  }

  void _onMessage(FromKit message, KitSend send) {
    switch (message) {
      case KitReady():
        _send = send;
        send(
          themeMessage(dark: Theme.of(context).brightness == Brightness.dark),
        );
        send(contextMessage(_context));
        _open();
      case KitEditorState(
        :final dirty,
        :final from,
        :final to,
        :final completing,
      ):
        if (_opened.isRunning) _opened.stop();
        setState(
          () => _status =
              '${dirty ? 'Edited' : 'Saved'} · selection $from–$to${completing ? ' · completing' : ''} · $_drafts drafts',
        );
      case KitDraft():
        _drafts++;
      case KitSave(:final text):
        setState(
          () => _status =
              'Save asked: ${text.length} characters (not written in the spike)',
        );
      case KitError(:final message):
        setState(() => _status = 'Kit error: $message');
      default:
        break;
    }
  }

  void _command(String command) {
    final send = _send;
    if (send == null) return;
    send(
      command.startsWith('insert:')
          ? editorCommandMessage('insert', text: command.substring(7))
          : editorCommandMessage(command),
    );
  }

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
      body: Column(
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
              onMessage: _onMessage,
              onRefused: (reason) =>
                  setState(() => _status = 'Refused: $reason'),
            ),
          ),
          EditorToolbar(onCommand: _command),
        ],
      ),
    );
  }
}

final _context = <String, ({String version, Object? value})>{
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
    value: {
      'wikiRoot': 'docs',
      'nodes': [
        {
          'title': 'Home',
          'path': 'docs/Home.md',
          'folder': null,
          'children': <Object>[],
        },
      ],
    },
  ),
  'settings': (
    version: 's1',
    value: {
      'statuses': ['backlog', 'todo', 'in-progress', 'review', 'done'],
      'hiddenColumns': <String>[],
      'types': <Object>[],
      'fields': <Object>[],
    },
  ),
  'files': (version: 'f1', value: ['README.md']),
  'plan': (version: 'n1', value: null),
  'author': (version: 'a1', value: 'Alex Chen'),
};
