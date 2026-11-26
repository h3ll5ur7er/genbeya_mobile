import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/git/git_remote.dart';
import 'package:genbeya_mobile/access/native/native_git_objects.dart';
import 'package:genbeya_mobile/access/native/native_git_writer.dart';
import 'package:genbeya_mobile/access/native/transfers.dart';
import 'package:genbeya_mobile/access/storage/json_store.dart';
import 'package:genbeya_mobile/engines/task_engine.dart';
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
        objects: NativeGitObjects(phone),
        writer: writer,
        access: () async => const RemoteAccess.none(),
        signer: () async => signer,
        handle: () => 'alice',
        now: () => DateTime.utc(2026, 11, 23),
      ),
      model: RepositoryModel(NativeGitObjects(phone), folderName: 'phone'),
    );
  }

  test('US-22: a task both changed merges the Genbeya way', () async {
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

  test(
    'US-22: a comment written on both sides keeps both, in time order',
    () async {
      final side = phoneSide();
      final state = await side.model.load();
      final tasks = TaskEngine();
      // The phone comments at 10:00 UTC; the desk at 09:30, pushed first.
      await side.writer.write(state, {
        'tasks/GM-1.md': tasks.addComment(
          task('todo'),
          'Alice',
          DateTime.utc(2026, 11, 23, 10),
          'From the phone.',
        ),
      }, 'Comment on GM-1');
      git(desk, ['switch', '-q', 'genbeya']);
      File('$desk/tasks/GM-1.md').writeAsStringSync(
        tasks.addComment(
          task('todo'),
          'Desk',
          DateTime.utc(2026, 11, 23, 9, 30),
          'From the desk.',
        ),
      );
      git(desk, ['commit', '-q', '-am', 'Comment on GM-1']);
      git(desk, ['push', '-q', 'origin', 'genbeya']);

      final report = await side.sync.sync(state);
      expect(report.merged, {'tasks/GM-1.md'});
      expect(report.rescued, isEmpty);
      final merged = git(tmp.path, [
        '--git-dir',
        remote,
        'show',
        'genbeya:tasks/GM-1.md',
      ]);
      expect(
        merged,
        endsWith(
          '## Comments\n\n### Desk — 2026-11-23 09:30+00:00\n\nFrom the desk.\n\n### Alice — 2026-11-23 10:00+00:00\n\nFrom the phone.',
        ),
      );
    },
    skip: skip,
  );

  String newTask(String id, String title, {String status = 'todo'}) =>
      '---\nid: $id\ntitle: $title\nstatus: $status\n---\n\nSee $id.\n';

  String remoteFile(String branch, String path) =>
      git(tmp.path, ['--git-dir', remote, 'show', '$branch:$path']);

  test('US-22: both made the next task: the phone renumbers its own, with what refers to it', () async {
    final side = phoneSide();
    final state = await side.model.load();
    final tasks = TaskEngine();
    // The phone makes GM-2, edits it, and comments on GM-1 about it.
    await side.writer.write(state, {
      'tasks/GM-2.md': newTask('GM-2', "Phone's"),
    }, "Create GM-2: Phone's");
    await side.writer.write(state, {
      'tasks/GM-2.md': newTask('GM-2', "Phone's", status: 'done'),
    }, "Update GM-2: Phone's");
    await side.writer.write(state, {
      'tasks/GM-1.md': tasks.addComment(
        task('todo'),
        'Alice',
        DateTime.utc(2026, 11, 26, 10),
        'Split off as [[GM-2]].',
      ),
    }, 'Comment on GM-1');
    // The desk made its own GM-2 at the same path, and moved GM-1.
    git(desk, ['switch', '-q', 'genbeya']);
    File('$desk/tasks/GM-2.md').writeAsStringSync(newTask('GM-2', "Desk's"));
    File('$desk/tasks/GM-1.md').writeAsStringSync(task('review'));
    git(desk, ['add', '-A']);
    git(desk, ['commit', '-q', '-m', "Create GM-2: Desk's"]);
    git(desk, ['push', '-q', 'origin', 'genbeya']);

    final report = await side.sync.sync(state);
    expect(report.renumbered, {'GM-2': 'GM-3'});
    expect(report.rescued, isEmpty);
    expect(
      remoteFile('genbeya', 'tasks/GM-2.md'),
      newTask('GM-2', "Desk's").trim(),
      reason: "the desk's task is untouched",
    );
    expect(
      remoteFile('genbeya', 'tasks/GM-3.md'),
      newTask('GM-3', "Phone's", status: 'done').trim(),
      reason: "the phone's task, with its edit, under the new ID",
    );
    final first = remoteFile('genbeya', 'tasks/GM-1.md');
    expect(first, contains('status: review'), reason: "the desk's change");
    expect(first, contains('Split off as [[GM-3]].'));
    expect(
      git(tmp.path, [
        '--git-dir',
        remote,
        'log',
        '--format=%s',
        '-1',
        'genbeya',
      ]),
      'Renumber GM-2 to GM-3 where this phone referred to it',
    );
    final reread = await side.model.load();
    expect(reread.tasks.map((t) => t.id).toList()..sort(), [
      'GM-1',
      'GM-2',
      'GM-3',
    ]);
  }, skip: skip);

  test(
    'US-22: the same next ID in different epics: no conflict, still renumbered',
    () async {
      final side = phoneSide();
      final state = await side.model.load();
      await side.writer.write(state, {
        'tasks/App/GM-2.md': newTask('GM-2', "Phone's"),
      }, "Create GM-2: Phone's");
      git(desk, ['switch', '-q', 'genbeya']);
      Directory('$desk/tasks/Web').createSync(recursive: true);
      File('$desk/tasks/Web/GM-2.md')
          .writeAsStringSync(newTask('GM-2', "Desk's"));
      git(desk, ['add', '-A']);
      git(desk, ['commit', '-q', '-m', "Create GM-2: Desk's"]);
      git(desk, ['push', '-q', 'origin', 'genbeya']);

      final report = await side.sync.sync(state);
      expect(report.renumbered, {'GM-2': 'GM-3'});
      expect(remoteFile('genbeya', 'tasks/Web/GM-2.md'), contains("Desk's"));
      expect(
        remoteFile('genbeya', 'tasks/App/GM-3.md'),
        newTask('GM-3', "Phone's").trim(),
      );
      expect(
        () => remoteFile('genbeya', 'tasks/App/GM-2.md'),
        throwsStateError,
        reason: 'no second GM-2',
      );
    },
    skip: skip,
  );

  test(
    "US-22: a renumbered task's ID follows into another new task's depends_on",
    () async {
      final side = phoneSide();
      final state = await side.model.load();
      await side.writer.write(state, {
        'tasks/GM-2.md': newTask('GM-2', "Phone's"),
      }, "Create GM-2: Phone's");
      await side.writer.write(state, {
        'tasks/GM-3.md': '---\nid: GM-3\ntitle: After it\nstatus: todo\ndepends_on: [GM-2]\n---\n\nOnce GM-2 is done.\n',
      }, 'Create GM-3: After it');
      git(desk, ['switch', '-q', 'genbeya']);
      File('$desk/tasks/GM-2.md').writeAsStringSync(newTask('GM-2', "Desk's"));
      git(desk, ['add', '-A']);
      git(desk, ['commit', '-q', '-m', "Create GM-2: Desk's"]);
      git(desk, ['push', '-q', 'origin', 'genbeya']);

      final report = await side.sync.sync(state);
      expect(report.renumbered, {
        'GM-2': 'GM-4',
      }, reason: 'GM-3 is taken by the phone itself');
      expect(remoteFile('genbeya', 'tasks/GM-4.md'), contains("Phone's"));
      expect(
        remoteFile('genbeya', 'tasks/GM-3.md'),
        '---\nid: GM-3\ntitle: After it\nstatus: todo\ndepends_on: [GM-4]\n---\n\nOnce GM-4 is done.',
      );
      expect(remoteFile('genbeya', 'tasks/GM-2.md'), contains("Desk's"));
    },
    skip: skip,
  );

  test('US-22: a page on the checked-out branch follows a task renumbered on the content branch', () async {
    final side = phoneSide();
    final state = await side.model.load();
    await side.writer.write(state, {
      'tasks/GM-2.md': newTask('GM-2', "Phone's"),
    }, "Create GM-2: Phone's");
    // The page lives with the code: another branch than the task.
    await side.writer.write(state, {
      'docs/Home.md': '# Home\n\nWelcome.\n\nPlan: [[GM-2]], see [[tasks/GM-2.md]] (DM-20, GM-20 untouched).\n',
    }, 'Edit docs/Home.md');
    // The desk takes GM-2 and adds a line to the same page.
    git(desk, ['switch', '-q', 'genbeya']);
    File('$desk/tasks/GM-2.md').writeAsStringSync(newTask('GM-2', "Desk's"));
    git(desk, ['add', '-A']);
    git(desk, ['commit', '-q', '-m', "Create GM-2: Desk's"]);
    git(desk, ['push', '-q', 'origin', 'genbeya']);
    git(desk, ['switch', '-q', 'main']);
    File('$desk/docs/Home.md')
        .writeAsStringSync('# Home by the desk\n\nWelcome.\n');
    git(desk, ['commit', '-q', '-am', 'Edit docs/Home.md']);
    git(desk, ['push', '-q', 'origin', 'main']);

    final report = await side.sync.sync(state);
    expect(report.renumbered, {'GM-2': 'GM-3'});
    expect(report.rescued, isEmpty);
    expect(
      remoteFile('main', 'docs/Home.md'),
      '# Home by the desk\n\nWelcome.\n\nPlan: [[GM-3]], see [[tasks/GM-3.md]] (DM-20, GM-20 untouched).',
      reason: "the desk's line kept, the phone's line renumbered",
    );
    expect(
      git(tmp.path, ['--git-dir', remote, 'log', '--format=%s', '-1', 'main']),
      'Renumber GM-2 to GM-3 where this phone referred to it',
    );
  }, skip: skip);

  test('US-23: what cannot merge goes to a pushed rescue branch; the branch follows the remote', () async {
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
    'US-23: a write the app was stopped during is committed on the next sync',
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

  test('US-24: a push the remote refuses is reported; the commits move to a branch of their own', () async {
    final side = phoneSide();
    final state = await side.model.load();
    // A protected main: the remote turns pushes to it down.
    final hook = File('$remote/hooks/pre-receive')
      ..writeAsStringSync(
        '#!/bin/sh\nwhile read old new ref; do\n  [ "\$ref" = refs/heads/main ] && echo "main is protected" && exit 1\ndone\nexit 0\n',
      );
    Process.runSync('chmod', ['+x', hook.path]);
    // libgit2 writes to a file:// remote directly, without its hooks: serve
    // it with git daemon, whose receive-pack runs them.
    final socket = await ServerSocket.bind('127.0.0.1', 0);
    final port = socket.port;
    await socket.close();
    final daemon = await Process.start('git', [
      'daemon',
      '--reuseaddr',
      '--export-all',
      '--enable=receive-pack',
      '--base-path=${tmp.path}',
      '--listen=127.0.0.1',
      '--port=$port',
      tmp.path,
    ]);
    addTearDown(daemon.kill);
    for (var i = 0; i < 50; i++) {
      try {
        await (await Socket.connect('127.0.0.1', port)).close();
        break;
      } on SocketException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    git(phone, [
      'remote',
      'set-url',
      'origin',
      'git://127.0.0.1:$port/remote.git',
    ]);
    await side.writer.write(state, {
      'docs/Home.md': '# Home\n\nMine.\n',
    }, 'Edit Home');
    final report = await side.sync.sync(state);
    expect(report.refused, {'main'});
    expect(report.rescued, isEmpty, reason: 'nothing conflicted');

    final own = await side.sync.moveToOwnBranch('main');
    expect(own, 'mobile/alice');
    expect(git(phone, ['branch', '--show-current']), 'mobile/alice');
    expect(File('$phone/docs/Home.md').readAsStringSync(), '# Home\n\nMine.\n');
    expect(
      git(tmp.path, [
        '--git-dir',
        remote,
        'log',
        '-1',
        '--format=%s',
        'mobile/alice',
      ]),
      'Edit Home',
    );
    expect(
      git(phone, ['rev-parse', 'main']),
      git(phone, ['rev-parse', 'origin/main']),
    );
  }, skip: skip);
}
