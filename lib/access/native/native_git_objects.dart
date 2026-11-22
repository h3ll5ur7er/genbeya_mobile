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
  Future<String?> configValue(String key) =>
      core.configValue(dir: dir, key: key);
}
