/// What the app asks of Git to write and sync: commits, fetch, rebase,
/// push and branches. The native core implements it ([NativeGitWriter]).
library;

import 'dart:typed_data';

import 'git_remote.dart';

typedef Signer = ({String name, String email});

/// A conflict a rebase stopped at: the file as the common ancestor, the
/// remote (being built on) and the local commit (being replayed) have it.
typedef GitConflict = ({
  String path,
  Uint8List? ancestor,
  Uint8List? remote,
  Uint8List? local,
});

/// How a rebase ended.
sealed class Rebased {
  const Rebased();
}

/// Nothing to do, or the branch moved to its upstream, or the local
/// commits were replayed.
class RebaseDone extends Rebased {
  const RebaseDone({required this.replayed});
  final int replayed;
}

/// Stopped at a conflict while replaying [commit]; nothing changed.
class RebaseConflicts extends Rebased {
  const RebaseConflicts(this.commit, this.conflicts);
  final String commit;
  final List<GitConflict> conflicts;
}

enum Pushed { pushed, upToDate, rejected }

typedef BranchState = ({
  String? commit,
  String? upstream,
  String? upstreamCommit,
  int ahead,
  int behind,
});

typedef GitCommit = ({String id, String author, int time, String summary});

abstract interface class GitWriter {
  /// Commits the working tree's state of [paths] on the checked-out branch.
  Future<String> commitFiles(List<String> paths, String message, Signer signer);

  /// Commits [files] (null removes one) onto [branch] without a checkout.
  Future<String> commitOntoBranch(
    String branch,
    Map<String, Uint8List?> files,
    String message,
    Signer signer,
  );

  Future<void> fetch(List<String> extraBranches, RemoteAccess access);

  /// Replays [branch]'s local commits (the checked-out one when null) onto
  /// its upstream; [resolutions] by commit, then path.
  Future<Rebased> rebase(
    String? branch,
    Signer signer,
    Map<String, Map<String, Uint8List?>> resolutions,
  );

  Future<Pushed> push(String branch, RemoteAccess access);

  Future<BranchState> branchState(String branch);

  Future<List<GitCommit>> unpushed(String branch, {int max = 100});

  /// Points [branch] at [commit] (creating it), refused when it isn't at
  /// [expected]; the working tree follows a checked-out branch.
  Future<void> setBranch(String branch, String commit, {String? expected});

  /// Checks out a local branch, safely.
  Future<void> switchBranch(String branch);

  /// The checked-out branch, and paths with uncommitted changes.
  Future<({String? branch, List<String> dirty})> head();
}
