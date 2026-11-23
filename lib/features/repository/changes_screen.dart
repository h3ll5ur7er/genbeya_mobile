import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../access/git/git_remote.dart';
import '../../access/git/git_writer.dart';
import '../../contracts/clones.dart';
import '../../managers/repository_session.dart';
import '../../managers/sync_manager.dart';
import '../repositories/format.dart';
import '../repositories/providers.dart';
import 'push_sign_in.dart';
import 'work_provider.dart';

/// Syncs [record]: fetch, merge, push; then the repository is read again,
/// and the clone's last sync noted. Throws [RemoteFailure] as the remote
/// answers.
Future<SyncReport> syncRepository(
  WidgetRef ref,
  CloneRecord record,
  RepositorySession session,
) async {
  final work = await ref.read(workProvider(record).future);
  final report = await work.sync.sync(session.state!);
  await session.load();
  final manager = await ref.read(repositoriesManagerProvider.future);
  await manager.markSynced(record.id);
  ref.invalidate(clonesProvider);
  return report;
}

/// What a sync did, in words.
String describeSync(SyncReport report) {
  final lines = <String>[
    if (report.recovered)
      'Committed an edit left unfinished when the app stopped.',
    for (final e in report.pushed.entries)
      'Pushed ${e.value} commit${e.value == 1 ? '' : 's'} to ${e.key}.',
    if (report.merged.isNotEmpty)
      'Merged changes from both sides in ${report.merged.join(', ')}.',
    for (final e in report.rescued.entries)
      'Edits on ${e.key} conflicted: they are kept on ${e.value}, pushed; ${e.key} now matches the remote.',
    for (final branch in report.refused)
      'The remote refuses pushes to $branch.',
  ];
  return lines.isEmpty ? 'Up to date.' : lines.join('\n');
}

/// The branches the phone commits to: the checked-out one and the content branch.
Future<List<String>> _branches(GitWriter git, RepositorySession session) async {
  final checkedOut = (await git.head()).branch;
  final content = session.state?.place.branch;
  return [?checkedOut, if (content != null && content != checkedOut) content];
}

/// The sync badge: how many commits aren't pushed yet; opens **Changes**.
class SyncBadge extends ConsumerStatefulWidget {
  const SyncBadge({super.key, required this.record, required this.session});

  final CloneRecord record;
  final RepositorySession session;

  @override
  ConsumerState<SyncBadge> createState() => _SyncBadgeState();
}

class _SyncBadgeState extends ConsumerState<SyncBadge> {
  int _unsynced = 0;
  StreamSubscription<Object>? _changes;

  @override
  void initState() {
    super.initState();
    _count();
    _changes = widget.session.changes.listen((_) => _count());
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _count() async {
    try {
      final work = await ref.read(workProvider(widget.record).future);
      var total = 0;
      for (final branch in await _branches(work.git, widget.session)) {
        final state = await work.git.branchState(branch);
        if (state.upstream != null) total += state.ahead;
      }
      if (mounted) setState(() => _unsynced = total);
    } on Object {
      // The badge is a hint; Changes says more.
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: _unsynced == 0 ? 'Sync' : '$_unsynced not synced',
    icon: Badge(
      isLabelVisible: _unsynced > 0,
      label: Text('$_unsynced'),
      child: const Icon(Icons.sync),
    ),
    onPressed: () async {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ChangesScreen(record: widget.record, session: widget.session),
        ),
      );
      _count();
    },
  );
}

/// **Changes** ([[Experience#sync-and-changes]]): what isn't pushed yet,
/// per branch; sync; undo the newest commit before it is pushed.
class ChangesScreen extends ConsumerStatefulWidget {
  const ChangesScreen({super.key, required this.record, required this.session});

  final CloneRecord record;
  final RepositorySession session;

  @override
  ConsumerState<ChangesScreen> createState() => _ChangesScreenState();
}

class _ChangesScreenState extends ConsumerState<ChangesScreen> {
  List<(String branch, List<GitCommit> commits, String? upstream)>?
  _branchCommits;
  SyncReport? _report;
  String? _problem;
  var _busy = false;

