// US-26 · Look around a repository I don't trust ([[User stories#us-26-look-around-a-repository-i-dont-trust]]).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/story.dart';

void main() {
  withoutWebViews();

  testWidgets(
    "a page can't send the app anywhere but the web, nor write but where it shows",
    (tester) async {
      final s = Story(
        code: {
          '.genbeya.yml': storySettings,
          'docs/Home.md': '# Home\n\n- [ ] Box\n',
        },
      );
      await s.setUp(tester);
      await tester.pumpWidget(s.app);
      await Story.settle(tester);
      await Story.tab(tester, 'Wiki');
      final kit = FakeKit(tester)..ready();

      // Links that would leave the repository or run something.
      kit
        ..follow({'kind': 'external', 'url': 'javascript:alert(1)'})
        ..follow({'kind': 'external', 'url': 'file:///etc/passwd'})
        ..follow({'kind': 'file', 'path': '../../etc/passwd', 'anchor': null})
        ..follow({'kind': 'file', 'path': '.git/config', 'anchor': null});
      // A checkbox in a version the page doesn't show.
      kit.host.receive(
        '{"type":"toggle","area":"wiki","path":"docs/Home.md","hash":"forged","offset":8}',
      );
      // A checkbox in another file.
      kit.host.receive(
        '{"type":"toggle","area":"settings","path":".genbeya.yml","hash":"x","offset":0}',
      );
      await Story.settle(tester);

      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Home'), findsWidgets, reason: 'still on the page');
      expect(s.git.messages, isEmpty, reason: 'nothing was written');
    },
  );
}
