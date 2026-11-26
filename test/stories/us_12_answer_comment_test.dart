// US-12 · Answer a comment ([[User stories#us-12-answer-a-comment]]).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/story.dart';

void main() {
  withoutWebViews();

  Story story() => Story(
    code: {
      '.genbeya.yml': storySettings,
      'docs/Release.md': '# Release\n',
      'tasks/DM-1.md': storyTask(
        'DM-1',
        'Write the plan',
        'todo',
        body: 'Text.\n\n## Comments\n\n### Sam Rivera — 2026-11-25 09:00+01:00\n\nWhen is it ready, @ada?\n',
      ),
    },
  );

  testWidgets(
    'a reply with @, [[ and //, signed and last; only my own can change',
    (tester) async {
      final s = story();
      await s.setUp(tester);
      await tester.pumpWidget(s.app);
      await Story.settle(tester);
      await Story.tab(tester, 'Tasks');
      await tester.tap(find.text('Write the plan'));
      await Story.settle(tester);
      expect(
        find.byTooltip('Edit or delete'),
        findsNothing,
        reason: "Sam's comment isn't mine",
      );

      final field = find.byType(TextField).last;
      await tester.tap(field);
      await tester.enterText(field, '@sa');
      await Story.settle(tester);
      await tester.tap(find.text('Sam Rivera'));
      await Story.settle(tester);
      await tester.enterText(
        field,
        '${tester.widget<TextField>(field).controller!.text}see [[Rel',
      );
      await Story.settle(tester);
      await tester.tap(find.text('Release'));
      await Story.settle(tester);
      await tester.enterText(
        field,
        '${tester.widget<TextField>(field).controller!.text} by //tomorrow',
      );
      await Story.settle(tester);
      await tester.tap(find.text('Tomorrow'));
      await Story.settle(tester);
      final text = tester.widget<TextField>(field).controller!.text;
      expect(text, matches(r'^@sam see \[\[Release\]\] by \d{4}-\d{2}-\d{2}$'));

      await tester.tap(find.byTooltip('Send'));
      await s.committed(tester, 'Comment on DM-1');
      final file = s.file('tasks/DM-1.md');
      expect(
        file,
        matches(
          RegExp(
            r'### Sam Rivera — 2026-11-25 09:00\+01:00\n\nWhen is it ready, @ada\?\n\n'
            r'### Ada Lovelace — \d{4}-\d{2}-\d{2} \d{2}:\d{2}[+-]\d{2}:\d{2}\n\n'
            '${RegExp.escape(text)}\n\$',
          ),
        ),
      );

      await tester.tap(find.byTooltip('Edit or delete'));
      await Story.settle(tester);
      await tester.tap(find.text('Delete'));
      await Story.settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await s.committed(tester, 'Delete a comment on DM-1');
      expect(s.file('tasks/DM-1.md'), isNot(contains('Ada Lovelace —')));
      expect(s.file('tasks/DM-1.md'), contains('When is it ready, @ada?'));
    },
  );
}
