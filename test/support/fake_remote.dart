import 'dart:io';

import 'package:genbeya_mobile/access/git/git_remote.dart';

/// A Git remote in memory: clones make a folder with one file.
class FakeRemote implements GitRemote {
  final branchesOf = <String, List<String>>{};
  final calls = <String>[];
  final config = <String, String>{};
  RemoteFailure? failNext;
  RemoteAccess? lastAccess;
  List<String>? lastExtra;
  int? lastDepth;

  @override
  Future<({String? defaultBranch, List<String> branches})> branches(
    String url,
    RemoteAccess access,
  ) async {
    lastAccess = access;
    final failure = failNext;
    failNext = null;
    if (failure != null) throw failure;
    final branches = branchesOf[url] ?? (throw const GitFailure('not found'));
    return (defaultBranch: branches.first, branches: branches);
  }

  @override
  Future<void> clone({
    required String url,
    required String dir,
    required String? branch,
    required List<String> extraBranches,
    required int? depth,
    required RemoteAccess access,
    required int operation,
    void Function(CloneProgress progress)? onProgress,
  }) async {
    calls.add('clone $url $branch');
    lastExtra = extraBranches;
    lastDepth = depth;
    Directory(dir).createSync(recursive: true);
    File('$dir/README.md').writeAsStringSync('hello');
    onProgress?.call((
      receivedObjects: 1,
      totalObjects: 1,
      indexedDeltas: 0,
      totalDeltas: 0,
      receivedBytes: 5,
    ));
    final failure = failNext;
    failNext = null;
    if (failure != null) throw failure;
  }

  @override
  void cancel(int operation) => calls.add('cancel $operation');

  @override
  Future<CloneHead> head(String dir) async => (
    branch: 'main',
    commit: 'abc',
    ahead: 2,
    behind: 0,
    dirty: 0,
    shallow: true,
  );

  @override
  Future<String?> getConfig(String dir, String key) async =>
      config['$dir $key'];

  @override
  Future<void> setConfig(String dir, String key, String? value) async {
    if (value == null) {
      config.remove('$dir $key');
    } else {
      config['$dir $key'] = value;
    }
  }

  int keys = 0;

  @override
  Future<({String privateKey, String publicKey, String fingerprint})>
  generateSshKey(String comment) async {
    keys++;
    return (
      privateKey: 'PRIVATE-$keys',
      publicKey: 'ssh-ed25519 AAAA$keys $comment',
      fingerprint: 'SHA256:key$keys',
    );
  }
}
