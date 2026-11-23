import 'dart:typed_data';

import '../../src/rust/api/git.dart' as core;
import '../../src/rust/git.dart' as core;
import '../git/git_remote.dart';
import '../git/git_writer.dart';
import 'native_git_remote.dart';
import 'transfers.dart';

/// [GitWriter] of a clone, through the Rust core.
class NativeGitWriter implements GitWriter {
  NativeGitWriter(this.dir);

  final String dir;
  static int _operation = 1 << 20;

  core.Identity _identity(Signer signer) =>
      core.Identity(name: signer.name, email: signer.email);

  core.RemoteOptions _options(RemoteAccess access) =>
      const NativeGitRemote().optionsFor(access);

  Future<T> _mapped<T>(Future<T> Function() run) =>
      const NativeGitRemote().mapped(run);

  @override
  Future<String> commitFiles(
    List<String> paths,
    String message,
    Signer signer,
  ) => _mapped(
    () => core.commitFiles(
      dir: dir,
      paths: paths,
      message: message,
      identity: _identity(signer),
    ),
  );

  @override
  Future<String> commitOntoBranch(
    String branch,
    Map<String, Uint8List?> files,
    String message,
    Signer signer,
  ) => _mapped(
    () => core.commitOntoBranch(
      dir: dir,
      branch: branch,
      changes: [
        for (final e in files.entries)
          core.FileChange(path: e.key, content: e.value),
      ],
      message: message,
      identity: _identity(signer),
    ),
  );

  @override
  Future<void> fetch(List<String> extraBranches, RemoteAccess access) =>
      _mapped(
        () => runTransfer(
          core.fetch(
            dir: dir,
            extraBranches: extraBranches,
            remote: _options(access),
            operationId: BigInt.from(++_operation),
          ),
        ),
      );

  @override
  Future<Rebased> rebase(
    String? branch,
    Signer signer,
    Map<String, Map<String, Uint8List?>> resolutions,
  ) => _mapped(() async {
    final outcome = await core.rebaseBranch(
      dir: dir,
      branch: branch,
      identity: _identity(signer),
      resolutions: [
        for (final byCommit in resolutions.entries)
          for (final file in byCommit.value.entries)
            core.Resolution(
              commit: byCommit.key,
              path: file.key,
              content: file.value,
            ),
      ],
    );
    return switch (outcome) {
      core.RebaseOutcome_UpToDate() => const RebaseDone(replayed: 0),
      core.RebaseOutcome_FastForwarded() => const RebaseDone(replayed: 0),
      core.RebaseOutcome_Rebased(:final commits) => RebaseDone(
        replayed: commits,
      ),
      core.RebaseOutcome_Conflicts(:final commit, :final conflicts) =>
        RebaseConflicts(commit, [
          for (final c in conflicts)
            (
              path: c.path,
              ancestor: c.ancestor,
              remote: c.ours,
              local: c.theirs,
            ),
        ]),
    };
  });

  @override
  Future<Pushed> push(String branch, RemoteAccess access) => _mapped(() async {
    final outcome = await core.push(
      dir: dir,
      branch: branch,
      remote: _options(access),
    );
    return switch (outcome) {
      core.PushOutcome_Pushed() => Pushed.pushed,
      core.PushOutcome_UpToDate() => Pushed.upToDate,
      core.PushOutcome_Rejected() => Pushed.rejected,
    };
  });

  @override
  Future<BranchState> branchState(String branch) => _mapped(() async {
    final status = await core.branchStatus(dir: dir, branch: branch);
    return (
      commit: status.commit,
      upstream: status.upstream,
      upstreamCommit: status.upstreamCommit,
      ahead: status.ahead,
      behind: status.behind,
    );
  });

  @override
  Future<List<GitCommit>> unpushed(String branch, {int max = 100}) => _mapped(
    () async => [
      for (final c in await core.unpushedCommits(
        dir: dir,
        branch: branch,
        max: max,
      ))
        (id: c.id, author: c.author, time: c.time.toInt(), summary: c.summary),
    ],
  );

  @override
  Future<void> setBranch(String branch, String commit, {String? expected}) =>
      _mapped(
        () => core.setBranch(
          dir: dir,
          branch: branch,
          commit: commit,
          expected: expected,
        ),
      );

  @override
  Future<void> switchBranch(String branch) =>
      _mapped(() => core.switchBranch(dir: dir, branch: branch));

  @override
  Future<({String? branch, List<String> dirty})> head() => _mapped(() async {
    final head = await core.head(dir: dir);
    return (branch: head.branch, dirty: head.dirty);
  });
}
