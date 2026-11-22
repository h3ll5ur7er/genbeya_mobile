import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/git/git_objects.dart';
import 'package:genbeya_mobile/features/repository/links.dart';
import 'package:genbeya_mobile/access/kit/kit_host.dart';
import 'package:genbeya_mobile/managers/repository_model.dart';
import 'package:genbeya_mobile/managers/repository_session.dart';

import 'support/fake_git.dart';

void main() {
  FakeGit repository() => FakeGit()
    ..refs['HEAD'] = 'code'
    ..refs['refs/remotes/origin/genbeya'] = 'content'
    ..refs['v1.0'] = 'code'
    ..commit('code', {
      '.genbeya.yml': 'name: Demo\n',
      'src/app.dart': 'void main() {}\n',
      'docs/Old.md': '# Old\n',
    })
    ..commit('content', {
      '.genbeya-content': '[areas]\n\twiki = branch\n\ttasks = branch\n',
      'docs/Home.md': '---\ntitle: x\n---\n# Home\n\nSee [[DM-1]].\n',
      'docs/images/a.png': [137, 80, 78, 71],
      'tasks/DM-1.md':
          '---\nid: DM-1\ntitle: First\nstatus: todo\n---\n\nDo it.\n',
    });

  test('reads each path from where its area lives', () async {
    final session = RepositorySession(
      repository(),
      folderName: 'demo',
      author: 'Ada',
    );
    await session.load();
    expect(session.commitOf('docs/Home.md'), 'content');
    expect(session.commitOf('tasks/DM-1.md'), 'content');
    expect(session.commitOf('.genbeya.yml'), 'code');
    expect(session.commitOf('src/app.dart'), 'code');
    final page = await session.page('docs/Home.md');
    expect(page.title, 'Home');
    expect(page.hash, fileHash(page.content));
    await expectLater(
      session.page('docs/Old.md'),
      throwsA(isA<KitReadException>()),
    );
  });

  test('the kit context: parts versioned by their content', () async {
    final git = repository();
    final session = RepositorySession(git, folderName: 'demo', author: 'Ada');
    await session.load();
    final first = session.kitContext();
    expect(first.keys, [
      'wiki',
      'tasks',
      'plan',
      'files',
      'people',
      'settings',
      'author',
    ]);
    expect((first['tasks']!.value! as List).single, {
      'id': 'DM-1',
      'path': 'tasks/DM-1.md',
      'title': 'First',
      'status': 'todo',
    });
    expect(first['files']!.value, [
      '.genbeya.yml',
      'src/app.dart',
      'docs/Old.md',
    ]);
    expect(first['author']!.value, 'Ada');

    git
      ..commit('content2', {
        ...{for (final e in git.commits['content']!.entries) e.key: e.value},
        'tasks/DM-1.md': '---\nid: DM-1\ntitle: First\nstatus: done\n---\n',
      })
      ..refs['refs/remotes/origin/genbeya'] = 'content2';
    await session.load();
    final second = session.kitContext();
    expect(second['tasks']!.version, isNot(first['tasks']!.version));
    expect(second['wiki']!.version, first['wiki']!.version);
    expect(second['files']!.version, first['files']!.version);
  });

  test(
    'files for the kit: images, embeds and pinned revisions, read-only',
    () async {
      final session = RepositorySession(repository(), folderName: 'demo');
      await session.load();
      final files = session.kitFiles();
      expect(await files.image('docs/images/a.png'), [137, 80, 78, 71]);
      expect(await files.file('src/app.dart'), 'void main() {}\n');
      expect(await files.fileAt('src/app.dart', 'v1.0'), 'void main() {}\n');
      await expectLater(
        files.fileAt('src/app.dart', 'v9'),
        throwsA(isA<KitReadException>()),
      );
      await expectLater(
        files.planHistory(null),
        throwsA(isA<KitReadException>()),
      );
    },
  );

  test("a task's activity: each commit and what it changed", () async {
    final git = repository();
    Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));
    const v1 = '---\nid: DM-1\ntitle: First\nstatus: todo\n---\n\nDo it.\n';
    const v2 = '---\nid: DM-1\ntitle: First\nstatus: done\n---\n\nDo it.\n';
    git.histories['tasks/DM-1.md'] = [
      FileRevision(
        commit: 'c2',
        author: 'Ada',
        time: 1763700000,
        subject: 'DM-1: Done',
        path: 'tasks/DM-1.md',
        oldPath: 'tasks/Old/DM-1.md',
        before: bytes(v1),
        after: bytes(v2),
      ),
      FileRevision(
        commit: 'c1',
        author: 'Sam',
        time: 1763600000,
        subject: 'Create DM-1',
        path: 'tasks/Old/DM-1.md',
        oldPath: null,
        before: null,
        after: bytes(v1),
      ),
    ];
    final session = RepositorySession(git, folderName: 'demo');
    final state = await session.load();
    final activity = await session.taskActivity(state.tasks.single);
    expect(activity.entries.map((e) => e.changes), [
      [
        {'kind': 'field', 'field': 'status', 'from': 'todo', 'to': 'done'},
        {'kind': 'field', 'field': 'epic', 'from': 'Old', 'to': ''},
      ],
      [
        {'kind': 'created'},
      ],
    ]);
    expect(activity.entries.first.author, 'Ada');
  });

  test('links lead to tasks, pages and other files', () async {
    final session = RepositorySession(repository(), folderName: 'demo');
    final state = await session.load();
    expect(fileTarget(state, 'tasks/DM-1.md'), FileTarget.task);
    expect(fileTarget(state, 'docs/Home.md'), FileTarget.page);
    expect(fileTarget(state, 'src/app.dart'), FileTarget.file);
    expect(wikiPages(state.wiki), ['docs/Home.md']);
  });

  test(
    'links to share: Genbeya links and web links on the right branch',
    () async {
      final session = RepositorySession(
        repository(),
        folderName: 'demo',
        remote: 'https://user:token@github.com/acme/demo.git',
        branch: 'main',
      );
      await session.load();
      expect(
        session.genbeyaLink((kind: 'task', value: 'DM-1')),
        'genbeya://open?remote=https://github.com/acme/demo.git&task=DM-1',
      );
      expect(
        session.webLink('tasks/DM-1.md'),
        'https://github.com/acme/demo/blob/genbeya/tasks/DM-1.md',
        reason: 'tasks live on the content branch',
      );
      expect(
        session.webLink('src/app.dart'),
        'https://github.com/acme/demo/blob/main/src/app.dart',
      );
      expect(
        RepositorySession(
          repository(),
          folderName: 'x',
        ).genbeyaLink((kind: 'task', value: 'A')),
        isNull,
      );
    },
  );
}
