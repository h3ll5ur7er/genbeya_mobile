/// Search in an open repository: names first, ranked as desktop's palette
/// ranks them (`fuzzy.ts`), then full text grouped into Wiki, Tasks, Code
/// and Pull requests (`content-search.ts`) ([[Experience#search]]).
library;

import '../contracts/model.dart';
import '../engines/search_engine.dart';
import 'repository_model.dart';
import 'task_views.dart';

/// How well [query] matches [text]: substring matches rank above scattered
/// ones, earlier and word-start matches higher; -1 is no match.
double fuzzyScore(String text, String query) {
  final haystack = text.toLowerCase();
  final needle = query.toLowerCase();
  final at = haystack.indexOf(needle);
  if (at >= 0) {
    final wordStart = at == 0 || RegExp(r'[\s/_-]').hasMatch(haystack[at - 1]);
    return 1000 -
        at * 2 -
        (haystack.length - needle.length) * 0.1 +
        (wordStart ? 50 : 0);
  }
  var matched = 0;
  var gaps = 0;
  for (final character in haystack.split('')) {
    if (matched < needle.length && character == needle[matched]) {
      matched++;
    } else if (matched > 0) {
      gaps++;
    }
    if (matched == needle.length) return 400.0 - gaps;
  }
  return -1;
}

enum SearchKind { page, task, file }

/// A page, task or file whose name matches.
typedef NameHit = ({
  SearchKind kind,
  String path,
  String title,
  String detail,
  double score,
});

/// Names that match [query], best first, at most [limit] of each kind.
List<NameHit> searchNames(
  RepositoryState state,
  String query, {
  int limit = 8,
}) {
  if (query.trim().isEmpty) return const [];
  List<NameHit> best(Iterable<NameHit> hits) {
    final list = hits.where((hit) => hit.score >= 0).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return list.take(limit).toList();
  }

  List<WikiNode> flat(List<WikiNode> nodes) => [
    for (final node in nodes) ...[node, ...flat(node.children)],
  ];
  final text = query.trim();
  return [
    ...best([
      for (final node in flat(state.wiki))
        if (node.path != null)
          (
            kind: SearchKind.page,
            path: node.path!,
            title: node.title,
            detail: node.path!,
            score: fuzzyScore(node.title, text),
          ),
    ]),
    ...best([
      for (final task in state.tasks)
        (
          kind: SearchKind.task,
          path: task.path,
          title: '${displayId(task.id)} ${task.title}',
          detail: titleCase(task.status),
          score: fuzzyScore('${task.id} ${task.title}', text),
        ),
    ]),
    ...best([
      for (final file in state.codeFiles)
        (
          kind: SearchKind.file,
          path: file.path,
          title: file.path.split('/').last,
          detail: file.path,
          score: fuzzyScore(file.path, text),
        ),
    ]),
  ];
}

/// A matching line with the lines around it, shortened as shown.
typedef SearchMatch = ({
  int line,
  String text,
  List<SearchRange> ranges,
  String? before,
  String? after,
});

/// A file with matches: its title (page title, task ID and title, path).
typedef ContentHit = ({
  String path,
  String title,
  String detail,
  List<SearchMatch> matches,
});

typedef ContentResults = ({
  List<ContentHit> wiki,
  List<ContentHit> tasks,
  List<ContentHit> code,
  List<ContentHit> pulls,
  bool truncated,
});
