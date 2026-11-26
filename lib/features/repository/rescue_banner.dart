import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../contracts/clones.dart';
import '../../managers/repository_session.dart';
import '../../managers/rescues.dart';
import '../repositories/providers.dart';
import 'work_provider.dart';

/// The rescue banner (US-23, D6), above every tab of a repository: while
/// edits wait on a rescue branch, what differs and how to finish on the
/// desktop; once its commits are on the branch, an offer to delete it.
class RescueBanner extends ConsumerStatefulWidget {
  const RescueBanner({super.key, required this.record, required this.session});

  final CloneRecord record;
  final RepositorySession session;

  @override
  ConsumerState<RescueBanner> createState() => _RescueBannerState();
}

class _RescueBannerState extends ConsumerState<RescueBanner> {
  List<RescueState> _states = const [];
  StreamSubscription<Object>? _changes;
  var _busy = false;

  /// Rescues offered for deletion that the user put off, until the app restarts.
  static final _later = <String>{};

  @override
  void initState() {
    super.initState();
    _look();
    _changes = widget.session.changes.listen((_) => _look());
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _look() async {
    try {
      final work = await ref.read(workProvider(widget.record).future);
      final states = await work.rescues.states();
      if (mounted) {
        setState(() {
          _states = states;
        });
      }
    } on Object {
      // The banner is a hint; sync reports rescues too.
    }
  }

  Future<void> _delete(Rescue rescue) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final work = await ref.read(workProvider(widget.record).future);
      final manager = await ref.read(repositoriesManagerProvider.future);
      final access = await manager.accessFor(
        widget.record.url,
        widget.record.credential,
      );
      await work.rescues.delete(rescue, access);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Deleted ${rescue.name}, here and on the remote.'),
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't delete ${rescue.name}: $error")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
      await _look();
    }
  }

  void _details(RescueState state) {
    final rescue = state.rescue;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(
                'Kept on ${rescue.name}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'On ${rescue.day}, your edits on ${rescue.branch} and someone else\'s '
                "couldn't be merged on the phone. Nothing was lost: your commits are on "
                '${rescue.name}, pushed, and ${rescue.branch} went back to what the remote has.\n\n'
                'To finish, merge ${rescue.name} into ${rescue.branch} on the desktop '
                '(git merge origin/${rescue.name}) and push. After the next sync this banner '
                'offers to delete the rescue branch.',
              ),
              const SizedBox(height: 12),
              Text(
                'Still different from ${rescue.branch}:',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final path in state.differing)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined, size: 20),
                  title: Text(path),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: rescue.name)),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy the branch name'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final waiting = [
      for (final s in _states)
        if (!s.upstream) s,
    ];
    final done = [
      for (final s in _states)
        if (s.upstream && !_later.contains(s.rescue.name)) s,
    ];
    if (waiting.isEmpty && done.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    if (waiting.isNotEmpty) {
      final state = waiting.first;
      final count = state.differing.length;
      return MaterialBanner(
        backgroundColor: scheme.tertiaryContainer,
        leading: Icon(
          Icons.inventory_2_outlined,
          color: scheme.onTertiaryContainer,
        ),
        content: Text(
          'Edits on ${state.rescue.branch} wait on ${state.rescue.name}: '
          '$count file${count == 1 ? '' : 's'} still differ${count == 1 ? 's' : ''}. '
          'Finish the merge on the desktop.'
          '${waiting.length > 1 ? ' (${waiting.length - 1} more rescue${waiting.length == 2 ? '' : 's'})' : ''}',
          style: TextStyle(color: scheme.onTertiaryContainer),
        ),
        actions: [
          TextButton(
            onPressed: () => _details(state),
            child: const Text('What differs'),
          ),
        ],
      );
    }
    final state = done.first;
    return MaterialBanner(
      leading: const Icon(Icons.check_circle_outline),
      content: Text(
        'The edits kept on ${state.rescue.name} are on ${state.rescue.branch} now. '
        'Delete the rescue branch, here and on the remote?',
      ),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() => _later.add(state.rescue.name)),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _delete(state.rescue),
          child: const Text('Delete it'),
        ),
      ],
    );
  }
}
