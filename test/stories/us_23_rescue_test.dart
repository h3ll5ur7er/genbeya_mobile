// US-23 · Never lose an edit when sync can't finish ([[User stories#us-23-never-lose-an-edit-when-sync-cant-finish]]).
// What can't merge goes to a rescue branch: end to end through the Git core
// in test/sync_flow_test.dart. Here, the banner that follows it.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'support/story.dart';

void main() {
  withoutWebViews();

  testWidgets(
    'a banner says what differs until the desktop merged the rescue, then offers to delete it',
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
      await tester.longPress(find.text('Write the plan'));
      await Story.settle(tester);
      await tester.tap(find.text('Done').last);
      await s.committed(tester, 'Update DM-1: Write the plan');
      final mine = s.repo.refs['HEAD']!;
      final name = 'mobile/rescue/ada-2026-11-26';

      // As a sync that couldn't merge leaves it: the commit kept and
      // pushed on the rescue branch, main back at the remote.
      await tester.runAsync(() async {
        await s.git.setBranch(name, mine);
        s.repo.refs['refs/remotes/origin/$name'] = mine;
        await s.git.setBranch('main', 'c0', expected: mine);
        await s.rescues.remember((
          name: name,
          branch: 'main',
          base: 'c0',
          tip: mine,
          day: '2026-11-26',
        ));
      });
      // The sync reads the repository again; the banner follows.
      s.session.load().ignore();
      await Story.until(
        tester,
        () => find
            .textContaining('Edits on main wait on $name')
            .evaluate()
            .isNotEmpty,
        what: 'the banner',
      );
      expect(find.textContaining('1 file still differs'), findsOneWidget);
      await tester.tap(find.text('What differs'));
      await Story.settle(tester);
      expect(find.text('tasks/DM-1.md'), findsOneWidget);
      expect(find.textContaining('git merge origin/$name'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await Story.settle(tester);

      // The desktop merges the rescue branch into main and pushes.
      s.git.merge('main', name, {
        'tasks/DM-1.md': Uint8List.fromList(
          utf8.encode(s.file('tasks/DM-1.md').replaceFirst('todo', 'done')),
        ),
      });
      await tester.tap(find.byTooltip('Sync').first);
      await Story.settle(tester);
      await tester.tap(find.text('Sync now'));
      await Story.until(
        tester,
        () => find.text('Up to date.').evaluate().isNotEmpty,
        what: 'the sync',
      );
      // Back from Changes: the banner is above the tabs.
      await tester.pageBack();
      await Story.settle(tester);
      await Story.until(
        tester,
        () => find.textContaining('are on main now').evaluate().isNotEmpty,
        what: 'the offer to delete',
      );

      await tester.tap(find.text('Delete it'));
      await Story.until(
        tester,
        () => find.textContaining('Deleted $name').evaluate().isNotEmpty,
        what: 'the deletion',
      );
      expect(s.repo.refs.containsKey('refs/heads/$name'), isFalse);
      expect(s.repo.refs.containsKey('refs/remotes/origin/$name'), isFalse);
      expect(find.textContaining('are on main now'), findsNothing);
    },
  );
}
