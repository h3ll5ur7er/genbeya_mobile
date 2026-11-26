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

import '../access/git/git_objects.dart';
import '../access/git/git_remote.dart';
import '../access/git/git_writer.dart';
import '../engines/content_layout.dart';
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

  /// Tasks this phone created whose IDs a teammate took meanwhile: the old
  /// ID and the new one.
  final renumbered = <String, String>{};

  bool get nothingToDo =>
      pushed.isEmpty &&
      merged.isEmpty &&
      rescued.isEmpty &&
      refused.isEmpty &&
      renumbered.isEmpty;
}

class SyncManager {
  SyncManager({
    required this.git,
    required this.objects,
    required this.writer,
    required this.access,
    required this.signer,
    required this.handle,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final GitWriter git;

  /// Reads commits, for the tasks local commits created.
  final GitObjects objects;
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
          final renumbering = await _renumbering(branch, before, state);
          final kept = await _rebase(
            branch,
            state,
            who,
            report,
            remote,
            renumbering?.resolutions ?? const {},
            renumbering?.oldPaths ?? const {},
          );
          if (kept && renumbering != null) {
            await _rewriteReferences(branch, state, renumbering, report);
          }
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

  /// Moves [branch]'s commits that the remote refused (a protected branch)
  /// to `mobile/<handle>`, a branch of the user's own: it is checked out
  /// and pushed, and [branch] goes back to its upstream (D5). Its name.
  Future<String> moveToOwnBranch(String branch) {
    final result = _queue.then((_) async {
      final remote = await access();
      final state = await git.branchState(branch);
      final local = state.commit!;
      final name = await _ownBranchName();
      await git.setBranch(name, local);
      await git.switchBranch(name);
      if (state.upstreamCommit != null) {
        await git.setBranch(branch, state.upstreamCommit!, expected: local);
      }
      await git.push(name, remote);
      return name;
    });
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  /// Starts a branch of the user's own, `mobile/<handle>`, at the
  /// checked-out commit and checks it out, for commits to go there instead
  /// of the checked-out branch (D5). Its name.
  Future<String> startOwnBranch() {
    final result = _queue.then((_) async {
      final current = (await git.head()).branch;
      if (current == null) throw StateError('No branch is checked out.');
      final commit = (await git.branchState(current)).commit!;
      final name = await _ownBranchName();
      await git.setBranch(name, commit);
      await git.switchBranch(name);
      return name;
    });
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  /// `mobile/<handle>`, numbered when taken.
  Future<String> _ownBranchName() async {
    var name = 'mobile/${handle()}';
    for (var n = 2; (await git.branchState(name)).commit != null; n++) {
      name = 'mobile/${handle()}-$n';
    }
    return name;
  }

  /// Rebases [branch], merging conflicting task files; when a conflict
  /// can't be merged, keeps the local commits on a pushed rescue branch and
  /// puts the branch back to its upstream. [initial] resolutions rewrite
  /// replayed commits (a renumbered task); a conflict at one of [keepRemote]
  /// keeps the remote's file. Whether the local commits were kept on the
  /// branch.
  Future<bool> _rebase(
    String branch,
    RepositoryState state,
    Signer who,
    SyncReport report,
    RemoteAccess remote, [
    Map<String, Map<String, Uint8List?>> initial = const {},
    Set<String> keepRemote = const {},
  ]) async {
    final resolutions = <String, Map<String, Uint8List?>>{
      for (final e in initial.entries) e.key: {...e.value},
    };
    for (var round = 0; round < 50; round++) {
      final outcome = await git.rebase(branch, who, resolutions);
      if (outcome is! RebaseConflicts) return true;
      final resolved = <String, Uint8List?>{};
      for (final conflict in outcome.conflicts) {
        if (keepRemote.contains(conflict.path)) {
          resolved[conflict.path] = conflict.remote;
          continue;
        }
        final merged = _merge(conflict, state);
        if (merged == null) {
          await _rescue(branch, report, remote);
          return false;
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
    return false;
  }

  /// Tasks the local commits of [branch] created whose IDs its upstream took
  /// meanwhile (a teammate made a task with the same next ID): each gets the
  /// next free ID, and the replayed commits are rewritten so that the old
  /// path stays as the remote has it and the task is at its new one. Null
  /// when nothing clashes.
  Future<_Renumbering?> _renumbering(
    String branch,
    BranchState before,
    RepositoryState state,
  ) async {
    final local = before.commit!;
    final upstream = before.upstreamCommit!;
    final commits = await git.unpushed(branch, max: 1000);
    if (commits.isEmpty) return null;
    final base = await objects.resolveCommit('${commits.last.id}^');
    if (base == null) return null;
    final settings = state.settings;
    final taskRoot = settings.taskRoot;
    Future<Map<String, String>> tasksAt(String commit) async => {
      for (final file in await objects.listFiles(commit))
        if (isTaskFile(file.path, taskRoot))
          _idOf(file.path).toUpperCase(): file.path,
    };
    final atBase = await tasksAt(base);
    final atLocal = await tasksAt(local);
    final atUpstream = await tasksAt(upstream);
    final clashing = [
      for (final id in atLocal.keys)
        if (!atBase.containsKey(id) && atUpstream.containsKey(id)) id,
    ]..sort();
    if (clashing.isEmpty) return null;

    final known = <String>{
      for (final paths in [atBase.values, atLocal.values, atUpstream.values])
        for (final path in paths) _idOf(path),
    };
    final names = {for (final id in known) '${id.toLowerCase()}.md'};
    final engine = TaskEngine();
    final renumbered = <String, String>{};
    for (final id in clashing) {
      // The task keeps its prefix, whatever the settings say now.
      final name = _idOf(atLocal[id]!);
      final dash = name.lastIndexOf('-');
      final next = engine.nextId(
        dash > 0 ? name.substring(0, dash) : settings.taskPrefix,
        known,
        (candidate) => names.contains('${candidate.toLowerCase()}.md'),
      );
      known.add(next);
      names.add('${next.toLowerCase()}.md');
      renumbered[name] = next;
    }

    final resolutions = <String, Map<String, Uint8List?>>{};
    final oldPaths = <String>{};
    var parent = base;
    for (final commit in commits.reversed) {
      for (final path in await objects.changedPaths(parent, commit.id)) {
        if (!isTaskFile(path, taskRoot)) continue;
        final old = renumbered.keys
            .where((id) => id.toLowerCase() == _idOf(path).toLowerCase())
            .firstOrNull;
        if (old == null) continue;
        final mine = await objects.readFileAt(commit.id, path, _textLimit);
        final theirs = await objects.readFileAt(upstream, path, _textLimit);
        final folder = path.substring(0, path.lastIndexOf('/') + 1);
        (resolutions[commit.id] ??= {})
          ..[path] = theirs
          ..['$folder${renumbered[old]}.md'] = mine == null
              ? null
              : _bytes(_renumberText(utf8.decode(mine), old, renumbered[old]!));
        oldPaths.add(path);
      }
      parent = commit.id;
    }
    return (
      resolutions: resolutions,
      oldPaths: oldPaths,
      renumbered: renumbered,
      base: base,
      local: local,
    );
  }

  /// After a renumbering: references to an old ID in lines this phone
  /// added (a comment, another new task's `depends_on`) now name the new
  /// one, in one commit on top of the merged files.
  Future<void> _rewriteReferences(
    String branch,
    RepositoryState state,
    _Renumbering renumbering,
    SyncReport report,
  ) async {
    report.renumbered.addAll(renumbering.renumbered);
    final tip = (await git.branchState(branch)).commit;
    if (tip == null) return;
    final files = <String, String?>{};
    for (final path in await objects.changedPaths(
      renumbering.base,
      renumbering.local,
    )) {
      if (renumbering.oldPaths.contains(path)) continue;
      if (contentAreaOf(
            path,
            wikiRoot: state.settings.wikiRoot,
            taskRoot: state.settings.taskRoot,
            pullRoot: state.settings.pullRoot,
          ) ==
          null) {
        continue;
      }
      final mine = await objects.readFileAt(
        renumbering.local,
        path,
        _textLimit,
      );
      final now = await objects.readFileAt(tip, path, _textLimit);
      if (mine == null || now == null) continue;
      final before = await objects.readFileAt(
        renumbering.base,
        path,
        _textLimit,
      );
      final String text;
      try {
        text = utf8.decode(now);
      } on FormatException {
        continue;
      }
      final added = _addedLines(
        utf8.decode(mine, allowMalformed: true),
        before == null ? '' : utf8.decode(before, allowMalformed: true),
      );
      var changed = false;
      final lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!added.contains(lines[i])) continue;
        var line = lines[i];
        for (final e in renumbering.renumbered.entries) {
          line = _renumberText(line, e.key, e.value);
        }
        if (line != lines[i]) {
          lines[i] = line;
          changed = true;
        }
      }
      if (changed) files[path] = lines.join('\n');
    }
    if (files.isEmpty) return;
    final names = [
      for (final e in renumbering.renumbered.entries) '${e.key} to ${e.value}',
    ].join(', ');
    await writer.write(
      state,
      files,
      'Renumber $names where this phone referred to it',
    );
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

/// Tasks renumbered while syncing one branch.
typedef _Renumbering = ({
  Map<String, Map<String, Uint8List?>> resolutions,
  Set<String> oldPaths,
  Map<String, String> renumbered,
  String base,
  String local,
});

const _textLimit = 2 * 1024 * 1024;

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

/// A task file's ID as its name says (desktop names files by ID).
String _idOf(String path) {
  final name = path.substring(path.lastIndexOf('/') + 1);
  return name.substring(0, name.length - 3);
}

/// [text] with the ID [old] as a whole word, in any case, replaced by [now].
String _renumberText(String text, String old, String now) => text.replaceAll(
  RegExp('(?<![\\w-])${RegExp.escape(old)}(?![\\w])', caseSensitive: false),
  now,
);

/// The lines of [mine] that [base] doesn't have, as often as they were added.
Set<String> _addedLines(String mine, String base) {
  final left = <String, int>{};
  for (final line in base.split('\n')) {
    left[line] = (left[line] ?? 0) + 1;
  }
  final added = <String>{};
  for (final line in mine.split('\n')) {
    final count = left[line] ?? 0;
    if (count > 0) {
      left[line] = count - 1;
    } else {
      added.add(line);
    }
  }
  return added;
}
