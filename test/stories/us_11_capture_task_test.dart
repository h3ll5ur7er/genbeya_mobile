// US-11 · Capture a task from another app ([[User stories#us-11-capture-a-task-from-another-app]]).
import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/features/tasks/start_new_task.dart';
import 'package:material_ui/material_ui.dart';

import 'support/story.dart';

void main() {
  withoutWebViews();

  Story story() => Story(
    code: {
      '.genbeya.yml': '$storySettings\ntypes: [bug, feature]\n',
      'tasks/DM-1.md': storyTask('DM-1', 'Write the plan', 'todo'),
      // A file whose task was renamed on another branch still takes its ID.
      'tasks/Old/DM-2.md': 'a file no task claims',
      'tasks/.templates/bug.md':
          '---\npriority: high\nlabels: [bug]\n---\n\n## Steps to reproduce\n',
    },
  );

  testWidgets('shared text becomes a new task with the next free ID', (
    tester,
  ) async {
    final s = story();
    await s.setUp(tester);
    await tester.pumpWidget(
      s.launcher(
        'Share',
        (navigator, ref) => startNewTask(
          navigator,
          ref,
          text: 'Export fails for the customer\nThey click Export and nothing happens.',
        ),
      ),
    );
    await tester.tap(find.text('Share'));
    await Story.settle(tester);

    expect(find.text('New task'), findsOneWidget);
    expect(find.text('Export fails for the customer'), findsOneWidget);

    // The kit's editor holds the rest; Create asks it for the text.
    final kit = FakeKit(tester)..ready();
    kit.save('They click Export and nothing happens.');
    await s.committed(tester, 'Create DM-3: Export fails for the customer');

    expect(
      s.file('tasks/DM-3.md'),
      '---\nid: DM-3\ntitle: Export fails for the customer\nstatus: backlog\n---\n\nThey click Export and nothing happens.\n',
    );
    expect(find.text('DM-3'), findsOneWidget, reason: 'the new task opens');
  });

  testWidgets('choosing a type fills the description from its template', (
    tester,
  ) async {
    final s = story();
    await s.setUp(tester);
    await tester.pumpWidget(
      s.launcher('New task', (navigator, ref) => startNewTask(navigator, ref)),
    );
    await tester.tap(find.text('New task'));
    await Story.settle(tester);

    await tester.enterText(find.byType(TextField).first, 'Crash on start');
    await tester.tap(find.text('Type'));
    await Story.settle(tester);
    await tester.tap(find.text('Bug').last);
    await Story.settle(tester);

    final kit = FakeKit(tester)..ready();
    expect(kit.host.editing!.text, '## Steps to reproduce\n');
    kit.save(kit.host.editing!.text);
    await s.committed(tester, 'Create DM-3: Crash on start');

    expect(
      s.file('tasks/DM-3.md'),
      '---\nid: DM-3\ntitle: Crash on start\ntype: bug\nstatus: backlog\npriority: high\nlabels:\n  - bug\n---\n\n## Steps to reproduce\n',
    );
  });
}