  /// The remote wants credentials this clone doesn't have, or refused them.
  var _needsSignIn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final work = await ref.read(workProvider(widget.record).future);
    final list = <(String, List<GitCommit>, String?)>[];
    for (final branch in await _branches(work.git, widget.session)) {
      final state = await work.git.branchState(branch);
      if (state.commit == null) continue;
      list.add((
        branch,
        state.upstream == null
            ? const <GitCommit>[]
            : await work.git.unpushed(branch),
        state.upstreamCommit,
      ));
    }
    if (mounted) setState(() => _branchCommits = list);
  }

  Future<void> _sync() async {
    setState(() {
      _busy = true;
      _problem = null;
      _needsSignIn = false;
    });
    try {
      final report = await syncRepository(ref, widget.record, widget.session);
      if (mounted) setState(() => _report = report);
    } on AuthFailed catch (error) {
      if (mounted) {
        setState(() {
          _problem = error.message;
          _needsSignIn = widget.record.credential != CredentialKind.sshKey;
        });
      }
    } on RemoteFailure catch (error) {
      if (mounted) setState(() => _problem = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _moveToOwn(String branch) async {
    setState(() => _busy = true);
    try {
      final work = await ref.read(workProvider(widget.record).future);
      final name = await work.sync.moveToOwnBranch(branch);
      await widget.session.load();
      if (mounted) {
        setState(() {
          _report = null;
          _problem =
              'Your commits are on $name now, pushed, and it is checked out. Open a pull request from it on desktop or on the forge.';
        });
      }
    } on RemoteFailure catch (error) {
      if (mounted) setState(() => _problem = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  /// Undoes the newest unpushed commit of [branch]: the branch goes back to
  /// the commit before it; the edit is gone from the phone.
  Future<void> _undo(
    String branch,
    List<GitCommit> commits,
    String upstream,
  ) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Undo the last commit?'),
        content: Text(
          '"${commits.first.summary}" is removed from this phone. It was never pushed, so nobody else has it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Undo'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    final work = await ref.read(workProvider(widget.record).future);
    final parent = commits.length > 1 ? commits[1].id : upstream;
    await work.git.setBranch(branch, parent, expected: commits.first.id);
    await widget.session.load();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final branches = _branchCommits;
    return Scaffold(
      appBar: AppBar(title: const Text('Changes')),
      body: branches == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : _sync,
                        icon: const Icon(Icons.sync),
                        label: Text(_busy ? 'Syncing…' : 'Sync now'),
                      ),
                      const SizedBox(width: 12),
                      if (widget.record.lastSync != null)
                        Text(
                          'Last synced ${formatAgo(widget.record.lastSync!)}',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (_report != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(describeSync(_report!)),
                  ),
                for (final branch in _report?.refused ?? const <String>{})
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _moveToOwn(branch),
                      child: const Text(
                        'Move my commits to a branch of my own',
                      ),
                    ),
                  ),
                if (_problem != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _problem!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                if (_needsSignIn)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: _busy
                            ? null
                            : () async {
                                if (await signInToPush(
                                  context,
                                  ref,
                                  widget.record,
                                )) {
                                  await _sync();
                                }
                              },
                        icon: const Icon(Icons.key),
                        label: const Text('Sign in to push'),
                      ),
                    ),
                  ),
                for (final (branch, commits, upstream) in branches) ...[
                  ListTile(
                    title: Text(branch, style: theme.textTheme.titleSmall),
                    subtitle: Text(
                      commits.isEmpty
                          ? 'Nothing waiting to be pushed.'
                          : '${commits.length} not pushed yet',
                    ),
                    trailing: commits.isEmpty || upstream == null || _busy
                        ? null
                        : TextButton(
                            onPressed: () => _undo(branch, commits, upstream),
                            child: const Text('Undo last'),
                          ),
                  ),
                  for (final commit in commits)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.commit),
                      title: Text(commit.summary),
                      subtitle: Text(
                        '${commit.author} · ${formatAgo(DateTime.fromMillisecondsSinceEpoch(commit.time * 1000))}',
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
