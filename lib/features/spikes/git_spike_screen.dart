import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../access/native/ca_bundle.dart';
import '../../access/native/transfers.dart';

import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/git.dart' as core;
import '../../src/rust/git.dart';

/// GM-2: try the Rust Git core on a real phone. Clone a repository, commit a
/// test file, sync (fetch, rebase in memory, push), and read the timings.
/// Goes once the spike is done.
class GitSpikeScreen extends StatefulWidget {
  const GitSpikeScreen({super.key});

  @override
  State<GitSpikeScreen> createState() => _GitSpikeScreenState();
}

class _GitSpikeScreenState extends State<GitSpikeScreen> {
  final _url = TextEditingController(
    text: 'https://github.com/genbeya/genbeya.git',
  );
  final _token = TextEditingController();
  final _depth = TextEditingController(text: '50');
  final _log = <String>[];
  var _busy = false;
  var _operation = 0;
  Progress? _progress;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    _depth.dispose();
    super.dispose();
  }

  Future<String> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    return '${docs.path}/spike-clone';
  }

  RemoteOptions get _remote => RemoteOptions(
    auth: _token.text.isEmpty
        ? const Auth.none()
        : Auth.token(username: 'x-access-token', token: _token.text),
    trustedHostKeys: const [],
  );

  static const _identity = Identity(
    name: 'Genbeya Mobile spike',
    email: 'spike@genbeya.invalid',
  );

  void _say(String line) => setState(() => _log.insert(0, line));

  Future<void> _run(String name, Future<String> Function() action) async {
    setState(() => _busy = true);
    final watch = Stopwatch()..start();
    try {
      final result = await action();
      _say('$name: $result (${watch.elapsedMilliseconds} ms)');
    } on CoreError catch (e) {
      _say('$name failed: $e (${watch.elapsedMilliseconds} ms)');
    } catch (e) {
      _say('$name failed: $e');
    } finally {
      setState(() {
        _busy = false;
        _progress = null;
      });
    }
  }

  Future<String> _clone() async {
    final dir = await _dir();
    if (Directory(dir).existsSync()) Directory(dir).deleteSync(recursive: true);
    _operation++;
    await runTransfer(
      core.cloneRepository(
        url: _url.text.trim(),
        dir: dir,
        extraBranches: const ['genbeya'],
        depth: int.tryParse(_depth.text),
        remote: _remote,
        operationId: BigInt.from(_operation),
      ),
      onProgress: (p) => setState(() => _progress = p),
    );
    final head = await core.head(dir: dir);
    final size = _sizeOf(Directory(dir));
    return '${head.branch} at ${head.commit.substring(0, 7)}, shallow ${head.shallow}, '
        '${(_progress?.receivedBytes ?? BigInt.zero) ~/ BigInt.from(1024)} KB received, ${size ~/ 1024} KB on disk';
  }

  Future<String> _commit() async {
    final dir = await _dir();
    final name = 'spike/${DateTime.now().millisecondsSinceEpoch}.md';
    File('$dir/$name')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '# Spike\n\nWritten on the phone at ${DateTime.now().toIso8601String()}.\n',
      );
    final id = await core.commitFiles(
      dir: dir,
      paths: [name],
      message: 'GM-2: Spike commit',
      identity: _identity,
    );
    final head = await core.head(dir: dir);
    return '${id.substring(0, 7)}, ${head.ahead} ahead';
  }

  Future<String> _sync() async {
    final dir = await _dir();
    _operation++;
    await runTransfer(
      core.fetch(
        dir: dir,
        extraBranches: const [],
        remote: _remote,
        operationId: BigInt.from(_operation),
      ),
      onProgress: (p) => setState(() => _progress = p),
    );
    final rebase = await core.rebaseOntoUpstream(
      dir: dir,
      identity: _identity,
      resolutions: const [],
    );
    final head = await core.head(dir: dir);
    if (head.ahead == 0) return 'fetched; $rebase; nothing to push';
    final push = await core.push(
      dir: dir,
      branch: head.branch!,
      remote: _remote,
    );
    return 'fetched; $rebase; $push';
  }

  Future<String> _head() async {
    final head = await core.head(dir: await _dir());
    return '${head.branch} ${head.commit.substring(0, 7)} ↑${head.ahead} ↓${head.behind} dirty ${head.dirty.length}';
  }

  int _sizeOf(Directory dir) => dir
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .fold(0, (sum, f) => sum + f.lengthSync());

  @override
  Widget build(BuildContext context) {
    final p = _progress;
    return Scaffold(
      appBar: AppBar(title: const Text('Git core')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${core.coreVersion()}\nCertificates: ${CaBundleStatus.description}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            decoration: const InputDecoration(labelText: 'Repository URL'),
          ),
          TextField(
            controller: _token,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Token (only to push)',
            ),
          ),
          TextField(
            controller: _depth,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Depth (empty for full history)',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _busy ? null : () => _run('Clone', _clone),
                child: const Text('Clone'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _run('Commit', _commit),
                child: const Text('Commit a test file'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _run('Sync', _sync),
                child: const Text('Sync'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _run('Head', _head),
                child: const Text('Head'),
              ),
              TextButton(
                onPressed: _busy
                    ? () => core.cancelOperation(
                        operationId: BigInt.from(_operation),
                      )
                    : null,
                child: const Text('Cancel'),
              ),
            ],
          ),
          if (p != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: p.totalObjects == 0
                  ? null
                  : p.receivedObjects / p.totalObjects,
            ),
            Text(
              '${p.receivedObjects}/${p.totalObjects} objects, ${p.receivedBytes ~/ BigInt.from(1024)} KB',
            ),
          ],
          const Divider(height: 32),
          for (final line in _log)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(line),
            ),
        ],
      ),
    );
  }
}
