import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/storage/json_store.dart';
import 'package:genbeya_mobile/managers/parse_cache.dart';
import 'package:genbeya_mobile/managers/repository_model.dart';

import 'support/fake_git.dart';

String task(String id, {String status = 'todo', String extra = ''}) =>
    '---\nid: $id\ntitle: Task $id\nstatus: $status\n$extra---\n\nDo it.\n';

/// The sources of task parsing, by [parseCacheVersion]: task_engine.dart
/// and what it imports within lib/, transitively.
const parsedBy = (
  version: 1,
  sources: '6e857bfdce147a371dc629905f02c0b073061a7f5c963f0ab107c99c2447a298',
);

/// [start] and the files under lib/ it imports, transitively, sorted.
List<File> sourcesOf(String start) {
  final seen = <String>{};
  void visit(String path) {
    if (!seen.add(path)) return;
    final imports = RegExp(r"""^import '([^':]+)'""", multiLine: true);
    for (final m in imports.allMatches(File(path).readAsStringSync())) {
      visit(File(path).parent.uri.resolve(m.group(1)!).toFilePath());
    }
  }

  visit(File(start).absolute.path);
  return [for (final path in seen.toList()..sort()) File(path)];
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('parsed'));
  tearDown(() => tmp.deleteSync(recursive: true));

  FakeGit repository() => FakeGit()
    ..refs['HEAD'] = 'c1'
    ..commit('c1', {
      '.genbeya.yml': 'name: Demo\ntaskPrefix: DM\nfields:\n  - name: due\n    type: date\n',
      for (var i = 1; i <= 5; i++) 'tasks/DM-$i.md': task('DM-$i'),
      'tasks/Epic/DM-6.md':
          '${task('DM-6', extra: 'labels: [a, b]\ndue: 2026-12-01\nassignee: sam\n')}\n## Comments\n\n### Sam Rivera — 2026-11-21 10:00+01:00\n\nLooks good.\n',
      'tasks/DM-7.md': '---\nid: [broken\n---\n',
    })
    ..authors.add((name: 'Sam Rivera', email: 'sam@example.com', commits: 4));

  test(
    'a cold start parses nothing that was parsed before, and reads the same',
    () async {
      final store = JsonStore(File('${tmp.path}/parsed/demo.json'));
      final git = repository();
      final first = RepositoryModel(
        git,
        folderName: 'demo',
        cache: ParseCache(store),
      );
      final before = await first.load();
      await first.saved;
      expect(first.parses, 7);

      // The next app start: a new model over the same clone.
      git.blobReads = 0;
      final again = RepositoryModel(
        git,
        folderName: 'demo',
        cache: ParseCache(store),
      );
      final after = await again.load();
      expect(again.parses, 0);
      expect(git.blobReads, 1, reason: 'only the settings are read');
      expect(git.authorReads, 1, reason: 'authors come from the cache too');
      expect(
        [for (final t in after.tasks) t.toJson()],
        [for (final t in before.tasks) t.toJson()],
      );
      expect(
        [for (final p in after.problems) (p.path, p.message)],
        [for (final p in before.problems) (p.path, p.message)],
      );
      expect(after.tasks.last.fields['labels'], isNull);
      expect(after.tasks.last.labels, ['a', 'b']);
      expect(
        [for (final p in after.people) p.name],
        [for (final p in before.people) p.name],
      );
    },
  );

  test('a changed file parses again; what is gone leaves the cache', () async {
    final store = JsonStore(File('${tmp.path}/demo.json'));
    final git = repository();
    final model = RepositoryModel(
      git,
      folderName: 'demo',
      cache: ParseCache(store),
    );
    await model.load();
    git
      ..commit('c2', {
        for (final e in git.commits['c1']!.entries)
          if (e.key != 'tasks/DM-1.md') e.key: e.value,
        'tasks/DM-2.md': task('DM-2', status: 'done'),
      })
      ..refs['HEAD'] = 'c2';
    await model.load();
    await model.saved;
    final restored = await ParseCache(store).read();
    expect(restored.parsed, hasLength(6));
    expect(restored.authors?.head, 'c2');

    final cold = RepositoryModel(
      git,
      folderName: 'demo',
      cache: ParseCache(store),
    );
    final state = await cold.load();
    expect(cold.parses, 0);
    expect(state.tasks.firstWhere((t) => t.id == 'DM-2').status, 'done');
    expect(state.tasks.where((t) => t.id == 'DM-1'), isEmpty);
  });

  test('a cache of another version, or broken, is dropped', () async {
    final file = File('${tmp.path}/demo.json');
    final store = JsonStore(file);
    for (final text in [
      '{"version": ${parseCacheVersion + 1}, "files": {}}',
      '{"version": $parseCacheVersion, "files": {"x": {"odd": 1}}}',
      'not json',
    ]) {
      file.writeAsStringSync(text);
      final model = RepositoryModel(
        repository(),
        folderName: 'demo',
        cache: ParseCache(store),
      );
      expect((await model.load()).tasks, hasLength(6));
      expect(model.parses, 7);
    }
  });

  test('task parsing is the one the cache version names', () {
    final sources = sourcesOf('lib/engines/task_engine.dart');
    final hash = sha256.convert([
      for (final f in sources) ...f.readAsBytesSync(),
    ]).toString();
    expect(
      (version: parseCacheVersion, sources: hash),
      parsedBy,
      reason:
          'The task parser changed (${sources.length} files under lib/). If a file can '
          'now parse differently, bump parseCacheVersion in lib/managers/parse_cache.dart; '
          'either way, set parsedBy here to (version: $parseCacheVersion, sources: \'$hash\').',
    );
  });
}
