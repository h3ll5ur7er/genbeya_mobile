// US-4 · See what needs me this morning ([[User stories#us-4-see-what-needs-me-this-morning]]).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/story.dart';

void main() {
  withoutWebViews();

  Story story({
    String name = 'Ada Lovelace',
    String email = 'ada@example.com',
  }) => Story(
    name: name,
    email: email,
    code: {
      '.genbeya.yml': storySettings,
      'tasks/DM-1.md': storyTask(
        'DM-1',
        'Write the plan',
        'todo',
        fields: 'assignee: ada\n',
      ),
      'tasks/DM-2.md': storyTask(
        'DM-2',
        'Fix the login',
        'in-progress',
        fields: 'assignee: Ada Lovelace\ndue: 2020-01-01\n',
        body: '- [ ] Ask the vendor 2020-01-02\n',
      ),
      'tasks/DM-3.md': storyTask(
        'DM-3',
        'Release',
        'todo',
        fields: 'assignee: sam\n',
        body: 'Text.\n\n## Comments\n\n### Sam Rivera — 2026-11-25 09:00+01:00\n\nCan you check this, @ada?\n',
      ),
    },
  );

  testWidgets(
    'the repository opens on my tasks, my due items and my mentions',
    (tester) async {
      final s = story();
      await s.setUp(tester);
      await tester.pumpWidget(s.app);
      await Story.settle(tester);

      expect(find.text('Today'), findsWidgets);
      expect(find.text('For Ada Lovelace (@ada)'), findsOneWidget);
      expect(find.text('My tasks · 2'), findsOneWidget);
      // In progress first, its overdue date in red.
      final first = tester.getTopLeft(find.text('Fix the login'));
      final second = tester.getTopLeft(find.text('Write the plan'));
      expect(first.dy, lessThan(second.dy));
      final due = tester.widget<Text>(find.text('2020-01-01'));
      expect(due.style?.color, isNotNull, reason: 'overdue is coloured');
      expect(find.text('Checklist · 1'), findsOneWidget);
      expect(find.text('Ask the vendor 2020-01-02'), findsOneWidget);
      expect(find.text('Mentions · 1'), findsOneWidget);
      expect(
        find.text('Sam Rivera: Can you check this, @ada?'),
        findsOneWidget,
      );
    },
  );

  testWidgets('pull to refresh syncs first, then works Today out again', (
    tester,
  ) async {
    final s = story();
    await s.setUp(tester);
    await tester.pumpWidget(s.app);
    await Story.settle(tester);

    await tester.fling(find.text('My tasks · 2'), const Offset(0, 400), 1000);
    await Story.until(
      tester,
      () => find.text('Up to date.').evaluate().isNotEmpty,
      what: "the sync's report",
    );
  });

  testWidgets('when "me" matches no one, Today says how to fix it', (
    tester,
  ) async {
    final s = story(name: 'Someone Else', email: 'someone@example.org');
    await s.setUp(tester);
    await tester.pumpWidget(s.app);
    await Story.settle(tester);

    expect(find.text('Who are you here?'), findsOneWidget);
    expect(find.text('Set my name and email'), findsOneWidget);
  });
}
