/// What the repository model parsed, kept in the app's storage across app
/// starts ([[GM-29]]): task files by blob ID and path, and the commit
/// authors by the HEAD they were read at. A cold start then reads only
/// trees and refs before the board shows; files parse again only when
/// their blob changed.
library;

import '../access/storage/json_store.dart';
import '../contracts/model.dart';
import '../engines/people_engine.dart';
import 'repository_model.dart';

/// The cache's format and the parsing it holds the results of. Bump it
/// when the task engine parses a file differently (or [Task]'s JSON
/// changes): a cache of another version is dropped. test/parse_cache_test
/// fails when task_engine.dart changes and this doesn't.
const parseCacheVersion = 1;

/// What a cache file holds.
typedef ParsedFiles = ({
  /// Parsed tasks or [FileProblem]s, by the model's key.
  Map<String, Object> parsed,

  /// Commit authors and the HEAD they were read at.
  ({String head, List<CommitAuthor> authors})? authors,
});

class ParseCache {
  ParseCache(this.store);

  final JsonStore store;

  /// What was saved, or nothing when there is no cache, it is of another
  /// version, or it can't be read.
  Future<ParsedFiles> read() async {
    const none = (parsed: <String, Object>{}, authors: null);
    try {
      final json = await store.read();
      if (json is! Map<String, Object?> ||
          json['version'] != parseCacheVersion) {
        return none;
      }
      final authors = json['authors'] as Map<String, Object?>?;
      return (
        parsed: <String, Object>{
          for (final e in (json['files']! as Map<String, Object?>).entries)
            e.key: switch (e.value! as Map<String, Object?>) {
              {'task': final Map<String, Object?> task} => Task.fromJson(task),
              {'problem': final String message, 'path': final String path} =>
                FileProblem(path, message),
              _ => throw const FormatException('Not a parsed file'),
            },
        },
        authors: authors == null
            ? null
            : (
                head: authors['head']! as String,
                authors: [
                  for (final a in authors['list']! as List)
                    (
                      name: (a as Map<String, Object?>)['name']! as String,
                      email: a['email']! as String,
                      commits: a['commits']! as int,
                    ),
                ],
              ),
      );
    } on Object {
      // A cache is only a shortcut: anything odd and it starts again.
      return none;
    }
  }

  Future<void> write(ParsedFiles files) => store.write({
    'version': parseCacheVersion,
    'files': {
      for (final e in files.parsed.entries)
        e.key: switch (e.value) {
          final Task task => {'task': task.toJson()},
          final FileProblem problem => {
            'problem': problem.message,
            'path': problem.path,
          },
          _ => throw StateError('Not a parsed file: ${e.value}'),
        },
    },
    if (files.authors case final authors?)
      'authors': {
        'head': authors.head,
        'list': [
          for (final a in authors.authors)
            {'name': a.name, 'email': a.email, 'commits': a.commits},
        ],
      },
  });
}
