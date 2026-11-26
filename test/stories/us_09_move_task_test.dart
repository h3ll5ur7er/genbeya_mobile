// US-9 · Move a task after stand-up ([[User stories#us-9-move-a-task-after-stand-up]]).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/story.dart';

void main() {
  withoutWebViews();

  Story story() => Story(
    code: {
      '.genbeya.yml': storySettings,
      // A field order, a YAML comment and CRLF lines that must survive.
      'tasks/DM-1.md': '---\r\nid: DM-1\r\ntitle: Write the plan\r\nstatus: todo\r\n# keep me\r\nassignee: ada\r\n---\r\n\r\nSteps.\r\n',
      'tasks/DM-2.md': storyTask('DM-2', 'Ship it', 'in-progress'),
    },
  );

  testWidgets('Move to… on long press changes only the status, in one commit', (
    tester,
  ) async {
    final s = story();
    await s.setUp(tester);
    await tester.pumpWidget(s.app);
    await Story.settle(tester);
    await Story.tab(tester, 'Tasks');

    await tester.longPress(find.text('Write the plan'));
    await Story.settle(tester);
    await tester.tap(find.text('Review').last);
    await s.committed(tester, 'Update DM-1: Write the plan');

    expect(
      s.file('tasks/DM-1.md'),
      '---\r\nid: DM-1\r\ntitle: Write the plan\r\nstatus: review\r\n# keep me\r\nassignee: ada\r\n---\r\n\r\nSteps.\r\n',
    );
    expect(s.git.messages, ['Update DM-1: Write the plan']);
    expect(find.text('Review · 1'), findsOneWidget);
  });

  testWidgets('dragging a card onto a state on the board moves it', (
    tester,
  ) async {
    final s = story();
    await s.setUp(tester);
    await tester.pumpWidget(s.app);
    await Story.settle(tester);
    await Story.tab(tester, 'Tasks');
    await tester.tap(find.byTooltip('Board'));
    await Story.settle(tester);

    // The board opens on the first column: Todo holds DM-1.
    await tester.tap(find.text('Todo 1'));
    await Story.settle(tester);
    final card = tester.getCenter(find.text('Write the plan'));
    final target = tester.getCenter(find.text('In progress 1'));
    final drag = await tester.startGesture(card);
    await tester.pump(const Duration(milliseconds: 600));
    await drag.moveTo(target);
    await tester.pump();
    await drag.up();
    await s.committed(tester, 'Update DM-1: Write the plan');

    expect(s.file('tasks/DM-1.md'), contains('status: in-progress\r\n'));
    expect(s.git.messages, ['Update DM-1: Write the plan']);
  });

  testWidgets("the task's status chip opens the states", (tester) async {
    final s = story();
    await s.setUp(tester);
    await tester.pumpWidget(s.app);
    await Story.settle(tester);
    await Story.tab(tester, 'Tasks');
    await tester.tap(find.text('Ship it'));
    await Story.settle(tester);

    await tester.tap(find.text('In progress'));
    await Story.settle(tester);
    await tester.tap(find.text('Review').last);
    await s.committed(tester, 'Update DM-2: Ship it');

    expect(s.file('tasks/DM-2.md'), contains('status: review\n'));
    expect(find.widgetWithText(ActionChip, 'Review'), findsOneWidget);
  });
}
