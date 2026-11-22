import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/features/repository/search_screen.dart';
import 'package:genbeya_mobile/managers/repository_session.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_git.dart';

void main() {
  testWidgets('names as you type, full text below', (tester) async {
    final git = FakeGit()
      ..refs['HEAD'] = 'c1'
      ..commit('c1', {
        'docs/Board.md': '# Board\n\nHow the board works.\n',
        'tasks/DM-1.md': '---\nid: DM-1\ntitle: Fix the login\nstatus: todo\n---\n\nThe board is slow.\n',
      });
    final session = RepositorySession(git, folderName: 'demo');
    await tester.runAsync(session.load);
    await tester.pumpWidget(MaterialApp(home: SearchScreen(session: session)));

    await tester.enterText(find.byType(TextField), 'board');
    await tester.pump();
    expect(find.text('Pages'), findsOneWidget);
    expect(find.text('Board'), findsWidgets);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('In tasks'), findsOneWidget);
    expect(find.text('DM-1 Fix the login'), findsOneWidget);
    expect(
      find.textContaining('The board is slow.', findRichText: true),
      findsOneWidget,
    );
  });
}
