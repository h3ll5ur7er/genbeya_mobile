import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/git/git_remote.dart';
import 'package:genbeya_mobile/access/native/native_git_objects.dart';
import 'package:genbeya_mobile/access/native/native_git_writer.dart';
import 'package:genbeya_mobile/access/native/transfers.dart';
import 'package:genbeya_mobile/access/storage/json_store.dart';
import 'package:genbeya_mobile/managers/content_writer.dart';
import 'package:genbeya_mobile/managers/repository_model.dart';
import 'package:genbeya_mobile/managers/sync_manager.dart';
import 'package:genbeya_mobile/src/rust/api/git.dart' as core;
import 'package:genbeya_mobile/src/rust/frb_generated.dart';
import 'package:genbeya_mobile/src/rust/git.dart' as core;

/// Writing and syncing through the Rust core against real repositories: a
/// bare remote, a teammate's clone made with git, the phone's made by the
/// core. Build the library first: `cargo build --release --lib` in
/// native/genbeya_core.
const library = 'native/genbeya_core/target/release/libgenbeya_core.so';

String git(String dir, List<String> args) {
  final result = Process.runSync('git', args, workingDirectory: dir);
  if (result.exitCode != 0) throw StateError('git $args: ${result.stderr}');
  return (result.stdout as String).trim();
}

String task(String status, {String extra = ''}) =>
    '---\nid: GM-1\ntitle: First\nstatus: $status\n$extra---\n\nDo it.\n';

