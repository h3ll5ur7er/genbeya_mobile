// US-10 · Tick a checklist item ([[User stories#us-10-tick-a-checklist-item]]).
import 'package:flutter_test/flutter_test.dart';

import 'support/story.dart';

void main() {
  withoutWebViews();

  Story story() => Story(
    code: {
      '.genbeya.yml': storySettings,
      'docs/Home.md': '# Home\n\n- [ ] First\n- [ ] Second 2026-12-01\n',
      'tasks/DM-1.md': storyTask(
        'DM-1',
        'Write the plan',
        'todo',
        body: 'Steps:\n\n- [ ] Draft\n- [ ] Review\n',
      ),
    },
  );

  testWidgets("ticking a task's item saves the file; only that box changes", (
    tester,
  ) async {
    final s = story();
    await s.setUp(tester);
    final before = s.file('tasks/DM-1.md');
    await tester.pumpWidget(s.app);
    await Story.settle(tester);
    await Story.tab(tester, 'Tasks');
    await tester.tap(find.text('Write the plan'));
    await Story.settle(tester);

    final kit = FakeKit(tester)..ready();
    final description = s.session.state!.tasks.single.body;
    kit.tick(description.indexOf('- [ ] Review'));
    await s.committed(tester, 'Update DM-1: Write the plan');

    expect(
      s.file('tasks/DM-1.md'),
      before.replaceFirst('- [ ] Review', '- [x] Review'),
    );
  });

  testWidgets("ticking a page's item saves the page as desktop does", (
    tester,
  ) async {
    final s = story();
    await s.setUp(tester);
    await tester.pumpWidget(s.app);
    await Story.settle(tester);
    await Story.tab(tester, 'Wiki');

    final kit = FakeKit(tester)..ready();
    kit.tick('# Home\n\n- [ ] First\n'.length);
    await s.committed(tester, 'Edit docs/Home.md');

    expect(
      s.file('docs/Home.md'),
      '# Home\n\n- [ ] First\n- [x] Second 2026-12-01\n',
    );
  });

  testWidgets('a forged offset ticks nothing', (tester) async {
    final s = story();
    await s.setUp(tester);
    await tester.pumpWidget(s.app);
    await Story.settle(tester);
    await Story.tab(tester, 'Wiki');

    FakeKit(tester)
      ..ready()
      ..tick(3);
    await Story.settle(tester);

    expect(s.git.messages, isEmpty);
  });
}
