// US-8 · Read and work offline ([[User stories#us-8-read-and-work-offline]]).
import 'package:flutter_test/flutter_test.dart';

import 'support/story.dart';

void main() {
  withoutWebViews();

  testWidgets(
    'edits become commits on the phone; the badge counts them; sync sends them',
    (tester) async {
      final s = Story(
        code: {
          '.genbeya.yml': storySettings,
          'tasks/DM-1.md': storyTask('DM-1', 'Write the plan', 'todo'),
        },
      );
      await s.setUp(tester);
      await tester.pumpWidget(s.app);
      await Story.settle(tester);
      await Story.tab(tester, 'Tasks');
      expect(find.byTooltip('Sync'), findsWidgets);

      await tester.longPress(find.text('Write the plan'));
      await Story.settle(tester);
      await tester.tap(find.text('Done').last);
      await s.committed(tester, 'Update DM-1: Write the plan');
      expect(s.git.fetches, 0, reason: 'nothing asks the network');
      await Story.until(
        tester,
        () => find.byTooltip('1 not synced').evaluate().isNotEmpty,
        what: 'the badge',
      );

      await tester.tap(find.byTooltip('1 not synced').first);
      await Story.settle(tester);
      expect(find.text('Changes'), findsOneWidget);
      expect(find.text('1 not pushed yet'), findsOneWidget);
      expect(find.text('Update DM-1: Write the plan'), findsOneWidget);

      await tester.tap(find.text('Sync now'));
      await Story.until(
        tester,
        () => find.text('Pushed 1 commit to main.').evaluate().isNotEmpty,
        what: "the sync's report",
      );
      expect(s.repo.refs['refs/remotes/origin/main'], s.repo.refs['HEAD']);
      expect(find.text('Nothing waiting to be pushed.'), findsOneWidget);
    },
  );
}
