/// Rescue branches ([[Experience#sync-and-changes]], D6, US-23): when sync
/// can't merge the phone's commits, they are kept on a pushed
/// `mobile/rescue/<handle>-<date>` and the branch goes back to the remote.
/// The app remembers each one, says what still differs until its commits
/// are on the branch (the desktop finished the merge), and then offers to
/// delete it, here and on the remote. Nothing is deleted without asking.
library;

import '../access/git/git_objects.dart';
import '../access/git/git_remote.dart';
import '../access/git/git_writer.dart';
import '../access/storage/json_store.dart';

/// A rescue: its branch, the branch whose commits it keeps, the commit
/// those commits start from, its tip, and the day it was made.
typedef Rescue = ({
  String name,
  String branch,
  String base,
  String tip,
  String day,
});

/// A rescue as it stands now: whether its commits are on the branch, and
/// the files it changed that still differ from the branch.
typedef RescueState = ({Rescue rescue, bool upstream, List<String> differing});

class Rescues {
  Rescues({required this.store, required this.git, required this.objects});

  /// Where the clone's rescues are remembered (the app's storage).
  final JsonStore store;
  final GitWriter git;
  final GitObjects objects;

  Future<List<Rescue>> all() async {
    final data = await store.read();
    if (data is! List) return [];
    return [
      for (final entry in data)
        if (entry case {
          'name': final String name,
          'branch': final String branch,
          'base': final String base,
          'tip': final String tip,
          'day': final String day,
        })
          (name: name, branch: branch, base: base, tip: tip, day: day),
    ];
  }

  Future<void> _save(List<Rescue> rescues) => store.write([
    for (final r in rescues)
      {
        'name': r.name,
        'branch': r.branch,
        'base': r.base,
        'tip': r.tip,
        'day': r.day,
      },
  ]);

  Future<void> remember(Rescue rescue) async =>
      _save([...(await all()).where((r) => r.name != rescue.name), rescue]);

  Future<void> _forget(String name) async =>
      _save([...(await all()).where((r) => r.name != name)]);

  /// Each rescue as it stands. One whose branch is gone (deleted on another
  /// device, say) is forgotten.
  Future<List<RescueState>> states() async {
    final states = <RescueState>[];
    for (final rescue in await all()) {
      final kept =
          await objects.resolveCommit('refs/heads/${rescue.name}') ??
          await objects.resolveCommit('refs/remotes/origin/${rescue.name}');
      if (kept == null) {
        await _forget(rescue.name);
        continue;
      }
      if (await git.branchContains(rescue.branch, rescue.tip)) {
        states.add((rescue: rescue, upstream: true, differing: const []));
        continue;
      }
      final branchTip =
          await objects.resolveCommit('refs/heads/${rescue.branch}') ??
          await objects.resolveCommit('refs/remotes/origin/${rescue.branch}');
      final differing = <String>[];
      for (final path in await objects.changedPaths(rescue.base, rescue.tip)) {
        final mine = await objects.readFileAt(rescue.tip, path, _limit);
        final theirs = branchTip == null
            ? null
            : await objects.readFileAt(branchTip, path, _limit);
        if (!_same(mine, theirs)) differing.add(path);
      }
      // Every file as the rescue has it: the desktop merged it another way.
      states.add((
        rescue: rescue,
        upstream: differing.isEmpty,
        differing: differing,
      ));
    }
    return states;
  }

  /// Deletes the rescue branch here and on the remote; it is forgotten.
  Future<void> delete(Rescue rescue, RemoteAccess access) async {
    await git.deleteBranch(rescue.name, access: access);
    await _forget(rescue.name);
  }
}

const _limit = 2 * 1024 * 1024;

bool _same(List<int>? a, List<int>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