void main() {
  final built = File(library).existsSync();
  final skip = built ? null : 'build the Git core first (native/genbeya_core)';
  late Directory tmp;
  late String remote;
  late String desk;
  late String phone;
  const signer = (name: 'Alice', email: 'alice@example.com');

  setUpAll(() async {
    if (built) {
      await RustLib.init(externalLibrary: ExternalLibrary.open(library));
    }
  });

  setUp(() async {
    if (!built) return;
    tmp = Directory.systemTemp.createTempSync('sync');
    remote = '${tmp.path}/remote.git';
    desk = '${tmp.path}/desk';
    phone = '${tmp.path}/phone';
    git(tmp.path, ['init', '--bare', '-q', '-b', 'main', remote]);
    git(tmp.path, ['clone', '-q', remote, desk]);
    git(desk, ['config', 'user.name', 'Desk']);
    git(desk, ['config', 'user.email', 'desk@example.com']);
    Directory('$desk/docs').createSync();
    File('$desk/docs/Home.md').writeAsStringSync('# Home\n\nWelcome.\n');
    git(desk, ['add', '-A']);
    git(desk, ['commit', '-q', '-m', 'Seed']);
    git(desk, ['push', '-q', 'origin', 'main']);
    // The content branch holds the tasks; the wiki stays in the checkout.
    git(desk, ['switch', '-q', '--orphan', 'genbeya']);
    Directory('$desk/tasks').createSync();
    File('$desk/tasks/GM-1.md').writeAsStringSync(task('todo'));
    File('$desk/.genbeya-content')
        .writeAsStringSync('[areas]\n\ttasks = branch\n');
    git(desk, ['add', '-A']);
    git(desk, ['commit', '-q', '-m', 'Content']);
    git(desk, ['push', '-q', 'origin', 'genbeya']);
    git(desk, ['switch', '-q', 'main']);
    await runTransfer(
      core.cloneRepository(
        url: 'file://$remote',
        dir: phone,
        branch: 'main',
        extraBranches: const ['genbeya'],
        remote: const core.RemoteOptions(
          auth: core.Auth.none(),
          trustedHostKeys: [],
        ),
        operationId: BigInt.from(7),
      ),
    );
  });

  tearDown(() {
    if (built) tmp.deleteSync(recursive: true);
  });

  ({ContentWriter writer, SyncManager sync, RepositoryModel model})
  phoneSide() {
    final gitWriter = NativeGitWriter(phone);
    final writer = ContentWriter(
      dir: phone,
      git: gitWriter,
      journal: JsonStore(File('${tmp.path}/journal.json')),
      signer: () async => signer,
    );
    return (
      writer: writer,
      sync: SyncManager(
        git: gitWriter,
        writer: writer,
        access: () async => const RemoteAccess.none(),
        signer: () async => signer,
        handle: () => 'alice',
        now: () => DateTime.utc(2026, 11, 23),
      ),
      model: RepositoryModel(NativeGitObjects(phone), folderName: 'phone'),
    );
  }

  test('a task both changed merges the Genbeya way', () async {
    final side = phoneSide();
    var state = await side.model.load();
    expect(state.place.branch, 'genbeya');
    // The phone moves GM-1 on the content branch; the desk assigns it meanwhile.
    await side.writer.write(state, {
      'tasks/GM-1.md': task('done'),
    }, 'GM-1: Move to done');
    git(desk, ['switch', '-q', 'genbeya']);
    File('$desk/tasks/GM-1.md')
        .writeAsStringSync(task('todo', extra: 'assignee: sam\n'));
    git(desk, ['commit', '-q', '-am', 'GM-1: Assign sam']);
    git(desk, ['push', '-q', 'origin', 'genbeya']);

    final report = await side.sync.sync(state);
    expect(report.merged, {'tasks/GM-1.md'});
    expect(report.pushed['genbeya'], 1);
    final merged = git(tmp.path, [
      '--git-dir',
      remote,
      'show',
      'genbeya:tasks/GM-1.md',
    ]);
    expect(merged, contains('status: done'));
    expect(merged, contains('assignee: sam'));
    state = await side.model.load();
    expect(state.tasks.single.status, 'done');
    expect(state.tasks.single.assignee, 'sam');
  }, skip: skip);

  test('what cannot merge goes to a pushed rescue branch; the branch follows the remote', () async {
    final side = phoneSide();
    final state = await side.model.load();
    await side.writer.write(state, {
      'docs/Home.md': '# Home\n\nFrom the phone.\n',
    }, 'Edit Home');
    File('$desk/docs/Home.md').writeAsStringSync('# Home\n\nFrom the desk.\n');
    git(desk, ['commit', '-q', '-am', 'Edit Home on the desk']);
    git(desk, ['push', '-q', 'origin', 'main']);

    final report = await side.sync.sync(state);
    expect(report.rescued, {'main': 'mobile/rescue/alice-2026-11-23'});
    expect(
      File('$phone/docs/Home.md').readAsStringSync(),
      '# Home\n\nFrom the desk.\n',
    );
    expect(
      git(tmp.path, [
        '--git-dir',
        remote,
        'log',
        '-1',
        '--format=%s',
        'mobile/rescue/alice-2026-11-23',
      ]),
      'Edit Home',
      reason: 'nothing is discarded',
    );
    expect(git(phone, ['status', '--porcelain']), isEmpty);
  }, skip: skip);

  test(
    'a write the app was stopped during is committed on the next sync',
    () async {
      final side = phoneSide();
      final state = await side.model.load();
      // As if the app died after writing the file, before committing it.
      File('${tmp.path}/journal.json').writeAsStringSync(
        '{"paths": ["docs/Home.md"], "message": "Edit Home"}',
      );
      File('$phone/docs/Home.md').writeAsStringSync('# Home\n\nHalf done.\n');
      final report = await side.sync.sync(state);
      expect(report.recovered, isTrue);
      expect(report.pushed['main'], 1);
      expect(
        git(tmp.path, [
          '--git-dir',
          remote,
          'log',
          '-1',
          '--format=%s',
          'main',
        ]),
        'Edit Home',
      );
      expect(
        await side.sync.sync(state),
        isA<SyncReport>().having((r) => r.nothingToDo, 'nothing to do', isTrue),
      );
    },
    skip: skip,
  );
}
