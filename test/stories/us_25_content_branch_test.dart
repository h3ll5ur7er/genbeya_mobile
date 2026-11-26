// US-25 · Share the board through the content branch ([[User stories#us-25-share-the-board-through-the-content-branch]]).
import 'package:flutter_test/flutter_test.dart';

import 'support/story.dart';

void main() {
  withoutWebViews();

  testWidgets(
    'tasks come from and go to the content branch; the wiki stays with the code',
    (tester) async {
      final s = Story(
        code: {
          '.genbeya.yml': storySettings,
          'docs/Home.md': '# Home\n\n- [ ] Read me\n',
          'tasks/DM-9.md': storyTask('DM-9', 'Only in the checkout', 'todo'),
        },
        content: {
          '.genbeya-content': '[areas]\n\ttasks = branch\n',
          'tasks/DM-1.md': storyTask('DM-1', 'On the branch', 'todo'),
        },
      );
      await s.setUp(tester);
      await tester.pumpWidget(s.app);
      await Story.settle(tester);
      await Story.tab(tester, 'Tasks');
      expect(find.text('On the branch'), findsOneWidget);
      expect(find.text('Only in the checkout'), findsNothing);

      await tester.longPress(find.text('On the branch'));
      await Story.settle(tester);
      await tester.tap(find.text('Done').last);
      await s.committed(tester, 'Update DM-1: On the branch');
      expect(s.repo.refs['HEAD'], 'c0', reason: 'the checkout is untouched');
      expect(s.file('tasks/DM-1.md'), contains('status: done\n'));

      await Story.tab(tester, 'Wiki');
      FakeKit(tester)
        ..ready()
        ..tick('# Home\n\n'.length);
      await s.committed(tester, 'Edit docs/Home.md');
      expect(
        s.repo.refs['HEAD'],
        isNot('c0'),
        reason: 'the page is committed with the code',
      );

      await tester.tap(find.byTooltip('2 not synced').first);
      await Story.settle(tester);
      await tester.tap(find.text('Sync now'));
      await Story.until(
        tester,
        () => find
            .textContaining('Pushed 1 commit to genbeya.')
            .evaluate()
            .isNotEmpty,
        what: "the sync's report",
      );
      expect(find.textContaining('Pushed 1 commit to main.'), findsOneWidget);
      expect(
        s.repo.refs['refs/remotes/origin/genbeya'],
        s.repo.refs['refs/heads/genbeya'],
      );
    },
  );
}
