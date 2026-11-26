// US-24 · Work on a project that never pushes to main ([[User stories#us-24-work-on-a-project-that-never-pushes-to-main]]).
import 'package:flutter_test/flutter_test.dart';

import 'support/story.dart';

void main() {
  withoutWebViews();

  testWidgets(
    'a refused push offers to move the commits to mobile/<handle>, pushed',
    (tester) async {
      final s = Story(
        code: {
          '.genbeya.yml': storySettings,
          'tasks/DM-1.md': storyTask('DM-1', 'Write the plan', 'todo'),
        },
      );
      await s.setUp(tester);
      s.git.refuses.add('main');
      await tester.pumpWidget(s.app);
      await Story.settle(tester);
      await Story.tab(tester, 'Tasks');
      await tester.longPress(find.text('Write the plan'));
      await Story.settle(tester);
      await tester.tap(find.text('Done').last);
      await s.committed(tester, 'Update DM-1: Write the plan');
      final mine = s.repo.refs['HEAD'];

      await Story.until(
        tester,
        () => find.byTooltip('1 not synced').evaluate().isNotEmpty,
        what: 'the badge',
      );
      await tester.tap(find.byTooltip('1 not synced').first);
      await Story.settle(tester);
      await tester.tap(find.text('Sync now'));
      await Story.until(
        tester,
        () => find
            .text('The remote refuses pushes to main.')
            .evaluate()
            .isNotEmpty,
        what: 'the refusal',
      );

      await tester.tap(find.text('Move my commits to a branch of my own'));
      await Story.until(
        tester,
        () => find.textContaining('mobile/ada').evaluate().isNotEmpty,
        what: 'the move',
      );
      expect(s.git.current, 'mobile/ada');
      expect(s.repo.refs['refs/remotes/origin/mobile/ada'], mine);
      expect(
        s.repo.refs['refs/heads/main'],
        'c0',
        reason: 'main is back at the remote',
      );
    },
  );
}
