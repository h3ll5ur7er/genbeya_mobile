import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/contracts/clones.dart';
import 'package:genbeya_mobile/features/repositories/providers.dart';
import 'package:genbeya_mobile/features/repository/today_screen.dart';
import 'package:genbeya_mobile/managers/repository_session.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_git.dart';

void main() {
  final record = CloneRecord(
    id: 'demo',
    url: 'https://example.com/demo.git',
    name: 'demo',
    branch: 'main',
    credential: CredentialKind.none,
    added: DateTime.utc(2026),
  );

  Future<RepositorySession> session(WidgetTester tester, String name) async {
    final git = FakeGit()
      ..refs['HEAD'] = 'c1'
      ..config['user.name'] = name
      ..commit('c1', {
        '.genbeya.yml':
            'name: Demo\npeople:\n  - handle: ada\n    name: Ada Lovelace\n',
        'tasks/DM-1.md': '---\nid: DM-1\ntitle: Write the plan\nstatus: in-progress\nassignee: ada\n---\n\n- [ ] Send it 2020-01-01\n',
      });
    final s = RepositorySession(git, folderName: 'demo', record: record);
    await tester.runAsync(s.load);
    return s;
  }

  Widget app(RepositorySession s) => ProviderScope(
    overrides: [
      repositoriesManagerProvider.overrideWith(
        (ref) => Future.error(StateError('no storage in tests')),
      ),
    ],
    child: MaterialApp(
      home: TodayScreen(session: s, record: record),
    ),
  );

  testWidgets('my tasks and an overdue checklist item', (tester) async {
    final s = await session(tester, 'Ada Lovelace');
    await tester.pumpWidget(app(s));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.text('For Ada Lovelace (@ada)'), findsOneWidget);
    expect(find.text('My tasks · 1'), findsOneWidget);
    expect(find.text('Write the plan'), findsOneWidget);
    expect(find.text('Checklist · 1'), findsOneWidget);
    expect(find.text('Send it 2020-01-01'), findsOneWidget);
  });

  testWidgets('an identity that matches no one explains how "me" is found', (
    tester,
  ) async {
    final s = await session(tester, 'Someone Else');
    await tester.pumpWidget(app(s));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.text('Who are you here?'), findsOneWidget);
    expect(find.text('Set my name and email'), findsOneWidget);
  });

  testWidgets('Today is worked out again when its tab is shown', (
    tester,
  ) async {
    final s = await session(tester, 'Ada Lovelace');
    Widget shown(bool active) => ProviderScope(
      overrides: [
        repositoriesManagerProvider.overrideWith(
          (ref) => Future.error(StateError('no storage in tests')),
        ),
      ],
      child: MaterialApp(
        home: TodayScreen(session: s, record: record, active: active),
      ),
    );
    await tester.pumpWidget(shown(true));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.text('Checklist · 1'), findsOneWidget);
    // The model changes without a published reload (as when another screen read it).
    final git = s.git as FakeGit;
    git
      ..commit('c2', {
        ...{for (final e in git.commits['c1']!.entries) e.key: e.value},
        'tasks/DM-1.md': '---\nid: DM-1\ntitle: Write the plan\nstatus: in-progress\nassignee: ada\n---\n\n- [x] Send it 2020-01-01\n',
      })
      ..refs['HEAD'] = 'c2';
    await tester.runAsync(s.model.load);
    await tester.pumpWidget(shown(false));
    await tester.pumpWidget(shown(true));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.textContaining('Checklist'), findsNothing);
  });
}
