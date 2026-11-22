import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/git/git_objects.dart';
import 'package:genbeya_mobile/engines/content_layout.dart';
import 'package:genbeya_mobile/managers/repository_model.dart';

/// Commits as maps of path to bytes; blob IDs are the content's hash.
class FakeGit implements GitObjects {
  final commits = <String, Map<String, List<int>>>{};
  final refs = <String, String>{};
  final config = <String, String>{};
  int blobReads = 0;

  String commit(String id, Map<String, Object> files) {
    commits[id] = {
      for (final e in files.entries)
        e.key: e.value is String
            ? utf8.encode(e.value as String)
            : e.value as List<int>,
    };
    return id;
  }

  static String blobOf(List<int> bytes) => sha1.convert(bytes).toString();

  @override
  Future<String?> resolveCommit(String revision) async => refs[revision];

  @override
  Future<List<GitFile>> listFiles(String commit) async => [
    for (final e in commits[commit]!.entries)
      GitFile(path: e.key, blob: blobOf(e.value), size: e.value.length),
  ];

  @override
  Future<List<Uint8List?>> readBlobs(List<String> blobs, int maxBytes) async {
    blobReads += blobs.length;
    final all = {
      for (final files in commits.values)
        for (final bytes in files.values) blobOf(bytes): bytes,
    };
    return [
      for (final blob in blobs)
        all[blob]!.length > maxBytes ? null : Uint8List.fromList(all[blob]!),
    ];
  }

