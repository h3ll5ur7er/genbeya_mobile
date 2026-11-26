// US-14 · Reassign or reprioritise ([[User stories#us-14-reassign-or-reprioritise]]).
import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/managers/task_views.dart';
import 'package:material_ui/material_ui.dart';

import 'support/story.dart';

void main() {
  withoutWebViews();

  testWidgets(
    'each chip opens its sheet: assignee, priority, epic (moving the file), fields by kind',
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
      await tester.tap(find.text('Write the plan'));
      await Story.settle(tester);

      await tester.tap(find.text('Unassigned'));
      await Story.settle(tester);
      await tester.tap(find.text('Sam Rivera'));
      await s.committed(tester, 'Update DM-1: Write the plan');
      expect(s.file('tasks/DM-1.md'), contains('assignee: sam\n'));

      await tester.tap(find.text('Priority'));
      await Story.settle(tester);
      await tester.tap(find.text('Urgent'));
      await Story.until(
        tester,
        () => s.file('tasks/DM-1.md').contains('priority: urgent\n'),
        what: 'the priority',
      );

      await tester.tap(find.text('Estimate'));
      await Story.settle(tester);
      await tester.enterText(find.byType(TextField).last, '2d');
      await tester.tap(find.text('Save'));
      await Story.until(
        tester,
        () => s.file('tasks/DM-1.md').contains('estimate: 2d\n'),
        what: 'the estimate',
      );

      await tester.tap(find.text('Due'));
      await Story.settle(tester);
      await tester.tap(find.text('OK'));
      await Story.until(
        tester,
        () => s.file('tasks/DM-1.md').contains('due: ${today()}\n'),
        what: 'the date',
      );

      await tester.tap(find.text('No epic'));
      await Story.settle(tester);
      await tester.tap(find.text('New epic…'));
      await Story.settle(tester);
      await tester.enterText(find.byType(TextField).last, 'Auth');
      await tester.tap(find.text('Move'));
      await Story.until(
        tester,
        () => s.repo.commits[s.repo.refs['HEAD']]!.containsKey(
          'tasks/Auth/DM-1.md',
        ),
        what: 'the file in its epic',
      );
      expect(
        s.repo.commits[s.repo.refs['HEAD']]!.containsKey('tasks/DM-1.md'),
        isFalse,
      );
      final moved = s.file('tasks/Auth/DM-1.md');
      expect(moved, contains('assignee: sam\n'));
      expect(moved, contains('estimate: 2d\n'));
    },
  );
}
