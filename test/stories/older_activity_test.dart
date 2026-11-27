// A task's activity past a shallow clone's edge ([[GM-29]]): what US-1's
// shallow clone leaves out is fetched when asked for.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/git/git_objects.dart';
import 'package:material_ui/material_ui.dart';

import 'support/story.dart';

FileRevision revision(
  String commit,
  String subject,
  String? before,
  String after,
) => FileRevision(
  commit: commit,
  author: 'Sam Rivera',
  time: DateTime.utc(2026, 10, 1).millisecondsSinceEpoch ~/ 1000,
  subject: subject,
  path: 'tasks/DM-1.md',
  oldPath: before == null ? null : 'tasks/DM-1.md',
  before: before == null ? null : Uint8List.fromList(utf8.encode(before)),
  after: Uint8List.fromList(utf8.encode(after)),
);

/// Scrolls the task to its end, where the activity is, clear of the composer.
Future<void> reach(WidgetTester tester, Finder finder) async {
  final list = find
      .ancestor(of: finder, matching: find.byType(Scrollable))
      .first;
  await tester.drag(list, const Offset(0, -2000));
  await Story.settle(tester);
}

void main() {
  withoutWebViews();

  testWidgets(
    'the activity offers older history, fetches it as asked, and shows it',
    (tester) async {
      final todo = storyTask('DM-1', 'Write the plan', 'todo');
      final doing = storyTask('DM-1', 'Write the plan', 'in-progress');
      final s = Story(
        code: {'.genbeya.yml': storySettings, 'tasks/DM-1.md': doing},
      );
      await s.setUp(tester);
      s.repo
        ..shallow = true
        ..histories['tasks/DM-1.md'] = [
          revision('c2', 'Update DM-1: Write the plan', todo, doing),
        ];
      s.git.older['tasks/DM-1.md'] = [
        revision('c1', 'Create DM-1: Write the plan', null, todo),
      ];
      await tester.pumpWidget(s.app);
      await Story.settle(tester);
      await Story.tab(tester, 'Tasks');
      await tester.tap(find.text('Write the plan'));
      await Story.settle(tester);

      final fetch = find.text('Fetch older history');
      await reach(tester, fetch);
      expect(find.textContaining('the clone is shallow'), findsOneWidget);
      await tester.tap(fetch);
      await Story.settle(tester);
      // How much, and from where.
      expect(find.textContaining('next 200 commits'), findsOneWidget);
      expect(find.textContaining('github.com'), findsOneWidget);
      await tester.tap(find.text('200 more'));
      await Story.until(
        tester,
        () => s.git.deepened.isNotEmpty,
        what: 'the fetch',
      );
      expect(s.git.deepened, [200]);
      // Still shallow: the offer stays, with the older commit shown above it.
      expect(find.textContaining('created the task'), findsOneWidget);
      expect(fetch, findsOneWidget);

      await reach(tester, fetch);
      await tester.tap(fetch);
      await Story.settle(tester);
      await tester.tap(find.text('All of it'));
      await Story.until(
        tester,
        () => s.git.deepened.length == 2,
        what: 'the whole history',
      );
      expect(s.git.deepened, [200, null]);
      expect(find.textContaining('the clone is shallow'), findsNothing);
      expect(fetch, findsNothing);
    },
  );
}
