import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/native/native_git_objects.dart';
import 'package:genbeya_mobile/access/native/transfers.dart';
import 'package:genbeya_mobile/managers/repository_model.dart';
import 'package:genbeya_mobile/src/rust/api/git.dart';
import 'package:genbeya_mobile/src/rust/frb_generated.dart';
import 'package:genbeya_mobile/src/rust/git.dart';

/// Drives the Rust Git core through the generated bridge on this machine,
/// against a bare repository: what the app does on a phone, minus the phone.
/// Build the library first: `cargo build --release --lib` in native/genbeya_core.
const library = 'native/genbeya_core/target/release/libgenbeya_core.so';

String git(String dir, List<String> args) {
  final result = Process.runSync('git', args, workingDirectory: dir);
  if (result.exitCode != 0) throw StateError('git $args: ${result.stderr}');
  return (result.stdout as String).trim();
}

void main() {
  final built = File(library).existsSync();

  setUpAll(() async {
    if (built) {
      await RustLib.init(externalLibrary: ExternalLibrary.open(library));
    }
  });

  test('clone, commit and push through the bridge', () async {
    final tmp = Directory.systemTemp.createTempSync('genbeya_bridge');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final remote = '${tmp.path}/remote.git';
    git(tmp.path, ['init', '--bare', '-q', '-b', 'main', remote]);
    final seed = '${tmp.path}/seed';
    git(tmp.path, ['clone', '-q', remote, seed]);
    Directory('$seed/tasks').createSync();
    File('$seed/tasks/GM-1.md')
        .writeAsStringSync('---\nid: GM-1\ntitle: First\nstatus: todo\n---\n');
    git(seed, [
      '-c',
      'user.name=Seed',
      '-c',
      'user.email=s@example.com',
      'add',
      '-A',
    ]);
    git(seed, [
      '-c',
      'user.name=Seed',
      '-c',
      'user.email=s@example.com',
      'commit',
      '-qm',
      'Seed',
    ]);
    git(seed, ['push', '-q', 'origin', 'main']);

    expect(coreVersion(), contains('libgit2'));
    final phone = '${tmp.path}/phone';
    final options = RemoteOptions(
      auth: const Auth.none(),
      trustedHostKeys: const [],
    );
    final progress = <Progress>[];
    await runTransfer(
      cloneRepository(
        url: 'file://$remote',
        dir: phone,
        branch: 'main',
        remote: options,
        operationId: BigInt.one,
      ),
      onProgress: progress.add,
    );
    expect(progress, isNotEmpty);
    // A failed clone reports its typed error on the stream (not a follow-up error).
    await expectLater(
      runTransfer(
        cloneRepository(
          url: 'file://${tmp.path}/no-such-remote',
          dir: '${tmp.path}/failed',
          remote: options,
          operationId: BigInt.two,
        ),
      ),
      throwsA(isA<CoreError>()),
    );
    expect(Directory('${tmp.path}/failed').existsSync(), isFalse);
    final head0 = await head(dir: phone);
    expect(head0.branch, 'main');
    expect(head0.upstream, 'origin/main');

    File('$phone/tasks/GM-1.md')
        .writeAsStringSync('---\nid: GM-1\ntitle: First\nstatus: done\n---\n');
    await commitFiles(
      dir: phone,
      paths: ['tasks/GM-1.md'],
      message: 'GM-1: Done',
      identity: const Identity(name: 'Alice', email: 'alice@example.com'),
    );
    expect((await head(dir: phone)).ahead, 1);
    expect(
      await push(dir: phone, branch: 'main', remote: options),
      const PushOutcome.pushed(),
    );
    expect(
      git(tmp.path, ['--git-dir', remote, 'log', '-1', '--format=%s']),
      'GM-1: Done',
    );

    // The repository model reads the clone through the core's objects.
    final state = await RepositoryModel(
      NativeGitObjects(phone),
      folderName: 'phone',
    ).load();
    expect([for (final t in state.tasks) '${t.id} ${t.status}'], ['GM-1 done']);
    expect(state.place.head, (await head(dir: phone)).commit);

    // Errors arrive as typed exceptions.
    await expectLater(
      commitFiles(
        dir: phone,
        paths: ['../outside'],
        message: 'x',
        identity: const Identity(name: 'A', email: 'a@example.com'),
      ),
      throwsA(isA<CoreError_InvalidPath>()),
    );
  }, skip: built ? false : 'build $library first');
}
