/// The harness of the story tests ([[GM-32]]): one clone on the phone,
/// held in memory, behind the app's real screens and managers.
///
/// - [Story.repo] holds the commits; [Story.git] writes them as the native
///   core does and plays the remote ([StoryGit]).
/// - The app's providers get the story's repositories manager (with the
///   clone registered), session and work, so screens, writers and sync run
///   unchanged.
/// - The web view isn't there in widget tests; [FakeKit] sends what the kit
///   would, through the same host the screen uses.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/git/git_remote.dart';
import 'package:genbeya_mobile/access/kit/kit_host.dart';
import 'package:genbeya_mobile/access/storage/json_store.dart';
import 'package:genbeya_mobile/access/storage/secret_store.dart';
import 'package:genbeya_mobile/contracts/clones.dart';
import 'package:genbeya_mobile/engines/content_layout.dart';
import 'package:genbeya_mobile/features/kit/kit_view.dart';
import 'package:genbeya_mobile/features/repositories/providers.dart';
import 'package:genbeya_mobile/features/repository/repository_shell.dart';
import 'package:genbeya_mobile/features/repository/session_provider.dart';
import 'package:genbeya_mobile/features/repository/work_provider.dart';
import 'package:genbeya_mobile/managers/content_writer.dart';
import 'package:genbeya_mobile/managers/repositories_manager.dart';
import 'package:genbeya_mobile/managers/repository_session.dart';
import 'package:genbeya_mobile/managers/rescues.dart';
import 'package:genbeya_mobile/managers/sync_manager.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fake_git.dart';
import '../../support/fake_remote.dart';
import 'story_git.dart';

/// Settings most stories use: a task prefix, a date field and two people.
const storySettings = '''name: Demo
taskPrefix: DM
fields:
  - name: due
    type: date
  - name: estimate
    type: effort
people:
  - handle: ada
    name: Ada Lovelace
    email: ada@example.com
  - handle: sam
    name: Sam Rivera
''';

/// A task file as desktop writes a new one.
String storyTask(
  String id,
  String title,
  String status, {
  String fields = '',
  String body = '',
}) =>
    '---\nid: $id\ntitle: $title\nstatus: $status\n$fields---\n${body.isEmpty ? '' : '\n$body'}';

class Story {
  /// [code] is the checked-out commit's files; [content], if given, is the
  /// content branch (`genbeya`), with `.genbeya-content` saying which areas
  /// it holds. Both are on the remote already. The clone signs as [name].
  Story({
    required this.code,
    this.content,
    this.name = 'Ada Lovelace',
    this.email = 'ada@example.com',
    this.commitsChosen = true,
  });

  final Map<String, String> code;
  final Map<String, String>? content;
  final String name;
  final String email;

  /// Whether the first-edit question about where commits go was answered.
  final bool commitsChosen;

  late final Directory root;
  late final FakeGit repo;
  late final StoryGit git;
  late final RepositoriesManager manager;
  late final CloneRecord record;
  late final RepositorySession session;
  late final ContentWriter writer;
  late final SyncManager sync;
  late final Rescues rescues;

  String get folder => manager.folderOf(record);

  /// Makes the clone and reads it; call first, from the test.
  Future<void> setUp(WidgetTester tester) async {
    await tester.runAsync(() async {
      root = Directory.systemTemp.createTempSync('story');
      record = CloneRecord(
        id: 'demo',
        url: 'https://github.com/acme/demo.git',
        name: 'demo',
        branch: 'main',
        credential: CredentialKind.none,
        added: DateTime.utc(2026, 11, 1),
        contentBranch: content == null ? null : 'genbeya',
        commitsChosen: commitsChosen,
      );
      File('${root.path}/repositories.json')
          .writeAsStringSync(jsonEncode([record.toJson()]));
      manager = RepositoriesManager(
        root: root,
        git: FakeRemote(),
        secrets: MemorySecretStore(),
      );
      // The checkout, on disk as the content writer finds it.
      for (final e in code.entries) {
        File('$folder/${e.key}')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(e.value);
      }
      repo = FakeGit()
        ..config['user.name'] = name
        ..config['user.email'] = email
        ..commit('c0', code)
        ..refs['HEAD'] = 'c0'
        ..refs['refs/heads/main'] = 'c0'
        ..refs['refs/remotes/origin/main'] = 'c0';
      if (content case final branch?) {
        repo
          ..commit('k0', branch)
          ..refs['refs/remotes/origin/genbeya'] = 'k0';
      }
      git = StoryGit(repo, folder);
      session = RepositorySession(
        repo,
        folderName: 'demo',
        author: name,
        remote: record.url,
        branch: 'main',
        record: record,
      );
      await session.load();
      Future<({String name, String email})> signer() async =>
          (name: name, email: email);
      writer = ContentWriter(
        dir: folder,
        git: git,
        journal: JsonStore(File('${root.path}/journal.json')),
        signer: signer,
      );
      rescues = Rescues(
        store: JsonStore(File('${root.path}/rescues.json')),
        git: git,
        objects: repo,
      );
      sync = SyncManager(
        git: git,
        objects: repo,
        writer: writer,
        rescues: rescues,
        access: () async => const RemoteAccess.none(),
        signer: signer,
        handle: () => 'ada',
      );
    });
    addTearDown(() => root.deleteSync(recursive: true));
  }

