import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../contracts/clones.dart';
import '../../managers/repositories_manager.dart';
import 'add_repository_screen.dart';
import 'format.dart';
import 'identity_dialog.dart';
import 'providers.dart';
import 'repository_screen.dart';
import 'ssh_key_screen.dart';

/// The start screen: the clones on this phone ([[Experience#navigation]]).
class RepositoriesScreen extends ConsumerWidget {
  const RepositoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clones = ref.watch(clonesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Repositories'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (choice) => switch (choice) {
              'ssh' => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SshKeyScreen()),
              ),
              _ => context.push('/spikes'),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'ssh', child: Text('SSH key of this phone')),
              PopupMenuItem(value: 'spikes', child: Text('Spikes')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(clonesProvider.future),
        child: clones.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text("Couldn't list the repositories: $error"),
              ),
            ],
          ),
          data: (list) => list.isEmpty
              ? const _Empty()
              : ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    for (final status in list)
                      _CloneTile(
                        status: status,
                        onOpen: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                RepositoryScreen(record: status.record),
                          ),
                        ),
                        onRemove: () => _remove(context, ref, status),
                        onIdentity: () =>
                            _identity(context, ref, status.record),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final added = await Navigator.of(context).push<CloneRecord>(
      MaterialPageRoute(builder: (_) => const AddRepositoryScreen()),
    );
    if (added != null) ref.invalidate(clonesProvider);
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    CloneStatus status,
  ) async {
    final unsynced = status.head?.ahead ?? 0;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${status.record.name}?'),
        content: Text(
          unsynced > 0
              ? 'This clone has $unsynced commit${unsynced == 1 ? '' : 's'} not synced yet. '
                    'Removing it deletes them from this phone; nobody else has them.'
              : 'Only this phone\'s copy goes; the repository on the server stays as it is.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    final manager = await ref.read(repositoriesManagerProvider.future);
    await manager.remove(status.record.id);
    ref.invalidate(clonesProvider);
  }

  Future<void> _identity(
    BuildContext context,
    WidgetRef ref,
    CloneRecord record,
  ) async {
    final manager = await ref.read(repositoriesManagerProvider.future);
    final current = await manager.identityOf(record);
    if (!context.mounted) return;
    final identity = await showIdentityDialog(context, current);
    if (identity != null) await manager.setIdentity(record, identity);
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 64),
        Text(
          'No repositories yet',
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Add one with its address: https for public repositories or with a token, or SSH with this phone\'s own key.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _CloneTile extends StatelessWidget {
  const _CloneTile({
    required this.status,
    required this.onOpen,
    required this.onRemove,
    required this.onIdentity,
  });

  final CloneStatus status;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final VoidCallback onIdentity;

  @override
  Widget build(BuildContext context) {
    final record = status.record;
    final head = status.head;
    final parts = <String>[
      head?.branch ?? record.branch,
      if (head != null && head.ahead > 0) '${head.ahead} unsynced',
      if (record.lastSync != null)
        'synced ${formatAgo(record.lastSync!)}'
      else
        'cloned ${formatAgo(record.added)}',
      if (status.bytes != null) formatBytes(status.bytes!),
    ];
    return ListTile(
      leading: const Icon(Icons.folder_outlined),
      title: Text(record.name),
      subtitle: Text(status.problem ?? parts.join(' · ')),
      onTap: status.problem == null ? onOpen : null,
      trailing: PopupMenuButton<String>(
        onSelected: (choice) => choice == 'remove' ? onRemove() : onIdentity(),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'identity', child: Text('Git name and email')),
          PopupMenuItem(value: 'remove', child: Text('Remove clone')),
        ],
      ),
    );
  }
}
