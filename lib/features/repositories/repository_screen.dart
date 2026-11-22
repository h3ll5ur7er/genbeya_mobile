import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../access/native/native_git_objects.dart';
import '../../contracts/clones.dart';
import '../../contracts/model.dart';
import '../../engines/content_layout.dart';
import '../../managers/repository_model.dart';
import 'providers.dart';

final _stateProvider = FutureProvider.family<RepositoryState, CloneRecord>((
  ref,
  record,
) async {
  final manager = await ref.watch(repositoriesManagerProvider.future);
  final started = Stopwatch()..start();
  final state = await RepositoryModel(
    NativeGitObjects(manager.folderOf(record)),
    folderName: record.name,
  ).load();
  _loadTimes[record.id] = started.elapsedMilliseconds;
  return state;
});

final _loadTimes = <String, int>{};

/// A repository as the model reads it. Until the wiki (GM-8) and the board
/// (GM-9) arrive, a summary that shows the clone is read correctly.
class RepositoryScreen extends ConsumerWidget {
  const RepositoryScreen({super.key, required this.record});

  final CloneRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_stateProvider(record));
    return Scaffold(
      appBar: AppBar(title: Text(record.name)),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text("Couldn't read the repository: $error"),
        ),
        data: (state) => RefreshIndicator(
          onRefresh: () => ref.refresh(_stateProvider(record).future),
          child: ListView(
            children: [
              _Row('Project', state.settings.name),
              if (state.settingsProblem != null)
                _Row('.genbeya.yml', state.settingsProblem!),
              _Row(
                'Content',
                state.place.branch == null
                    ? 'In the checkout (${record.branch})'
                    : 'Content branch ${state.place.branch}: ${[for (final e in state.place.areas.entries)
                        if (e.value == StorageMode.branch) e.key].join(', ')}',
              ),
              _Row(
                'Wiki',
                '${_pages(state.wiki)} pages in ${state.settings.wikiRoot}/',
              ),
              _Row(
                'Tasks',
                '${state.tasks.length} in ${state.settings.taskRoot}/: ${[for (final status in state.settings.statuses) '${state.tasks.where((t) => t.status == status).length} $status'].join(', ')}',
              ),
              if (state.problems.isNotEmpty)
                _Row(
                  'Unreadable',
                  state.problems
                      .map((p) => '${p.path}: ${p.message}')
                      .join('\n'),
                ),
              _Row(
                'People',
                '${state.people.length}; you are ${state.me == null ? 'none of them yet (set your Git name and email)' : '@${state.me}'}',
              ),
              _Row('Files', '${state.codeFiles.length} in ${record.branch}'),
              _Row('Read in', '${_loadTimes[record.id] ?? '?'} ms'),
            ],
          ),
        ),
      ),
    );
  }

  static int _pages(List<WikiNode> nodes) => nodes.fold<int>(
    0,
    (sum, node) => sum + (node.path == null ? 0 : 1) + _pages(node.children),
  );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) =>
      ListTile(title: Text(label), subtitle: Text(value));
}
