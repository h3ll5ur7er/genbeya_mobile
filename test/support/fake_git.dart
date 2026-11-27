import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:genbeya_mobile/access/git/git_objects.dart';

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
  Future<List<String>> changedPaths(String from, String to) async {
    final a = commits[from] ?? const <String, List<int>>{};
    final b = commits[to] ?? const <String, List<int>>{};
    return [
      for (final path in {...a.keys, ...b.keys})
        if (a[path] == null ||
            b[path] == null ||
            blobOf(a[path]!) != blobOf(b[path]!))
          path,
    ]..sort();
  }

  @override
  Future<String?> configValue(String key) async => config[key];

  @override
  Future<List<String>> grepFiles(
    String commit,
    String text, {
    required bool caseSensitive,
    required bool regex,
    required bool wholeWord,
  }) async => [
    for (final e in commits[commit]!.entries)
      if (utf8
          .decode(e.value, allowMalformed: true)
          .toLowerCase()
          .contains(text.toLowerCase()))
        e.key,
  ];

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
    for (final path in paths)
      path: [
        for (final (index, line)
            in utf8.decode(commits[commit]![path]!).split('\n').indexed)
          if (line.toLowerCase().contains(text.toLowerCase()))
            (
              line: index + 1,
              text: line,
              ranges: [
                (
                  start: line.toLowerCase().indexOf(text.toLowerCase()),
                  end:
                      line.toLowerCase().indexOf(text.toLowerCase()) +
                      text.length,
                ),
              ],
              isMatch: true,
            ),
      ].take(maxMatches).toList(),
  };

  /// Histories by path, for tests that need one.
  final histories = <String, List<FileRevision>>{};

  /// Whether histories end at a shallow clone's edge.
  var shallow = false;

  @override
  Future<({List<FileRevision> revisions, bool truncated})> fileHistory(
    String start,
    String path, {
    required int limit,
    required int maxBytes,
  }) async => (
    revisions: histories[path] ?? const <FileRevision>[],
    truncated: shallow,
  );

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
