import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/engines/search_engine.dart';
import 'package:genbeya_mobile/managers/repository_session.dart';
import 'package:genbeya_mobile/managers/search.dart';

import 'support/fake_git.dart';

void main() {
  test('fuzzy score: substrings first, earlier and at word starts higher', () {
    expect(fuzzyScore('Architecture', 'xyz'), -1);
    expect(
      fuzzyScore('Board', 'board'),
      greaterThan(fuzzyScore('Onboarding', 'board')),
    );
    expect(
      fuzzyScore('docs/Board.md', 'board'),
      greaterThan(fuzzyScore('docs/xBoard.md', 'board')),
    );
    expect(
      fuzzyScore('Architecture', 'arch'),
      greaterThan(fuzzyScore('Architecture', 'atr')),
    );
    expect(fuzzyScore('Architecture', 'atr'), greaterThanOrEqualTo(0));
  });

  FakeGit repository() => FakeGit()
    ..refs['HEAD'] = 'code'
    ..refs['refs/remotes/origin/genbeya'] = 'content'
    ..commit('code', {
      'src/board.dart': '// the board\nvoid main() {}\n',
      // A stale copy in the checkout of an area that lives on the branch.
      'tasks/DM-9.md': '---\nid: DM-9\ntitle: Old board\nstatus: todo\n---\n',
    })
    ..commit('content', {
      '.genbeya-content': '[areas]\n\twiki = branch\n\ttasks = branch\n',
      'docs/Board.md': '# Board\n\nHow the board works.\n',
      'tasks/DM-1.md': '---\nid: DM-1\ntitle: Fix the board\nstatus: todo\n---\n\nThe board is slow.\n',
    });

  test('names: pages, tasks and files that match, best first', () async {
    final session = RepositorySession(repository(), folderName: 'demo');
    final state = await session.load();
    final names = searchNames(state, 'board');
    expect(
      [for (final n in names) '${n.kind.name} ${n.title}'],
      ['page Board', 'task DM-1 Fix the board', 'file board.dart'],
    );
    expect(searchNames(state, ' '), isEmpty);
  });

  test('full text: each file from where its area lives', () async {
    final session = RepositorySession(repository(), folderName: 'demo');
    await session.load();
    final results = await session.search(SearchEngine().validate('board'));
    expect([for (final h in results.wiki) h.title], ['Board']);
    expect(
      [for (final h in results.tasks) h.title],
      ['DM-1 Fix the board'],
      reason: 'not the stale copy',
    );
    expect([for (final h in results.code) h.path], ['src/board.dart']);
    final line = results.tasks.single.matches.last;
    expect(line.line, 7);
    expect(line.ranges, [(start: 4, end: 9)]);
    expect(results.truncated, isFalse);
    expect(
      () => SearchEngine().validate('  '),
      throwsA(isA<SearchException>()),
    );
  });
}