  @override
  Future<Uint8List?> readFileAt(
    String commit,
    String path,
    int maxBytes,
  ) async {
    final bytes = commits[commit]![path];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<List<String>> changedPaths(String from, String to) async => [];

  @override
  Future<String?> configValue(String key) async => config[key];

  final authors = <({String name, String email, int commits})>[];
  int authorReads = 0;

  @override
  Future<List<({String name, String email, int commits})>> commitAuthors(
    int limit,
  ) async {
    authorReads++;
    return authors;
  }
}

String task(String id, {String status = 'todo', String extra = ''}) =>
    '---\nid: $id\ntitle: Task $id\nstatus: $status\n$extra---\n\nDo it.\n';

const settings = 'name: Demo\ntaskPrefix: DM\nwikiRoot: wiki\n';

void main() {
  test('reads everything from the checkout without a content branch', () async {
    final git = FakeGit()
      ..refs['HEAD'] = 'c1'
      ..commit('c1', {
        '.genbeya.yml': settings,
        'wiki/Home.md': '# Home\n',
        'wiki/Guide.md': '# Guide\n',
        'tasks/DM-1.md': task('DM-1', extra: 'assignee: Ada Lovelace\n'),
        'tasks/Epic/DM-2.md':
            '${task('DM-2')}\n## Comments\n\n### Sam Rivera — 2026-11-21 10:00+01:00\n\nLooks good.\n',
        'tasks/DM-3.md': '---\nid: [broken\n---\n',
        'tasks/DM-4.md': [0x2d, 0x00, 0x2d],
        'src/main.dart': 'void main() {}\n',
      });
    final state = await RepositoryModel(git, folderName: 'demo').load();
    expect(state.place.branch, isNull);
    expect(state.settings.name, 'Demo');
    expect(state.settingsProblem, isNull);
    expect([for (final node in state.wiki) node.title], ['Home', 'Guide']);
    expect([for (final t in state.tasks) t.id], ['DM-1', 'DM-2']);
    expect(state.tasks[1].epic, 'Epic');
    expect(
      [for (final p in state.problems) p.path],
      ['tasks/DM-3.md', 'tasks/DM-4.md'],
    );
    expect(state.problems[1].message, 'tasks/DM-4.md is a binary file.');
    expect(
      [for (final p in state.people) p.name],
      ['Ada Lovelace', 'Sam Rivera'],
    );
    expect(state.codeFiles, hasLength(8));
  });

  test('people include commit authors, and me is who Git signs as', () async {
    final git = FakeGit()
      ..refs['HEAD'] = 'c1'
      ..config['user.name'] = 'Ada'
      ..config['user.email'] = 'ada@example.com'
      ..commit('c1', {'tasks/DM-1.md': task('DM-1')});
    git.authors.addAll([
      (name: 'Ada Lovelace', email: 'ada@example.com', commits: 10),
      (name: 'Grace Hopper', email: 'grace@example.com', commits: 3),
    ]);
    final model = RepositoryModel(git, folderName: 'demo');
    final state = await model.load();
    expect([for (final p in state.people) p.handle], ['ada', 'grace']);
    expect(state.me, 'ada');
    await model.load();
    expect(git.authorReads, 1, reason: 'read again only when HEAD moves');
    git.config.remove('user.email');
    git.config['user.name'] = 'Someone Else';
    expect((await model.load()).me, isNull);
  });

  test('a content branch without .genbeya-content holds every area', () async {
    final git = FakeGit()
      ..refs['HEAD'] = 'code'
      ..refs['refs/remotes/origin/genbeya'] = 'content'
      ..commit('code', {'tasks/DM-1.md': task('DM-1'), 'README.md': 'code'})
      ..commit('content', {
        '.genbeya.yml': settings,
        'tasks/DM-9.md': task('DM-9'),
        'wiki/Home.md': '# Home\n',
      });
    final state = await RepositoryModel(git, folderName: 'demo').load();
    expect(state.place.branch, 'genbeya');
    expect(state.place.areas, everyArea(StorageMode.branch));
    expect([for (final t in state.tasks) t.id], ['DM-9']);
    expect(state.settings.taskPrefix, 'DM');
    expect(
      [for (final f in state.codeFiles) f.path],
      ['tasks/DM-1.md', 'README.md'],
    );
  });

  test('.genbeya-content splits the areas; the local branch wins', () async {
    final git = FakeGit()
      ..refs['HEAD'] = 'code'
      ..refs['refs/heads/genbeya'] = 'local'
      ..refs['refs/remotes/origin/genbeya'] = 'remote'
      ..commit('code', {
        '.genbeya.yml': settings,
        'wiki/Code.md': '# Code\n',
        'tasks/DM-1.md': task('DM-1'),
      })
      ..commit('local', {
        '.genbeya-content': '[areas]\n\ttasks = branch\n\twiki = checkout\n',
        'tasks/DM-2.md': task('DM-2'),
        'wiki/Branch.md': '# Branch\n',
      })
      ..commit('remote', {'tasks/DM-3.md': task('DM-3')});
    final state = await RepositoryModel(git, folderName: 'demo').load();
    expect(state.place.branchCommit, 'local');
    expect([for (final t in state.tasks) t.id], ['DM-2']);
    expect([for (final node in state.wiki) node.title], ['Code']);
    expect(
      state.settings.name,
      'Demo',
      reason: 'settings stay in the checkout',
    );
  });

  test('genbeya.storage worktree keeps everything in the checkout', () async {
    final git = FakeGit()
      ..refs['HEAD'] = 'code'
      ..refs['refs/heads/notes'] = 'content'
      ..config['genbeya.branch'] = 'notes'
      ..commit('code', {'tasks/DM-1.md': task('DM-1')})
      ..commit('content', {'tasks/DM-2.md': task('DM-2')});
    final model = RepositoryModel(git, folderName: 'demo');
    expect((await model.locate()).branch, 'notes');
    git.config['genbeya.storage'] = 'worktree';
    final state = await model.load();
    expect(state.place.branch, isNull);
    expect([for (final t in state.tasks) t.id], ['DM-1']);
  });

  test(
    'parses a blob once, and after a change only the changed file',
    () async {
      final git = FakeGit()
        ..refs['HEAD'] = 'c1'
        ..commit('c1', {
          for (var i = 1; i <= 20; i++) 'tasks/DM-$i.md': task('DM-$i'),
        });
      final model = RepositoryModel(git, folderName: 'demo');
      await model.load();
      expect(model.parses, 20);
      await model.load();
      expect(model.parses, 20, reason: 'nothing changed');
      git
        ..commit('c2', {
          ...{for (final e in git.commits['c1']!.entries) e.key: e.value},
          'tasks/DM-5.md': task('DM-5', status: 'done'),
        })
        ..refs['HEAD'] = 'c2';
      final state = await model.load();
      expect(model.parses, 21);
      expect(state.tasks.firstWhere((t) => t.id == 'DM-5').status, 'done');
    },
  );

  test('invalid settings fall back to the defaults, with the reason', () async {
    final git = FakeGit()
      ..refs['HEAD'] = 'c1'
      ..commit('c1', {
        '.genbeya.yml': 'statuses: [a, a]\n',
        'tasks/DM-1.md': task('DM-1'),
      });
    final state = await RepositoryModel(git, folderName: 'my-repo').load();
    expect(state.settingsProblem, isNotNull);
    expect(state.settings.name, 'my-repo');
  });

  test(
    "a task's hash is Genbeya's: SHA-256 of its text, byte order mark kept",
    () async {
      final text = '﻿${task('DM-1')}';
      final git = FakeGit()
        ..refs['HEAD'] = 'c1'
        ..commit('c1', {'tasks/DM-1.md': utf8.encode(text)});
      final state = await RepositoryModel(git, folderName: 'demo').load();
      expect(
        state.tasks.single.hash,
        sha256.convert(utf8.encode(text)).toString(),
      );
      expect(
        fileHash('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        decodeText(Uint8List.fromList([0xef, 0xbb, 0xbf, 0x61]), 'x'),
        '﻿a',
      );
      expect(
        () => decodeText(Uint8List.fromList([0xff]), 'x'),
        throwsFormatException,
      );
    },
  );
}
