// US-6 · Follow a reference ([[User stories#us-6-follow-a-reference]]).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/story.dart';

void main() {
  withoutWebViews();

  Story story() => Story(
    code: {
      '.genbeya.yml': storySettings,
      'docs/Home.md': '# Home\n\nSee [[DM-12]] and [[Guide#setup]].\n',
      'docs/Guide.md': '# Guide\n\n## Setup\n\nInstall it.\n',
      'tasks/DM-12.md': storyTask('DM-12', 'Edit tasks', 'review'),
      'lib/app.dart': 'void main() {}\n',
    },
  );

  Future<FakeKit> home(WidgetTester tester, Story s) async {
    await s.setUp(tester);
    await tester.pumpWidget(s.app);
    await Story.settle(tester);
    await Story.tab(tester, 'Wiki');
    return FakeKit(tester)..ready();
  }

  testWidgets('a task reference opens its screen', (tester) async {
    final s = story();
    final kit = await home(tester, s);
    kit.follow({'kind': 'file', 'path': 'tasks/DM-12.md', 'anchor': null});
    await Story.settle(tester);
    expect(find.text('DM-12'), findsOneWidget);
    expect(find.text('Edit tasks'), findsOneWidget);
  });

  testWidgets('a page reference opens the page at its section', (tester) async {
    final s = story();
    final kit = await home(tester, s);
    kit.follow({'kind': 'file', 'path': 'docs/Guide.md', 'anchor': 'setup'});
    await Story.settle(tester);
    expect(find.text('Guide'), findsWidgets);
    expect(kit.host.document?.path, 'docs/Guide.md');
  });

  testWidgets('a missing page and a file say what they are', (tester) async {
    final s = story();
    final kit = await home(tester, s);
    kit.follow({'kind': 'missing', 'title': 'Meeting notes'});
    await Story.settle(tester);
    expect(
      find.textContaining('"Meeting notes" has no page yet'),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
