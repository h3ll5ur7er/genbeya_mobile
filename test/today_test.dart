import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/managers/repository_session.dart';
import 'package:genbeya_mobile/managers/task_views.dart';
import 'package:genbeya_mobile/managers/today.dart';

import 'support/fake_git.dart';

String task(String id, String status, {String extra = '', String body = ''}) =>
    '---\nid: $id\ntitle: Task $id\nstatus: $status\n$extra---\n\n$body';

void main() {
  Future<RepositorySession> session({String? name, String? email}) async {
    final git = FakeGit()
      ..refs['HEAD'] = 'c1'
      ..config['user.name'] = name ?? 'Ada Lovelace'
      ..config['user.email'] = email ?? 'ada@example.com'
      ..commit('c1', {
        '.genbeya.yml': 'name: Demo\ntaskPrefix: DM\nfields:\n  - name: due\n    type: date\npeople:\n  - handle: ada\n    name: Ada Lovelace\n    email: ada@example.com\n    aliases: [countess]\n  - handle: sam\n    name: Sam Rivera\n',
        'tasks/DM-1.md': task('DM-1', 'todo', extra: 'assignee: ada\n'),
        'tasks/DM-2.md': task(
          'DM-2',
          'in-progress',
          extra: 'assignee: Ada Lovelace\ndue: 2026-11-20\n',
          body: 'Steps:\n\n- [ ] Draft by 2026-11-27\n- [x] Old 2026-11-01\n- [ ] No date\n\n```\n- [ ] fenced 2026-11-24\n```\n',
        ),
        'tasks/DM-3.md': task('DM-3', 'done', extra: 'assignee: ada\n'),
        'tasks/DM-4.md': task(
          'DM-4',
          'todo',
          extra: 'assignee: sam\n',
          body: 'Ask @countess about it.\n\n- [ ] @ada reviews 2026-11-30\n- [ ] Sam alone 2026-11-25\n\n## Comments\n\n### Sam Rivera — 2026-11-24 10:00+01:00\n\nWhat do you think, @ada?\n\n### Sam Rivera — 2026-11-25 09:00+01:00\n\nnot for her: ada@example.com\n\n### Ada Lovelace — 2026-11-25 11:00+01:00\n\nNoted, @ada.\n',
        ),
      });
    final s = RepositorySession(git, folderName: 'demo');
    await s.load();
    return s;
  }

  test("my open tasks, mentions and dated checklist items", () async {
    final s = await session();
    final today = buildToday(s.state!, on: '2026-11-26');
    expect(today.me?.handle, 'ada');
    expect(
      [for (final t in today.tasks) t.task.id],
      ['DM-2', 'DM-1'],
      reason: 'in progress first; done left out; matched by name too',
    );
    expect(today.tasks.first.tone, DueTone.overdue);
    expect(
      [for (final m in today.mentions) (m.kind, m.date)],
      [('comment', '2026-11-24T10:00+01:00'), ('task', null)],
      reason: "others' comments with dates; an alias counts; emails and one's own don't",
    );
    expect(today.mentions.first.text, 'Sam Rivera: What do you think, @ada?');
    expect(
      [for (final i in today.checklist) (i.text, i.tone)],
      [
        ('Draft by 2026-11-27', DueTone.soon),
        ('@ada reviews 2026-11-30', null),
      ],
      reason: 'open, dated, mine or mentioning me; not in code',
    );
  });

  test('pages found by the search count when they mention me', () async {
    final s = await session();
    final today = buildToday(
      s.state!,
      on: '2026-11-26',
      pageHits: [
        (
          path: 'docs/Plan.md',
          title: 'Plan',
          detail: 'docs',
          matches: [
            (
              line: 3,
              text: '- [ ] @ada signs 2026-11-25',
              ranges: const [],
              before: null,
              after: null,
            ),
            (
              line: 9,
              text: 'mail @adam or me@ada',
              ranges: const [],
              before: null,
              after: null,
            ),
          ],
        ),
      ],
    );
    expect(today.mentions.any((m) => m.kind == 'page'), isTrue);
    expect(today.checklist.first, (
      path: 'docs/Plan.md',
      title: 'Plan',
      text: '@ada signs 2026-11-25',
      date: '2026-11-25',
      tone: DueTone.overdue,
    ));
  });

  test('an identity that matches no one: nothing, and no me', () async {
    final s = await session(name: 'Nobody Here', email: 'nobody@example.org');
    final today = buildToday(s.state!, on: '2026-11-26');
    expect(today.me, isNull);
    expect(today.isEmpty, isTrue);
  });
}
