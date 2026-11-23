import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/storage/json_store.dart';
import 'package:genbeya_mobile/contracts/model.dart';
import 'package:genbeya_mobile/engines/task_engine.dart';
import 'package:genbeya_mobile/managers/content_writer.dart';
import 'package:genbeya_mobile/managers/page_writer.dart';
import 'package:genbeya_mobile/managers/repository_session.dart';
import 'package:genbeya_mobile/managers/task_writer.dart';

import 'support/fake_git.dart';
import 'support/fake_writer.dart';

void main() {
  late FakeGit repo;
  late FakeWriter git;
  late RepositorySession session;
  late TaskWriter tasks;
  late Directory tmp;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('tasks');
    repo = FakeGit()
      ..refs['HEAD'] = 'code'
      ..refs['refs/remotes/origin/genbeya'] = 'content'
      ..commit('code', {'.genbeya.yml': 'name: Demo\ntaskPrefix: DM\n'})
      ..commit('content', {
        '.genbeya-content': '[areas]\n\ttasks = branch\n\twiki = branch\n',
        'docs/Home.md':
            '---\ntitle: Home\n---\n# Home\n\n- [ ] first\n- [x] second\n',
        'tasks/Sync/DM-1.md': '---\nid: DM-1\ntitle: First\nstatus: todo\nlabels: [a, b]\n---\n\nDo it.\n\n- [ ] one\n- [ ] two\n',
        'tasks/DM-7.md': '---\r\nid: DM-7\r\ntitle: Seventh\r\nstatus: backlog\r\n---\r\n\r\nCRLF.\r\n',
        // A file whose task was renamed elsewhere still takes its ID.
        'tasks/Old/DM-8.md': 'not a task',
        'tasks/.templates/bug.md': '---\npriority: high\nlabels: [bug]\nseverity: "2"\n---\n\n## Steps\n',
      });
    git = FakeWriter(repo);
    session = RepositorySession(repo, folderName: 'demo');
    await session.load();
    tasks = TaskWriter(
      session: session,
      writer: ContentWriter(
        dir: tmp.path,
        git: git,
        journal: JsonStore(File('${tmp.path}/journal.json')),
        signer: () async => (name: 'Ada', email: 'ada@example.com'),
      ),
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Task taskOf(String id) => session.state!.tasks.firstWhere((t) => t.id == id);
  String fileOf(String path) => String.fromCharCodes(
    repo.commits[repo.refs['refs/heads/genbeya']]![path]!,
  );

  test('changes a field in place, committed onto the content branch', () async {
    final updated = await tasks.update(
      taskOf('DM-7'),
      taskOf('DM-7').toInput().copyWith(status: 'done'),
    );
    expect(updated.status, 'done');
    expect(git.messages, ['Update DM-7: Seventh']);
    expect(
      fileOf('tasks/DM-7.md'),
      '---\r\nid: DM-7\r\ntitle: Seventh\r\nstatus: done\r\n---\r\n\r\nCRLF.\r\n',
    );
    expect(taskOf('DM-7').status, 'done', reason: 'the session read it again');
  });

  test(
    'another epic moves the file, spelled like the existing folder',
    () async {
      final moved = await tasks.update(
        taskOf('DM-7'),
        taskOf('DM-7').toInput().copyWith(epic: 'sync'),
      );
      expect(moved.path, 'tasks/Sync/DM-7.md');
      final files = repo.commits[repo.refs['refs/heads/genbeya']]!;
      expect(files.containsKey('tasks/DM-7.md'), isFalse);
      expect(files.containsKey('tasks/Sync/DM-7.md'), isTrue);
      expect(taskOf('DM-7').epic, 'Sync');
    },
  );

  test('ticks a checkbox in the description', () async {
    final task = taskOf('DM-1');
    final offset = task.body.indexOf('- [ ] two');
    await tasks.toggle(task, offset);
    expect(fileOf('tasks/Sync/DM-1.md'), contains('- [ ] one\n- [x] two\n'));
    expect(await tasks.toggle(taskOf('DM-1'), 1), isNull);
  });

  test('refuses a stale task', () async {
    final stale = taskOf('DM-1');
    await tasks.update(stale, stale.toInput().copyWith(title: 'Newer'));
    expect(
      () => tasks.update(stale, stale.toInput().copyWith(status: 'done')),
      throwsA(isA<ChangedMeanwhileException>()),
    );
  });

  test('creates a task with the next free ID and its template', () async {
    final template = await tasks.template('bug');
    expect(template!.priority, 'high');
    var draft = emptyDraft('todo').copyWith(title: 'Crash', type: 'bug');
    final applied = withTemplate(draft, template);
    draft = applied.draft;
    expect(draft.labels, ['bug']);
    expect(draft.body, '## Steps\n');
    final created = await tasks.create(draft);
    expect(created.id, 'DM-9', reason: 'DM-8 names a file');
    expect(git.messages.last, 'Create DM-9: Crash');
    expect(
      fileOf('tasks/DM-9.md'),
      '---\nid: DM-9\ntitle: Crash\ntype: bug\nstatus: todo\npriority: high\nlabels:\n  - bug\nseverity: "2"\n---\n\n## Steps\n',
    );
    // Another type takes back what the template put in.
    final back = withoutTemplate(draft, applied.applied);
    expect(back.priority, 'none');
    expect(back.labels, isEmpty);
    expect(back.body, '');
    expect(back.fields, isEmpty);
  });

  test('a type without a template, or an invalid one, has none', () async {
    expect(await tasks.template('chore'), isNull);
    expect(await tasks.template('../x'), isNull);
    expect(
      () => tasks.create(emptyDraft('todo')),
      throwsA(isA<TaskException>()),
    );
  });

  test('ticks a checkbox on a page, refusing a stale one', () async {
    final pages = PageWriter(session: session, writer: tasks.writer);
    final page = await session.page('docs/Home.md');
    // Offsets count from the end of the frontmatter.
    final rendered =
        page.content.indexOf('- [x]') - page.content.indexOf('# Home');
    final ticked = await pages.toggle(page, rendered);
    expect(ticked!.content, endsWith('- [ ] first\n- [ ] second\n'));
    expect(git.messages.last, 'Edit docs/Home.md');
    expect(await pages.toggle(ticked, 1), isNull);
    expect(
      () => pages.toggle(page, rendered),
      throwsA(isA<ChangedMeanwhileException>()),
    );
  });
}
