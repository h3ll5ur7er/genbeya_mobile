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
  Future<List<String>> changedPaths(String from, String to) async => [];

  @override
  Future<String?> configValue(String key) async => config[key];

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
