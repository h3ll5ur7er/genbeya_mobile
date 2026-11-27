import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/git/git_remote.dart';
import 'package:genbeya_mobile/access/native/native_git_objects.dart';
import 'package:genbeya_mobile/access/native/native_git_writer.dart';
import 'package:genbeya_mobile/access/native/transfers.dart';
import 'package:genbeya_mobile/access/storage/json_store.dart';
import 'package:genbeya_mobile/engines/content_layout.dart';
import 'package:genbeya_mobile/managers/content_writer.dart';
import 'package:genbeya_mobile/managers/repository_model.dart';
import 'package:genbeya_mobile/managers/sync_manager.dart';
import 'package:genbeya_mobile/src/rust/api/git.dart' as core;
import 'package:genbeya_mobile/src/rust/frb_generated.dart';
import 'package:genbeya_mobile/src/rust/git.dart' as core;

/// The phone on a repository whose content branch Genbeya desktop laid out
/// ([[GM-15]], US-25): tool/conformance/desktop-repository.ts runs
/// desktop's own ContentStore, at the commit in kit/GENBEYA_REF, to move
/// the tasks and the wiki onto `genbeya`, edit both there and sync. The
/// conformance job checks that the export below is what it makes.
///
/// Needs the Git core built: `cargo build --release --lib` in
/// native/genbeya_core.
const library = 'native/genbeya_core/target/release/libgenbeya_core.so';
const export = 'tool/conformance/expected/desktop-repository.fi';

String git(String dir, List<String> args) {
  final process = Process.runSync(
    'git',
    args,
    workingDirectory: dir,
    environment: const {
      'GIT_CONFIG_GLOBAL': '/dev/null',
      'GIT_CONFIG_NOSYSTEM': '1',
    },
  );
  if (process.exitCode != 0) throw StateError('git $args: ${process.stderr}');
  return (process.stdout as String).trim();
}

