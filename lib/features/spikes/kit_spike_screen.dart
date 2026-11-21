import 'package:material_ui/material_ui.dart';

import '../../access/kit/kit_protocol.dart';
import '../kit/kit_view.dart';

/// GM-3 on a phone: a native screen with the kit in it, rendering a sample
/// page, sizing itself to the height the kit reports, and logging every
/// message the kit sends.
class KitSpikeScreen extends StatefulWidget {
  const KitSpikeScreen({super.key});

  @override
  State<KitSpikeScreen> createState() => _KitSpikeScreenState();
}

class _KitSpikeScreenState extends State<KitSpikeScreen> {
  final _log = <String>[];
  double _height = 400;
  final _started = Stopwatch()..start();

  void _note(String line) {
    if (!mounted) return;
    setState(() => _log.insert(0, '${_started.elapsedMilliseconds} ms  $line'));
  }

  void _onMessage(FromKit message, KitSend send) {
    switch (message) {
      case KitReady(:final protocol, :final genbeya):
        _note('ready: protocol $protocol, Genbeya $genbeya');
        if (protocol != kitProtocol) {
          _note('refused: this app speaks protocol $kitProtocol');
          return;
        }
        send(
          themeMessage(dark: Theme.of(context).brightness == Brightness.dark),
        );
        send(contextMessage(_sampleContext));
        send(
          previewPageMessage(
            path: 'docs/Spike.md',
            title: 'Spike',
            source: _samplePage,
            hash: 'spike-1',
          ),
        );
      case KitHeight(:final height):
        setState(() => _height = height.clamp(200, 20000));
      case KitToggle(:final path, :final hash, :final offset):
        _note('toggle: $path at $offset in version $hash');
      case KitFollow(:final link):
        _note(
          'follow: ${switch (link) {
            ExternalLink(:final url) => 'web link $url',
            MissingPage(:final title) => 'new page "$title"',
            PersonLink(:final handle) => '@$handle',
            FileLink(:final path, :final anchor) => '$path${anchor == null ? '' : '#$anchor'}',
          }}',
        );
      case KitRequest():
        _note(
          'request ${message.runtimeType} ${message.id}: answered with an error in the spike',
        );
        send(replyTo(message, error: 'Not in the spike.'));
      case KitError(:final message):
        _note('kit error: $message');
      default:
        _note(message.runtimeType.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Web kit')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Native above: Genbeya\'s renderer below, offline, in a web view sized to its content.',
            ),
          ),
          SizedBox(
            height: _height,
            child: KitView(
              onMessage: _onMessage,
              onRefused: (reason) => _note('refused: $reason'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Messages from the kit'),
          ),
          for (final line in _log)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Text(
                line,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

const _tasks = [
  ('GM-1', 'Set up the Flutter project and CI', 'review'),
  ('GM-2', 'Spike: Git on the device with a Rust core', 'in-progress'),
  ('GM-3', 'Spike: render Genbeya pages with the web kit', 'in-progress'),
  ('GM-6', 'Repositories, cloning and signing in', 'backlog'),
];

final _sampleContext = <String, ({String version, Object? value})>{
  'tasks': (
    version: 't1',
    value: [
      for (final (id, title, status) in _tasks)
        {'id': id, 'path': 'tasks/$id.md', 'title': title, 'status': status},
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
        {
          'title': 'Architecture',
          'path': 'docs/Architecture.md',
          'folder': null,
          'children': <Object>[],
        },
      ],
    },
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
    ],
  ),
  'settings': (
    version: 's1',
    value: {
      'statuses': ['backlog', 'todo', 'in-progress', 'review', 'done'],
      'hiddenColumns': <String>[],
      'types': [
        {'name': 'spike', 'icon': 'flask-conical'},
      ],
      'fields': <Object>[],
    },
  ),
  'files': (version: 'f1', value: ['README.md', 'pubspec.yaml']),
  'plan': (version: 'n1', value: null),
  'author': (version: 'a1', value: 'Alex Chen'),
};

const _samplePage = r'''# Spike

Rendered by Genbeya's own pipeline: [[GM-2]] and [[GM-3]] show their state, [[Architecture]] is a page, [[Meeting notes]] doesn't exist yet. Asked by @alex on 2026-11-21.

- [x] Render this page offline
- [ ] Tick this box: the host gets a toggle

> [!NOTE]
> Callouts, tables, math and diagrams come from the kit.

| Spike | State |
| --- | --- |
| Git core | running |
| Kit | rendering |

$$\int_0^1 x^2\,dx = \frac{1}{3}$$

```mermaid
flowchart LR
  app[Flutter] --> kit[Web kit]
  app --> git[Rust core]
```

```plantuml
Alice -> Bob: hello
Bob --> Alice: hi
```
''';
