import 'dart:io';
import 'dart:typed_data';

import 'package:genbeya_mobile/access/git/git_remote.dart';
import 'package:genbeya_mobile/access/git/git_writer.dart';

import '../../support/fake_git.dart';

/// A clone for the stories: [repo]'s commits and refs, written to as the
/// native core does. The checkout's files are read from [dir] when
/// committed; branches have upstreams on a remote whose refs are
/// `refs/remotes/origin/<branch>`; a push copies the branch there, unless
/// the remote [refuses] it (a protected branch).
class StoryGit implements GitWriter {
  StoryGit(this.repo, this.dir);

  final FakeGit repo;
  final String dir;

  /// The checked-out branch.
  var current = 'main';

  /// Branches the remote refuses pushes to.
  final refuses = <String>{};

  /// Commit messages, newest last; and each commit's parent.
  final messages = <String>[];
  final _parents = <String, String?>{};
  final _summaries = <String, String>{};
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
    final id = 'story-${++_n}';
    repo.commits[id] = next;
    _parents[id] = parent;
    _summaries[id] = message;
    messages.add(message);
    return id;
  }

  String? _local(String branch) =>
      branch == current ? repo.refs['HEAD'] : repo.refs['refs/heads/$branch'];

  void _setLocal(String branch, String commit) {
    repo.refs['refs/heads/$branch'] = commit;
    if (branch == current) repo.refs['HEAD'] = commit;
  }

  /// [from]'s first-parent ancestors, nearest first, without [from].
  List<String> _ancestors(String? from) {
    final list = <String>[];
    var at = from == null ? null : _parents[from];
    while (at != null) {
      list.add(at);
      at = _parents[at];
    }
    // A merge's second parent and what it holds count too.
    for (final id in [?from, ...list]) {
      final second = _secondParents[id];
      if (second != null) list.addAll([second, ..._ancestors(second)]);
    }
    return list;
  }

  @override
  Future<String> commitFiles(
    List<String> paths,
    String message,
    Signer signer,
  ) async {
    final id = _commit(repo.refs['HEAD'], {
      for (final path in paths)
        path: File('$dir/$path').existsSync()
            ? File('$dir/$path').readAsBytesSync()
            : null,
    }, message);
    _setLocal(current, id);
    return id;
  }

  @override
  Future<String> commitOntoBranch(
    String branch,
    Map<String, Uint8List?> files,
    String message,
    Signer signer,
  ) async {
    final base =
        repo.refs['refs/heads/$branch'] ??
        repo.refs['refs/remotes/origin/$branch'];
    final id = _commit(base, files, message);
    repo.refs['refs/heads/$branch'] = id;
    return id;
  }

  /// How often the remote was asked: nothing goes there until a sync.
  var fetches = 0;

  @override
  Future<void> fetch(List<String> extraBranches, RemoteAccess access) async =>
      fetches++;

  @override
  Future<Rebased> rebase(
    String? branch,
    Signer signer,
    Map<String, Map<String, Uint8List?>> resolutions,
  ) async {
    final name = branch ?? current;
    final state = await branchState(name);
    if (state.ahead == 0 && state.behind > 0) {
      _setLocal(name, state.upstreamCommit!);
    }
    return const RebaseDone(replayed: 0);
  }

  @override
  Future<Pushed> push(String branch, RemoteAccess access) async {
    if (refuses.contains(branch)) return Pushed.rejected;
    final local = _local(branch);
    if (local == null) return Pushed.upToDate;
    if (repo.refs['refs/remotes/origin/$branch'] == local) {
      return Pushed.upToDate;
    }
    repo.refs['refs/remotes/origin/$branch'] = local;
    return Pushed.pushed;
  }

  @override
  Future<BranchState> branchState(String branch) async {
    final commit = _local(branch);
    final upstream = repo.refs['refs/remotes/origin/$branch'];
    var ahead = 0;
    var behind = 0;
    if (commit != null && upstream != null && commit != upstream) {
      final mine = [commit, ..._ancestors(commit)];
      final theirs = [upstream, ..._ancestors(upstream)];
      // As Git counts them: commits on one side and not in the other's history.
      ahead = mine.where((c) => !theirs.contains(c)).toSet().length;
      behind = theirs.where((c) => !mine.contains(c)).toSet().length;
    }
    return (
      commit: commit,
      upstream: upstream == null ? null : 'origin/$branch',
      upstreamCommit: upstream,
      ahead: ahead,
      behind: behind,
    );
  }

  @override
  Future<List<GitCommit>> unpushed(String branch, {int max = 100}) async {
    final state = await branchState(branch);
    final commits = [
      state.commit!,
      ..._ancestors(state.commit),
    ].take(state.ahead).take(max);
    return [
      for (final id in commits)
        (
          id: id,
          author: 'Ada Lovelace',
          time: DateTime.utc(2026, 11, 26).millisecondsSinceEpoch ~/ 1000,
          summary: _summaries[id] ?? id,
        ),
    ];
  }

  @override
  Future<void> setBranch(
    String branch,
    String commit, {
    String? expected,
  }) async {
    if (expected != null && _local(branch) != expected) {
      throw StateError('$branch moved meanwhile');
    }
    _setLocal(branch, commit);
  }

  @override
  Future<void> switchBranch(String branch) async {
    current = branch;
    repo.refs['HEAD'] = repo.refs['refs/heads/$branch']!;
  }

  @override
  Future<void> deleteBranch(String branch, {RemoteAccess? access}) async {
    if (branch == current) throw StateError('$branch is checked out');
    if (access != null) repo.refs.remove('refs/remotes/origin/$branch');
    repo.refs.remove('refs/heads/$branch');
  }

  @override
  Future<bool> branchContains(String branch, String commit) async {
    final tip = _local(branch) ?? repo.refs['refs/remotes/origin/$branch'];
    if (tip == null) return false;
    return tip == commit || _ancestors(tip).contains(commit);
  }

  /// Makes [commit] the parent chain's newest on [branch] as a merge on the
  /// desktop would: a commit whose first parent is the branch and that
  /// holds [files] (for a merge of a rescue branch, its files).
  String merge(String branch, String other, Map<String, Uint8List?> files) {
    final tip = repo.refs['refs/remotes/origin/$branch']!;
    final id = _commit(tip, files, 'Merge $other into $branch');
    _secondParents[id] =
        repo.refs['refs/remotes/origin/$other'] ??
        repo.refs['refs/heads/$other']!;
    repo.refs['refs/remotes/origin/$branch'] = id;
    return id;
  }

  final _secondParents = <String, String>{};

  @override
  Future<({String? branch, List<String> dirty})> head() async =>
      (branch: current, dirty: const <String>[]);
}
