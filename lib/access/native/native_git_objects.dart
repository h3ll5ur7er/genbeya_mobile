import 'dart:typed_data';

import '../../src/rust/api/git.dart' as core;
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

  @override
  Future<String?> configValue(String key) =>
      core.configValue(dir: dir, key: key);
}
