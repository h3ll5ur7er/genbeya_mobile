import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/storage/json_store.dart';
import 'package:genbeya_mobile/contracts/clones.dart';
import 'package:genbeya_mobile/features/kit/kit_view.dart';
import 'package:genbeya_mobile/features/repositories/providers.dart';
import 'package:genbeya_mobile/features/repository/task_view_screen.dart';
import 'package:genbeya_mobile/features/tasks/task_editing.dart';
import 'package:genbeya_mobile/features/tasks/tasks_screen.dart';
import 'package:genbeya_mobile/managers/content_writer.dart';
import 'package:genbeya_mobile/managers/repository_session.dart';
import 'package:genbeya_mobile/managers/task_writer.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_git.dart';
import 'support/fake_writer.dart';

void main() {
  KitView.webViews = false;
  final record = CloneRecord(
    id: 'demo',
    url: 'https://example.com/demo.git',
    name: 'demo',
    branch: 'main',
    credential: CredentialKind.none,
    added: DateTime.utc(2026),
  );
  late FakeGit repo;
  late FakeWriter git;
  late RepositorySession session;
  late TaskWriter writer;

  String fileOf(String path) => String.fromCharCodes(
    repo.commits[repo.refs['refs/heads/genbeya']]![path]!,
  );

  Future<void> setUpRepository(WidgetTester tester) async {
    repo = FakeGit()
      ..refs['HEAD'] = 'code'
      ..refs['refs/remotes/origin/genbeya'] = 'content'
      ..commit('code', {'.genbeya.yml': 'name: Demo\ntaskPrefix: DM\n'})
      ..commit('content', {
        '.genbeya-content': '[areas]\n\ttasks = branch\n',
        'tasks/DM-1.md': '---\nid: DM-1\ntitle: Write the plan\nstatus: todo\n---\n\nDo it.\n',
      });
    git = FakeWriter(repo);
    session = RepositorySession(repo, folderName: 'demo', record: record);
    await tester.runAsync(session.load);
    writer = TaskWriter(
      session: session,
      writer: ContentWriter(
        dir: Directory.systemTemp.path,
        git: git,
        journal: JsonStore(File('${Directory.systemTemp.path}/unused.json')),
        signer: () async => (name: 'Ada', email: 'ada@example.com'),
      ),
    );
  }

  /// Sheets and saves, without waiting for spinners that never stop.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Widget app(Widget home) => ProviderScope(
    overrides: [
      taskWriterProvider.overrideWith((ref, _) async => writer),
      repositoriesManagerProvider.overrideWith(
        (ref) => Future.error(StateError('no storage in tests')),
      ),
    ],
    child: MaterialApp(home: home),
  );

  testWidgets('a long press moves a task to another state', (tester) async {
    await setUpRepository(tester);
    await tester.pumpWidget(app(TasksScreen(session: session, record: record)));
    await tester.pumpAndSettle();
    expect(find.text('Todo · 1'), findsOneWidget);

    await tester.longPress(find.text('Write the plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done').last);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(git.messages, ['Update DM-1: Write the plan']);
    expect(fileOf('tasks/DM-1.md'), contains('status: done\n'));
    expect(find.text('Done · 1'), findsOneWidget);
  });

  testWidgets('the task screen changes a property from its sheet', (
    tester,
  ) async {
    await setUpRepository(tester);
    final task = session.state!.tasks.single;
    await tester.pumpWidget(app(TaskViewScreen(session: session, task: task)));
    await settle(tester);

    await tester.tap(find.text('Priority'));
    await settle(tester);
    await tester.tap(find.text('High'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await settle(tester);

    expect(fileOf('tasks/DM-1.md'), contains('priority: high\n'));
    expect(find.text('High'), findsOneWidget);
  });
}
