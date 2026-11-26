// US-5 · Look up a decision during a meeting ([[User stories#us-5-look-up-a-decision-during-a-meeting]]).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/story.dart';

void main() {
  withoutWebViews();

  testWidgets('search finds pages by title as I type, and by text below', (
    tester,
  ) async {
    final s = Story(
      code: {
        '.genbeya.yml': storySettings,
        'docs/Home.md': '# Home\n',
        'docs/Decisions.md':
            '# Decisions\n\n## Database\n\nWe use Postgres for the board.\n',
        'tasks/DM-1.md': storyTask('DM-1', 'Pick a database', 'done'),
      },
    );
    await s.setUp(tester);
    await tester.pumpWidget(s.app);
    await Story.settle(tester);
    await Story.tab(tester, 'Wiki');
    await tester.tap(find.byTooltip('Search'));
    await Story.settle(tester);

    await tester.enterText(find.byType(TextField), 'decis');
    await Story.settle(tester);
    expect(find.text('Decisions'), findsWidgets, reason: 'the page by title');

    await tester.enterText(find.byType(TextField), 'postgres');
    await Story.until(
      tester,
      () => find
          .textContaining('We use Postgres', findRichText: true)
          .evaluate()
          .isNotEmpty,
      what: 'the matched line',
    );

    await tester.tap(
      find.textContaining('We use Postgres', findRichText: true).first,
    );
    await Story.settle(tester);
    expect(find.text('Decisions'), findsWidgets, reason: 'the page opened');
    expect(find.byTooltip('Search'), findsWidgets);
  });
}
