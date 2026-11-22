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

/// A commit that changed a file, with the file before and after.
class FileRevision {
  const FileRevision({
    required this.commit,
    required this.author,
    required this.time,
    required this.subject,
    required this.path,
    required this.oldPath,
    required this.before,
    required this.after,
  });

  final String commit;
  final String author;

  /// Seconds since 1970.
  final int time;
  final String subject;
  final String path;

  /// Null when this commit created the file.
  final String? oldPath;

  /// Null where there is none, or it was larger than the limit.
  final Uint8List? before;
  final Uint8List? after;
}

/// A line of a file found by search: a match with its ranges, or a line
/// next to one.
typedef GrepLine = ({
  int line,
  String text,
  List<({int start, int end})> ranges,
  bool isMatch,
});

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

  /// The files of [commit] with a match, as `git grep -l` lists them.
  Future<List<String>> grepFiles(
    String commit,
    String text, {
    required bool caseSensitive,
    required bool regex,
    required bool wholeWord,
  });

  /// The matching lines of [paths] in [commit], with the lines around them.
  Future<Map<String, List<GrepLine>>> grepLines(
    String commit,
    List<String> paths,
    String text, {
    required bool caseSensitive,
    required bool regex,
    required bool wholeWord,
    required int maxMatches,
  });

  /// The newest [limit] commits from [start] that changed [path], following
  /// renames, without merges; `truncated` when a shallow clone ends first.
  Future<({List<FileRevision> revisions, bool truncated})> fileHistory(
    String start,
    String path, {
    required int limit,
    required int maxBytes,
  });

  /// The authors of HEAD's newest [limit] commits as .mailmap names them,
  /// with how many each wrote.
  Future<List<({String name, String email, int commits})>> commitAuthors(
    int limit,
  );
}