void main() {
  final built = File(library).existsSync();
  final skip = built ? null : 'build the Git core first (native/genbeya_core)';
  late Directory tmp;
  late String remote;
  late String phone;
  const signer = (name: 'Alice', email: 'alice@example.com');

  setUpAll(() async {
    if (built) {
      await RustLib.init(externalLibrary: ExternalLibrary.open(library));
    }
  });

  setUp(() async {
    if (!built) return;
    tmp = Directory.systemTemp.createTempSync('desktop');
    remote = '${tmp.path}/remote.git';
    phone = '${tmp.path}/phone';
    git(tmp.path, ['init', '--bare', '-q', '-b', 'main', remote]);
    final imported = await Process.run('sh', [
      '-c',
      'git fast-import --quiet < "\$1"',
      'import',
      File(export).absolute.path,
    ], workingDirectory: remote);
    if (imported.exitCode != 0) throw StateError('${imported.stderr}');
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
        operationId: BigInt.from(11),
      ),
    );
  });

  tearDown(() {
    if (built) tmp.deleteSync(recursive: true);
  });

  String onRemote(String revision) =>
      git(tmp.path, ['--git-dir', remote, ...revision.split(' ')]);

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
        objects: NativeGitObjects(phone),
        writer: writer,
        access: () async => const RemoteAccess.none(),
        signer: () async => signer,
        handle: () => 'alice',
        now: () => DateTime.utc(2026, 11, 27),
      ),
      model: RepositoryModel(NativeGitObjects(phone), folderName: 'phone'),
    );
  }

  Future<String> read(String commit, String path) async => utf8.decode(
    (await NativeGitObjects(phone).readFileAt(commit, path, 1 << 20))!,
  );

  test('the export is the repository desktop made', () async {
    // Desktop's steps, as its commits name them, on top of an empty root.
    expect(onRemote('log --format=%s --reverse genbeya').split('\n'), [
      'Start the Genbeya content branch',
      'Move tasks to the content branch',
      'Move the wiki to the content branch',
      'Update DP-1: First',
      'Edit docs/Home.md',
    ]);
    expect(onRemote('ls-tree genbeya~4'), isEmpty);
    expect(onRemote('log --format=%s main'), 'Initial commit');
  }, skip: skip);

  test('US-25: each area is read where desktop put it', () async {
    final side = phoneSide();
    final state = await side.model.load();
    final place = state.place;
    expect(place.branch, 'genbeya');
    expect(place.branchCommit, onRemote('rev-parse genbeya'));
    expect(place.areas, {
      'wiki': StorageMode.branch,
      'tasks': StorageMode.branch,
      'settings': StorageMode.checkout,
      'pulls': StorageMode.checkout,
    });
    // Settings from the checkout; tasks and pages from the branch, not the
    // copies main still has from before the move.
    expect(state.settings.taskPrefix, 'DP');
    expect(
      {for (final t in state.tasks) t.id: t.status},
      {'DP-1': 'in-progress', 'DP-2': 'todo'},
    );
    expect(
      state.tasks.singleWhere((t) => t.id == 'DP-2').path,
      'tasks/Auth/DP-2.md',
    );
    expect(
      await read(place.commitOf('wiki'), 'docs/Home.md'),
      contains('from the content branch'),
    );
    expect(await read(place.head, 'tasks/DP-1.md'), contains('status: todo'));
  }, skip: skip);

  test('US-25: edits go onto desktop\'s branch and sync over a desk edit made meanwhile', () async {
    final side = phoneSide();
    var state = await side.model.load();
    final desktopTip = state.place.branchCommit!;
    final head = state.place.head;
    await side.writer.write(state, {
      'tasks/Auth/DP-2.md': (await read(
        desktopTip,
        'tasks/Auth/DP-2.md',
      )).replaceFirst('status: todo', 'status: done'),
    }, 'Update DP-2: Sign in');
    state = await side.model.load();
    await side.writer.write(state, {
      'docs/Guide.md': '# Guide\n\n- [x] Read it\n',
    }, 'Edit docs/Guide.md');

    // Meanwhile on the desk: an edit to another task, synced as desktop
    // syncs (rebase onto the remote, push).
    final desk = '${tmp.path}/desk';
    git(tmp.path, ['clone', '-q', '-b', 'genbeya', remote, desk]);
    git(desk, ['config', 'user.name', 'Desk']);
    git(desk, ['config', 'user.email', 'desk@example.com']);
    File('$desk/tasks/DP-1.md').writeAsStringSync(
      File('$desk/tasks/DP-1.md')
          .readAsStringSync()
          .replaceFirst('status: in-progress', 'status: done'),
    );
    git(desk, ['commit', '-q', '-am', 'Update DP-1: First']);
    git(desk, ['push', '-q', 'origin', 'genbeya']);

    state = await side.model.load();
    final report = await side.sync.sync(state);
    expect(report.pushed['genbeya'], 2);
    expect(report.rescued, isEmpty);

    // One line of history on desktop's branch, the phone's commits last;
    // the layout file and the code branch as desktop left them.
    expect(onRemote('log --format=%s --reverse genbeya').split('\n').skip(3), [
      'Update DP-1: First',
      'Edit docs/Home.md',
      'Update DP-1: First',
      'Update DP-2: Sign in',
      'Edit docs/Guide.md',
    ]);
    expect(onRemote('rev-list --merges genbeya'), isEmpty);
    expect(onRemote('rev-list genbeya').split('\n'), contains(desktopTip));
    expect(
      onRemote('show genbeya:.genbeya-content'),
      onRemote('show $desktopTip:.genbeya-content'),
    );
    expect(onRemote('rev-parse main'), head);
    expect(onRemote('show genbeya:tasks/DP-1.md'), contains('status: done'));
    expect(
      onRemote('show genbeya:tasks/Auth/DP-2.md'),
      contains('status: done'),
    );
    expect(onRemote('show genbeya:docs/Guide.md'), contains('[x] Read it'));
    // Signed as the phone's user, the desk's commit as the desk.
    expect(onRemote('log -3 --format=%an genbeya').split('\n'), [
      'Alice',
      'Alice',
      'Desk',
    ]);
  }, skip: skip);
}
