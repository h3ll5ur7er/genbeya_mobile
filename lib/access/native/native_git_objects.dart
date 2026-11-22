import 'dart:typed_data';

import '../../src/rust/api/git.dart' as core;
import '../../src/rust/git.dart' as core;
import '../git/git_objects.dart';

/// [GitObjects] of a clone, through the Rust core.
class NativeGitObjects implements GitObjects {
  NativeGitObjects(this.dir);

  /// The clone's folder.
  final String dir;

  @override
  Future<String?> resolveCommit(String revision) =>
      core.resolveCommit(dir: dir, revision: revision);

  @override
  Future<List<GitFile>> listFiles(String commit) async => [
    for (final file in await core.listFiles(dir: dir, commit: commit))
      GitFile(
        path: file.path,
        blob: file.blob,
        size: file.size.toInt(),
        link: file.link,
      ),
  ];

  @override
  Future<List<Uint8List?>> readBlobs(List<String> blobs, int maxBytes) =>
      core.readBlobs(dir: dir, blobs: blobs, maxBytes: BigInt.from(maxBytes));

  @override
  Future<Uint8List?> readFileAt(String commit, String path, int maxBytes) =>
      core.readFileAt(
        dir: dir,
        commit: commit,
        path: path,
        maxBytes: BigInt.from(maxBytes),
      );

  @override
  Future<List<String>> changedPaths(String from, String to) =>
      core.changedPaths(dir: dir, from: from, to: to);

  @override
  Future<List<({String name, String email, int commits})>> commitAuthors(
    int limit,
  ) async => [
    for (final author in await core.commitAuthors(dir: dir, limit: limit))
      (name: author.name, email: author.email, commits: author.commits),
  ];

  @override
  Future<({List<FileRevision> revisions, bool truncated})> fileHistory(
    String start,
    String path, {
    required int limit,
    required int maxBytes,
  }) async {
    final history = await core.fileHistory(
      dir: dir,
      start: start,
      path: path,
      limit: limit,
      maxBytes: BigInt.from(maxBytes),
    );
    return (
      revisions: [
        for (final r in history.revisions)
          FileRevision(
            commit: r.commit,
            author: r.author,
            time: r.time.toInt(),
            subject: r.subject,
            path: r.path,
            oldPath: r.oldPath,
            before: r.before,
            after: r.after,
          ),
      ],
      truncated: history.truncated,
    );
  }

  core.GrepQuery _query(
    String text,
    bool caseSensitive,
    bool regex,
    bool wholeWord,
  ) => core.GrepQuery(
    text: text,
    caseSensitive: caseSensitive,
    regex: regex,
    wholeWord: wholeWord,
  );

  @override
  Future<List<String>> grepFiles(
    String commit,
    String text, {
    required bool caseSensitive,
    required bool regex,
    required bool wholeWord,
  }) => core.grepFiles(
    dir: dir,
    commit: commit,
    query: _query(text, caseSensitive, regex, wholeWord),
  );

  @override
  Future<Map<String, List<GrepLine>>> grepLines(
    String commit,
    List<String> paths,
    String text, {
    required bool caseSensitive,
    required bool regex,
    required bool wholeWord,
    required int maxMatches,
  }) async => {
    for (final file in await core.grepLines(
      dir: dir,
      commit: commit,
      paths: paths,
      query: _query(text, caseSensitive, regex, wholeWord),
      maxMatches: maxMatches,
    ))
      file.path: [
        for (final line in file.lines)
          (
            line: line.line,
            text: line.text,
            ranges: [for (final r in line.ranges) (start: r.start, end: r.end)],
            isMatch: line.isMatch,
          ),
      ],
  };

  @override
  Future<String?> configValue(String key) =>
      core.configValue(dir: dir, key: key);
}
