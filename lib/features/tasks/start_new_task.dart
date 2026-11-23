import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../contracts/clones.dart';
import '../../contracts/model.dart';
import '../repositories/providers.dart';
import '../repository/session_provider.dart';
import '../repository/task_view_screen.dart';
import 'new_task_screen.dart';

/// A new task from outside a repository: the app icon's quick action, or
/// text shared into the app ([text] fills the title and description). The
/// repository is the only clone, or the one chosen; the created task opens.
Future<void> startNewTask(
  NavigatorState navigator,
  WidgetRef ref, {
  String text = '',
}) async {
  final messenger = ScaffoldMessenger.maybeOf(navigator.context);
  final manager = await ref.read(repositoriesManagerProvider.future);
  final clones = await manager.clones();
  if (!navigator.mounted) return;
  if (clones.isEmpty) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Add a repository first, then its tasks.')),
    );
    return;
  }
  final record = clones.length == 1
      ? clones.single
      : await showModalBottomSheet<CloneRecord>(
          context: navigator.context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: Text(
                    'New task in…',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final clone in clones)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(clone.name),
                    subtitle: Text(clone.url),
                    onTap: () => Navigator.pop(context, clone),
                  ),
              ],
            ),
          ),
        );
  if (record == null) return;
  final session = await ref.read(sessionProvider(record).future);
  final created = await navigator.push<Task>(
    MaterialPageRoute(
      builder: (_) =>
          NewTaskScreen(record: record, session: session, text: text),
    ),
  );
  if (created == null) return;
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => TaskViewScreen(session: session, task: created),
    ),
  );
}
