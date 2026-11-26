import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/storage/json_store.dart';
import 'package:genbeya_mobile/contracts/clones.dart';
import 'package:genbeya_mobile/features/repositories/providers.dart';
import 'package:genbeya_mobile/features/repository/today_screen.dart';
import 'package:genbeya_mobile/managers/content_writer.dart';
import 'package:genbeya_mobile/managers/repository_session.dart';
import 'package:genbeya_mobile/managers/task_writer.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_git.dart';
import 'support/fake_writer.dart';

void main() {
  final record = CloneRecord(
    id: 'demo',
    url: 'https://example.com/demo.git',
    name: 'demo',
    branch: 'main',
    credential: CredentialKind.none,
    added: DateTime.utc(2026),
  );

  testWidgets('Today follows an edit made while it is open', (tester) async {
    final repo = FakeGit()
      ..refs['HEAD'] = 'code'
      ..refs['refs/remotes/origin/genbeya'] = 'content'
      ..config['user.name'] = 'Ada Lovelace'
      ..commit('code', {
        '.genbeya.yml': 'name: Demo\ntaskPrefix: DM\npeople:\n  - handle: ada\n    name: Ada Lovelace\n',
      })
      ..commit('content', {
        '.genbeya-content': '[areas]\n\ttasks = branch\n',
        'tasks/DM-1.md': '---\nid: DM-1\ntitle: Plan\nstatus: todo\n---\n',
      });
    final session = RepositorySession(
      repo,
      folderName: 'demo',
      record: record,
      author: 'Ada Lovelace',
    );
    await tester.runAsync(session.load);
    final tasks = TaskWriter(
      session: session,
      writer: ContentWriter(
        dir: Directory.systemTemp.path,
        git: FakeWriter(repo),
        journal: JsonStore(File('${Directory.systemTemp.path}/unused.json')),
        signer: () async => (name: 'Ada', email: ''),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoriesManagerProvider.overrideWith(
            (ref) => Future.error(StateError('no storage in tests')),
          ),
        ],
        child: MaterialApp(
          home: TodayScreen(session: session, record: record),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    // As the screens do it: in the app's zone, the frames going on.
    Future<void> edit(Future<Object?> change) async {
      var done = false;
      change.whenComplete(() => done = true).ignore();
      for (var i = 0; i < 50 && !done; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(done, isTrue, reason: 'the edit finished');
    }

    await settle();
    expect(find.textContaining('My tasks'), findsNothing);

    var task = session.state!.tasks.single;
    await tester.pumpAndSettle();
    await edit(tasks.update(task, task.toInput().copyWith(assignee: 'ada')));
    await settle();
    expect(find.text('My tasks · 1'), findsOneWidget);

    task = session.state!.tasks.single;
    await edit(
      tasks.update(
        task,
        task.toInput().copyWith(body: '- [ ] Send it 2026-11-25\n'),
      ),
    );
    await settle();
    expect(find.text('Checklist · 1'), findsOneWidget);
  });
}