  List<Override> get overrides => [
    repositoriesManagerProvider.overrideWith((ref) async => manager),
    sessionProvider.overrideWith((ref, _) async => session),
    workProvider.overrideWith(
      (ref, _) async =>
          (writer: writer, sync: sync, git: git, rescues: rescues),
    ),
  ];

  /// The app inside the repository, as the start screen opens it.
  Widget get app => ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: RepositoryShell(record: record)),
  );

  /// A start screen with one button that runs [action], as the app does
  /// for links and shared text arriving from outside.
  Widget launcher(
    String label,
    Future<void> Function(NavigatorState navigator, WidgetRef ref) action,
  ) => ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => action(Navigator.of(context), ref),
              child: Text(label),
            ),
          ),
        ),
      ),
    ),
  );

  /// Lets the writes, reads and frames that follow a tap finish.
  static Future<void> settle(WidgetTester tester, {int rounds = 30}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Waits until [done] holds, the app working meanwhile (writes go
  /// through real files and take real time); fails after a few seconds.
  static Future<void> until(
    WidgetTester tester,
    bool Function() done, {
    String what = 'the app to finish',
  }) async {
    for (var i = 0; i < 400 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done(), isTrue, reason: 'waited for $what');
    await settle(tester, rounds: 5);
  }

  /// Waits for the commit [message] (the newest).
  Future<void> committed(WidgetTester tester, String message) => until(
    tester,
    () => git.messages.isNotEmpty && git.messages.last == message && readAgain,
    what: 'the commit "$message", read again',
  );

  /// Whether the app has read the repository since its last commit.
  bool get readAgain {
    final place = session.state!.place;
    if (place.head != repo.refs['HEAD']) return false;
    final branch = place.branch;
    return branch == null ||
        place.branchCommit ==
            (repo.refs['refs/heads/$branch'] ??
                repo.refs['refs/remotes/origin/$branch']);
  }

  /// The file as the clone has it now: from the content branch when its
  /// area lives there, else from the checked-out commit.
  String file(String path) {
    final place = session.state!.place;
    final area = contentAreaOf(
      path,
      wikiRoot: session.state!.settings.wikiRoot,
      taskRoot: session.state!.settings.taskRoot,
      pullRoot: session.state!.settings.pullRoot,
    );
    final onBranch =
        area != null &&
        place.branch != null &&
        place.areas[area] == StorageMode.branch;
    final commit = onBranch
        ? repo.refs['refs/heads/${place.branch}'] ??
              repo.refs['refs/remotes/origin/${place.branch}']
        : repo.refs['HEAD'];
    final bytes = repo.commits[commit]![path];
    if (bytes == null) throw StateError('$path is not in $commit');
    return utf8.decode(bytes);
  }

  /// Opens a tab of the bottom bar.
  static Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await settle(tester);
  }
}

/// What the kit in the web view would send, through the host of the kit
/// shown on top ([KitView.webViews] is off in widget tests).
class FakeKit {
  FakeKit(this.tester);

  final WidgetTester tester;

  KitHost get host =>
      tester.widgetList<KitView>(find.byType(KitView)).last.host;

  void _send(Map<String, Object?> message) => host.receive(jsonEncode(message));

  /// The kit started: the host sends it the document again, and answers.
  void ready() => _send({'type': 'ready', 'protocol': 1, 'genbeya': '0.2.1'});

  /// A tap on the checkbox whose list item starts at [offset] of the shown
  /// document's rendered text.
  void tick(int offset) {
    final shown = host.document!;
    _send({
      'type': 'toggle',
      'area': shown.area,
      'path': shown.path,
      'hash': shown.hash,
      'offset': offset,
    });
  }

  /// The editor's Save, with [text].
  void save(String text) {
    final edit = host.editing!;
    _send({'type': 'save', 'path': edit.path, 'hash': edit.hash, 'text': text});
  }

  /// A followed link.
  void follow(Map<String, Object?> link) =>
      _send({'type': 'follow', 'link': link});
}

/// Widget tests have no web view: the kit's place stays empty.
void withoutWebViews() => KitView.webViews = false;
