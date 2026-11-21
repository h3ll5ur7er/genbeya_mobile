import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../access/kit/kit_host.dart';
import '../../access/kit/kit_protocol.dart';
import '../../engines/checkbox_engine.dart';
import '../kit/kit_view.dart';

/// GM-3 on a phone: a native screen with the kit in it, rendering a sample
/// page through [KitHost], sizing itself to the height the kit reports, and
/// logging what the kit sends. A ticked checkbox goes the whole way: the host
/// checks it against the version shown, the page's text changes, and the new
/// version is shown (the commit is C4's, later).
class KitSpikeScreen extends StatefulWidget {
  const KitSpikeScreen({super.key});

  @override
  State<KitSpikeScreen> createState() => _KitSpikeScreenState();
}

class _KitSpikeScreenState extends State<KitSpikeScreen> {
  final _log = <String>[];
  double _height = 400;
  final _started = Stopwatch()..start();
  late final KitHost _host;
  var _page = const KitPage(
    path: 'docs/Spike.md',
    title: 'Spike',
    content: _samplePage,
    hash: 'spike-1',
  );
  var _version = 1;

  @override
  void initState() {
    super.initState();
    _host =
        KitHost(
            files: _SpikeFiles(),
            onReady: (genbeya) => _note('ready: Genbeya $genbeya'),
            onHeight: (height) =>
                setState(() => _height = height.clamp(200, 20000)),
            onToggle: _toggle,
            onFollow: (link) => _note(
              'follow: ${switch (link) {
                ExternalLink(:final url) => 'web link $url',
                MissingPage(:final title) => 'new page "$title"',
                PersonLink(:final handle) => '@$handle',
                FileLink(:final path, :final anchor) => '$path${anchor == null ? '' : '#$anchor'}',
              }}',
            ),
            onLog: _note,
          )
          ..updateContext(_sampleContext)
          ..show(_page);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _host.setTheme(dark: Theme.of(context).brightness == Brightness.dark);
  }

  void _note(String line) {
    if (!mounted) return;
    setState(() => _log.insert(0, '${_started.elapsedMilliseconds} ms  $line'));
  }

  /// What C4 will do with a file: refuse once the version changed, else write
  /// the checkbox flipped (here only in memory) and show the new version.
  Future<void> _toggle(KitDocument document, int offset) async {
    if (document.hash != _page.hash) {
      _note('toggle refused: the page changed meanwhile');
      return;
    }
    final content = togglePageCheckbox(_page.content, offset);
    if (content == null) {
      _note('toggle refused: no checkbox at $offset');
      return;
    }
    _page = KitPage(
      path: _page.path,
      title: _page.title,
      content: content,
      hash: 'spike-${++_version}',
    );
    _note('toggle at $offset: written as ${_page.hash}');
    _host.show(_page);
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
              host: _host,
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

/// The spike has no repository: requests are answered with an error.
class _SpikeFiles implements KitFiles {
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

const _tasks = [
  ('GM-1', 'Set up the Flutter project and CI', 'review'),
  ('GM-2', 'Spike: Git on the device with a Rust core', 'in-progress'),
  ('GM-3', 'Spike: render Genbeya pages with the web kit', 'in-progress'),
  ('GM-6', 'Repositories, cloning and signing in', 'backlog'),
];

final _sampleContext = <String, KitContextPart>{
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

const _samplePage = r'''---
title: Spike
---
# Spike

Rendered by Genbeya's own pipeline: [[GM-2]] and [[GM-3]] show their state, [[Architecture]] is a page, [[Meeting notes]] doesn't exist yet. Asked by @alex on 2026-11-21.

- [x] Render this page offline
- [ ] Tick this box: the host checks it and shows the new version
  - [ ] Nested boxes count too

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
