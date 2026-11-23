/// Sync ([[Call chains#c10-sync]], [[Experience#sync-and-changes]]): fetch,
/// put the phone's commits on top of what others pushed, push. One sync at
/// a time per clone; nothing is ever forced or discarded.
///
/// - Each branch the phone commits to, the checked-out one and the content
///   branch, is rebased in memory onto its upstream.
/// - Task files both sides changed are merged the Genbeya way
///   (`task_merge.dart`).
/// - When that still conflicts, the local commits go to a rescue branch,
///   `mobile/rescue/<handle>-<date>`, which is pushed, and the branch goes
///   back to its upstream.
/// - A rejected push means someone pushed meanwhile: again from fetch, up
///   to three times. A push the remote refuses although nothing new is
///   there (a protected branch) is reported, for the commits to move to a
///   branch of their own.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../access/git/git_remote.dart';
import '../access/git/git_writer.dart';
import '../engines/task_engine.dart';
import '../engines/task_merge.dart';
import 'content_writer.dart';
import 'repository_model.dart';

/// How a sync went, for the screen to say.
class SyncReport {
  SyncReport();

  /// Commits pushed, by branch.
  final pushed = <String, int>{};

  /// Task files merged the Genbeya way.
  final merged = <String>{};

  /// Rescue branches made, by the branch whose commits they keep.
  final rescued = <String, String>{};

  /// Branches whose push the remote refused although nothing new was there.
  final refused = <String>{};

  /// Whether a write left unfinished by a stopped app was committed first.
  var recovered = false;

  bool get nothingToDo =>
      pushed.isEmpty && merged.isEmpty && rescued.isEmpty && refused.isEmpty;
}

class SyncManager {
  SyncManager({
    required this.git,
    required this.writer,
    required this.access,
    required this.signer,
    required this.handle,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final GitWriter git;
  final ContentWriter writer;

  /// How to reach the remote, read when a sync starts.
  final Future<RemoteAccess> Function() access;
  final Future<Signer> Function() signer;

  /// The user's handle, for rescue branch names.
  final String Function() handle;
  final DateTime Function() _now;

  Future<void> _queue = Future.value();

  /// Syncs the branches the phone commits to; [state] names them and the
  /// task settings for the merge.
  Future<SyncReport> sync(RepositoryState state) {
    final result = _queue.then((_) => _sync(state));
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<SyncReport> _sync(RepositoryState state) async {
    final report = SyncReport()..recovered = await writer.recover();
    final remote = await access();
    final who = await signer();
    final content = state.place.branch;
    final checkedOut = (await git.head()).branch;
    final branches = [
      ?checkedOut,
      if (content != null && content != checkedOut) content,
    ];

    for (var attempt = 1; attempt <= 3; attempt++) {
      await git.fetch([?content], remote);
      final rejected = <String>[];
      for (final branch in branches) {
        final before = await git.branchState(branch);
        if (before.commit == null) continue;
        if (before.upstream != null && before.behind > 0 && before.ahead > 0) {
          await _rebase(branch, state, who, report, remote);
        } else if (before.upstream != null && before.behind > 0) {
          await git.rebase(branch, who, const {});
        }
        final now = await git.branchState(branch);
        if (now.ahead == 0 && now.upstream != null) continue;
        switch (await git.push(branch, remote)) {
          case Pushed.pushed:
            report.pushed[branch] = (report.pushed[branch] ?? 0) + now.ahead;
          case Pushed.upToDate:
            break;
          case Pushed.rejected:
            rejected.add(branch);
        }
      }
      if (rejected.isEmpty) return report;
      if (attempt == 3) {
        // Refused although we just fetched: the remote won't take them.
        report.refused.addAll(rejected);
        return report;
      }
      // Someone pushed meanwhile, or the remote refuses: fetch and see.
      await git.fetch([?content], remote);
      var moved = false;
      for (final branch in rejected) {
        if ((await git.branchState(branch)).behind > 0) moved = true;
      }
      if (!moved) {
        report.refused.addAll(rejected);
        return report;
      }
    }
    return report;
  }

  /// Rebases [branch], merging conflicting task files; when a conflict
  /// can't be merged, keeps the local commits on a pushed rescue branch and
  /// puts the branch back to its upstream.
  Future<void> _rebase(
    String branch,
    RepositoryState state,
    Signer who,
    SyncReport report,
    RemoteAccess remote,
  ) async {
    final resolutions = <String, Map<String, Uint8List?>>{};
    for (var round = 0; round < 50; round++) {
      final outcome = await git.rebase(branch, who, resolutions);
      if (outcome is! RebaseConflicts) return;
      final resolved = <String, Uint8List?>{};
      for (final conflict in outcome.conflicts) {
        final merged = _merge(conflict, state);
        if (merged == null) {
          await _rescue(branch, report, remote);
          return;
        }
        resolved[conflict.path] = Uint8List.fromList(utf8.encode(merged));
        report.merged.add(conflict.path);
      }
      resolutions[outcome.commit] = {
        ...?resolutions[outcome.commit],
        ...resolved,
      };
    }
    await _rescue(branch, report, remote);
  }

  /// The Genbeya merge of a conflicting task file; null when it can't.
  String? _merge(GitConflict conflict, RepositoryState state) {
    final taskRoot = state.settings.taskRoot;
    if (!isTaskFile(conflict.path, taskRoot)) return null;
    final base = conflict.ancestor;
    final theirs = conflict.remote;
    final mine = conflict.local;
    if (base == null || theirs == null || mine == null) return null;
    try {
      return mergeTask(
        path: conflict.path,
        base: utf8.decode(base),
        remote: utf8.decode(theirs),
        local: utf8.decode(mine),
        taskRoot: taskRoot,
        statuses: state.settings.statuses,
      );
    } on MergeConflict {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Keeps [branch]'s local commits on `mobile/rescue/<handle>-<date>`,
  /// pushes it (a failed push leaves it for the next sync), and puts the
  /// branch back to its upstream.
  Future<void> _rescue(
    String branch,
    SyncReport report,
    RemoteAccess remote,
  ) async {
    final state = await git.branchState(branch);
    final local = state.commit!;
    final day = _now().toIso8601String().substring(0, 10);
    var name = 'mobile/rescue/${handle()}-$day';
    for (var n = 2; (await git.branchState(name)).commit != null; n++) {
      name = 'mobile/rescue/${handle()}-$day-$n';
    }
    await git.setBranch(name, local);
    try {
      await git.push(name, remote);
    } on RemoteFailure {
      // Pushed with the next sync.
    }
    await git.setBranch(branch, state.upstreamCommit!, expected: local);
    report.rescued[branch] = name;
  }
}
