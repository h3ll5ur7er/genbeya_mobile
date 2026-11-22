/// What the repository model reads from Git: commits, their trees and blobs.
/// The native core implements it ([NativeGitObjects]); tests use a fake.
library;

import 'dart:typed_data';

/// A file of a commit's tree.
class GitFile {
  const GitFile({
    required this.path,
    required this.blob,
    required this.size,
    this.link = false,
  });

  final String path;

  /// The blob's ID: the same content always has the same ID.
  final String blob;
  final int size;

  /// A symbolic link, whose blob is its target.
  final bool link;
}

abstract interface class GitObjects {
  /// The commit [revision] names, or null.
  Future<String?> resolveCommit(String revision);

  /// Every file of [commit]'s tree.
  Future<List<GitFile>> listFiles(String commit);

  /// Each blob's bytes, or null when it is larger than [maxBytes].
  Future<List<Uint8List?>> readBlobs(List<String> blobs, int maxBytes);

  /// [path] as committed in [commit], or null when it has no such file.
  Future<Uint8List?> readFileAt(String commit, String path, int maxBytes);

  /// The paths that differ between two commits.
  Future<List<String>> changedPaths(String from, String to);

  /// A value of the repository's Git configuration.
  Future<String?> configValue(String key);

  /// The authors of HEAD's newest [limit] commits as .mailmap names them,
  /// with how many each wrote.
  Future<List<({String name, String email, int commits})>> commitAuthors(
    int limit,
  );
}
