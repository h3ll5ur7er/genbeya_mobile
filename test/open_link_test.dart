import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/storage/secret_store.dart';
import 'package:genbeya_mobile/contracts/clones.dart';
import 'package:genbeya_mobile/features/links/open_link.dart';
import 'package:genbeya_mobile/features/repositories/providers.dart';
import 'package:genbeya_mobile/features/repository/session_provider.dart';
import 'package:genbeya_mobile/managers/repositories_manager.dart';
import 'package:genbeya_mobile/managers/repository_session.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_git.dart';
import 'support/fake_remote.dart';

void main() {
  late Directory root;
  late RepositoriesManager manager;
  late FakeRemote remote;

  setUp(() {
    root = Directory.systemTemp.createTempSync('links');
    remote = FakeRemote();
    manager = RepositoriesManager(
      root: root,
      git: remote,
      secrets: MemorySecretStore(),
    );
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<void> open(
    WidgetTester tester,
    String link,
    RepositorySession session,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoriesManagerProvider.overrideWith((ref) async => manager),
          sessionProvider.overrideWith(
            (ref, CloneRecord record) async => session,
          ),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => openLinkText(Navigator.of(context), ref, link),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('open'));
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
  }

  RepositorySession session() => RepositorySession(
    FakeGit()
      ..refs['HEAD'] = 'c1'
      ..commit('c1', {
        'tasks/DM-1.md': '---\nid: DM-1\ntitle: One\nstatus: todo\n---\n',
      }),
    folderName: 'demo',
  );

  testWidgets('without a clone, it offers to clone the repository', (
    tester,
  ) async {
    final s = session();
    await tester.runAsync(s.load);
    await open(
      tester,
      'genbeya://open?remote=https://github.com/acme/demo.git&task=DM-1',
      s,
    );
    expect(find.text('Add a repository'), findsOneWidget);
    expect(
      find.text('To open task DM-1, clone its repository first.'),
      findsOneWidget,
    );
    expect(find.text('https://github.com/acme/demo.git'), findsOneWidget);
  });

  testWidgets('in a clone without the task, it says so', (tester) async {
    remote.branchesOf['https://github.com/acme/demo'] = ['main'];
    await tester.runAsync(
      () async =>
          manager.add(await manager.prepare('https://github.com/acme/demo')),
    );
    final s = session();
    await tester.runAsync(s.load);
    await open(
      tester,
      'genbeya://open?remote=git@github.com:acme/demo.git&task=DM-7',
      s,
    );
    expect(
      find.textContaining('has no task DM-7 on this phone'),
      findsOneWidget,
    );
  });

  testWidgets('refuses what is no Genbeya link', (tester) async {
    final s = session();
    await open(tester, 'genbeya://open?remote=/srv/repo&task=DM-1', s);
    expect(
      find.text('That is not a Genbeya link this app opens.'),
      findsOneWidget,
    );
  });

  testWidgets('a forge web link without a clone offers to clone it', (
    tester,
  ) async {
    final s = session();
    await open(
      tester,
      'https://github.com/acme/demo/blob/main/tasks/DM-1.md',
      s,
    );
    expect(
      find.text('To open this link, clone its repository first.'),
      findsOneWidget,
    );
    expect(find.text('https://github.com/acme/demo'), findsOneWidget);
  });
}
