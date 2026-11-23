import 'dart:typed_data';

import 'package:genbeya_mobile/access/git/git_writer.dart';

import 'fake_git.dart';

/// Commits onto [FakeGit]'s branches; the checkout's files are committed
/// from [worktree], which tests fill as the content writer's files would be.
class FakeWriter implements GitWriter {
  FakeWriter(this.repo);

  final FakeGit repo;
  final messages = <String>[];
  var _n = 0;

  String _commit(
    String? parent,
    Map<String, Uint8List?> files,
    String message,
  ) {
    final next = {...?repo.commits[parent]};
    for (final e in files.entries) {
      if (e.value == null) {
        next.remove(e.key);
      } else {
        next[e.key] = e.value!;
      }
    }
    final id = 'c${++_n}';
    repo.commits[id] = next;
    messages.add(message);
    return id;
  }

  @override
  Future<String> commitOntoBranch(
    String branch,
    Map<String, Uint8List?> files,
    String message,
    Signer signer,
  ) async {
    final parent =
        repo.refs['refs/heads/$branch'] ??
        repo.refs['refs/remotes/origin/$branch'];
    return repo.refs['refs/heads/$branch'] = _commit(parent, files, message);
  }

  /// The checkout's files as the content writer left them.
  final worktree = <String, Uint8List?>{};

  @override
  Future<String> commitFiles(
    List<String> paths,
    String message,
    Signer signer,
  ) async => repo.refs['HEAD'] = _commit(repo.refs['HEAD'], {
    for (final path in paths) path: worktree[path],
  }, message);

  @override
  Future<({String? branch, List<String> dirty})> head() async =>
      (branch: 'main', dirty: const <String>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
