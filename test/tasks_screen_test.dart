import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/features/tasks/tasks_screen.dart';
import 'package:genbeya_mobile/managers/repository_session.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_git.dart';

String task(String id, String title, String status, [String extra = '']) =>
    '---\nid: $id\ntitle: $title\nstatus: $status\n$extra---\n';

void main() {
  testWidgets('the list by state, filters, and the board', (tester) async {
    final git = FakeGit()
      ..refs['HEAD'] = 'c1'
      ..commit('c1', {
        '.genbeya.yml': 'name: Demo\nhiddenColumns: [backlog]\n',
        'tasks/DM-1.md': task('DM-1', 'Write the plan', 'todo', 'type: docs\n'),
        'tasks/DM-2.md': task(
          'DM-2',
          'Fix the login',
          'in-progress',
          'type: bug\npriority: urgent\n',
        ),
        'tasks/DM-3.md': task('DM-3', 'Ship it', 'done'),
        'tasks/DM-4.md': task('DM-4', 'Someday', 'backlog'),
      });
    final session = RepositorySession(git, folderName: 'demo');
    await tester.runAsync(session.load);
    await tester.pumpWidget(MaterialApp(home: TasksScreen(session: session)));
    await tester.pumpAndSettle();

    expect(find.text('Todo · 1'), findsOneWidget);
    expect(find.text('In progress · 1'), findsOneWidget);
    expect(
      find.text('Backlog · 1'),
      findsOneWidget,
      reason: 'the list shows every state',
    );
    expect(find.text('Fix the login'), findsOneWidget);

    await tester.tap(find.text('Type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bug').last);
    await tester.pumpAndSettle();
    expect(find.text('Fix the login'), findsOneWidget);
    expect(find.text('Write the plan'), findsNothing);
    expect(find.text('Type: Bug'), findsOneWidget);

    await tester.tap(find.byTooltip('Board'));
    await tester.pumpAndSettle();
    expect(
      find.text('Backlog 0'),
      findsNothing,
      reason: 'hidden columns stay off the board',
    );
    expect(find.text('Todo 0'), findsOneWidget);
    expect(find.text('In progress 1'), findsOneWidget);
  });
}
