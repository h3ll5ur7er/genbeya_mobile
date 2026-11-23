import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/engines/task_engine.dart';
import 'package:genbeya_mobile/engines/task_merge.dart';

const statuses = ['todo', 'in-progress', 'review', 'done'];

String task({
  String status = 'todo',
  String extra = '',
  String body = 'Do it.\n',
  String comments = '',
}) =>
    '---\nid: A-1\ntitle: First\nstatus: $status\n$extra---\n\n$body${comments.isEmpty ? '' : '\n## Comments\n\n$comments'}';

String merge(String base, String remote, String local) => mergeTask(
  path: 'tasks/A-1.md',
  base: base,
  remote: remote,
  local: local,
  taskRoot: 'tasks',
  statuses: statuses,
);

void main() {
  test("each side's field changes are kept, written as the engine writes", () {
    final base = task();
    final remote = task(status: 'done');
    final local = task(extra: 'assignee: ada\n');
    final merged = merge(base, remote, local);
    final engine = TaskEngine();
    final expected = engine.serializeUpdate(
      remote,
      engine.validate(
        engine
            .parse('tasks/A-1.md', remote, '', 'tasks')
            .toInput()
            .copyWith(assignee: 'ada'),
        statuses,
      ),
    );
    expect(merged, expected);
    expect(merged, contains('status: done'));
    expect(merged, contains('assignee: ada'));
  });

  test('the same change on both sides merges; different ones give up', () {
    expect(
      merge(task(), task(status: 'done'), task(status: 'done')),
      contains('status: done'),
    );
    expect(
      () => merge(task(), task(status: 'done'), task(status: 'review')),
      throwsA(
        isA<MergeConflict>().having(
          (e) => e.reason,
          'reason',
          contains('status'),
        ),
      ),
    );
  });

  test('labels merge as a set', () {
    final merged = merge(
      task(extra: 'labels: [a, b]\n'),
      task(extra: 'labels: [a, b, x]\n'),
      task(extra: 'labels: [b, y]\n'),
    );
    // Desktop's engine writes changed labels as a block list ([[Upstream]]).
    expect(TaskEngine().parse('tasks/A-1.md', merged, '', 'tasks').labels, [
      'b',
      'x',
      'y',
    ]);
  });

  test('custom fields one by one, a removal included', () {
    final merged = merge(
      task(extra: 'estimate: 2d\nmilestone: M1\n'),
      task(extra: 'estimate: 3d\nmilestone: M1\n'),
      task(extra: 'estimate: 2d\n'),
    );
    expect(merged, contains('estimate: 3d'));
    expect(merged, isNot(contains('milestone')));
  });

  test('the description: one side changes it, or both give up', () {
    expect(
      merge(task(), task(), task(body: 'Do it twice.\n')),
      contains('Do it twice.'),
    );
    expect(
      () => merge(task(), task(body: 'A.\n'), task(body: 'B.\n')),
      throwsA(isA<MergeConflict>()),
    );
  });

  test("both sides' time log entries are kept", () {
    String log(List<String> lines) =>
        'Do it.\n\n## Time log\n\n${lines.map((l) => '- $l').join('\n')}\n';
    final merged = merge(
      task(body: log(['2026-11-20 — Ada — 2h'])),
      task(body: log(['2026-11-20 — Ada — 2h', '2026-11-21 — Sam — 1h'])),
      task(body: log(['2026-11-20 — Ada — 2h', '2026-11-22 — Ada — 3h'])),
    );
    expect(
      merged,
      contains(
        '- 2026-11-20 — Ada — 2h\n- 2026-11-21 — Sam — 1h\n- 2026-11-22 — Ada — 3h',
      ),
    );
  });

  test('new comments from both sides, in time order', () {
    const old = '### Ada — 2026-11-20 10:00+01:00\n\nFirst.';
    final merged = merge(
      task(comments: '$old\n'),
      task(
        comments:
            '$old\n\n### Sam — 2026-11-21 09:00+01:00\n\nFrom the desk.\n',
      ),
      task(
        comments:
            '$old\n\n### Ada — 2026-11-21 08:00+01:00\n\nFrom the phone.\n',
      ),
    );
    final phone = merged.indexOf('From the phone.');
    final desk = merged.indexOf('From the desk.');
    expect(merged.indexOf('First.'), lessThan(phone));
    expect(phone, lessThan(desk), reason: '08:00 before 09:00');
  });

  test("one side's edit of a comment applies; both editing it gives up", () {
    const old = '### Ada — 2026-11-20 10:00+01:00\n\nFirst.';
    final edited = merge(
      task(comments: '$old\n'),
      task(status: 'done', comments: '$old\n'),
      task(comments: '### Ada — 2026-11-20 10:00+01:00\n\nFirst, edited.\n'),
    );
    expect(edited, contains('First, edited.'));
    expect(edited, contains('status: done'));
    expect(
      () => merge(
        task(comments: '$old\n'),
        task(comments: '### Ada — 2026-11-20 10:00+01:00\n\nA.\n'),
        task(comments: '### Ada — 2026-11-20 10:00+01:00\n\nB.\n'),
      ),
      throwsA(isA<MergeConflict>()),
    );
    final deleted = merge(
      task(comments: '$old\n'),
      task(comments: '$old\n'),
      task(),
    );
    expect(deleted, isNot(contains('## Comments')));
  });

  test("the remote's line endings and byte order mark stay", () {
    final base = task();
    final remote = '﻿${task(status: 'done').replaceAll('\n', '\r\n')}';
    final merged = merge(base, remote, task(extra: 'priority: high\n'));
    expect(merged, startsWith('﻿---\r\n'));
    expect(merged.replaceAll('\r\n', ''), isNot(contains('\n')));
    expect(merged, contains('priority: high'));
  });

  test('gives up on what does not parse, or two different tasks', () {
    expect(
      () => merge(task(), '---\nid: [x\n---\n', task()),
      throwsA(isA<MergeConflict>()),
    );
    expect(
      () => merge(task(), task(), task().replaceFirst('id: A-1', 'id: A-2')),
      throwsA(isA<MergeConflict>()),
    );
  });
}
