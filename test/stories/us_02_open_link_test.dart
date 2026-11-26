// US-2 · Open a link a teammate sent ([[User stories#us-2-open-a-link-a-teammate-sent]]).
import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/engines/genbeya_link.dart';
import 'package:genbeya_mobile/features/links/open_link.dart';

import 'support/story.dart';

void main() {
  withoutWebViews();

  Story story() => Story(
    code: {
      '.genbeya.yml': storySettings,
      'tasks/DM-48.md': storyTask('DM-48', 'Fix the login', 'todo'),
    },
  );

  testWidgets('a link to a task opens it in the clone whose remote matches', (
    tester,
  ) async {
    final s = story();
    await s.setUp(tester);
    // The teammate's remote, spelled differently: SSH, no .git.
    final link = formatGenbeyaLink('git@github.com:acme/demo', (
      kind: 'task',
      value: 'DM-48',
    ));
    await tester.pumpWidget(
      s.launcher(
        'Open',
        (navigator, ref) => openLinkText(navigator, ref, link),
      ),
    );
    await tester.tap(find.text('Open'));
    await Story.settle(tester);

    expect(find.text('DM-48'), findsOneWidget, reason: "the task's screen");
    expect(find.text('Fix the login'), findsOneWidget);
  });

  testWidgets('a malformed link is refused with a reason', (tester) async {
    final s = story();
    await s.setUp(tester);
    await tester.pumpWidget(
      s.launcher(
        'Open',
        (navigator, ref) => openLinkText(
          navigator,
          ref,
          'genbeya://open?remote=file:///etc&page=../../passwd',
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await Story.settle(tester);

    expect(
      find.text('That is not a Genbeya link this app opens.'),
      findsOneWidget,
    );
    expect(find.text('Open'), findsOneWidget, reason: 'nothing opened');
  });

  testWidgets('without a matching clone, the app offers to clone it', (
    tester,
  ) async {
    final s = story();
    await s.setUp(tester);
    final link = formatGenbeyaLink('https://gitlab.com/other/project.git', (
      kind: 'task',
      value: 'OT-1',
    ));
    await tester.pumpWidget(
      s.launcher(
        'Open',
        (navigator, ref) => openLinkText(navigator, ref, link),
      ),
    );
    await tester.tap(find.text('Open'));
    await Story.settle(tester);

    expect(find.textContaining('clone its repository first'), findsOneWidget);
  });
}
