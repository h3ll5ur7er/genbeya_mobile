import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../contracts/clones.dart';
import '../../contracts/model.dart';
import '../../engines/content_layout.dart';
import '../../engines/task_engine.dart';
import '../../managers/repository_session.dart';
import '../../managers/page_writer.dart';
import '../../managers/task_writer.dart';
import '../repositories/providers.dart';
import '../repository/session_provider.dart';
import '../repository/work_provider.dart';

/// A clone's task writer.
final taskWriterProvider = FutureProvider.family<TaskWriter, CloneRecord>((
  ref,
  record,
) async {
  final session = await ref.watch(sessionProvider(record).future);
  final work = await ref.watch(workProvider(record).future);
  return TaskWriter(session: session, writer: work.writer);
});

/// A clone's page writer.
final pageWriterProvider = FutureProvider.family<PageWriter, CloneRecord>((
  ref,
  record,
) async {
  final session = await ref.watch(sessionProvider(record).future);
  final work = await ref.watch(workProvider(record).future);
  return PageWriter(session: session, writer: work.writer);
});

/// Runs a task change for [record] ([changeContent]).
Future<Task?> changeTask(
  BuildContext context,
  WidgetRef ref,
  CloneRecord record,
  RepositorySession session,
  Future<Task?> Function(TaskWriter tasks) change,
) => changeContent(context, ref, record, session, 'tasks', () async {
  final tasks = await ref.read(taskWriterProvider(record).future);
  return change(tasks);
});

/// Runs a change to [area] of [record]: on the first edit of an area kept
/// in the checkout, asks where the commits go ([askWhereCommitsGo]); then
/// the change, whose problems are shown in a snack bar. What it returned,
/// or null when it didn't happen.
Future<T?> changeContent<T>(
  BuildContext context,
  WidgetRef ref,
  CloneRecord record,
  RepositorySession session,
  String area,
  Future<T?> Function() change,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    if (!await askWhereCommitsGo(context, ref, record, session, area)) {
      return null;
    }
    return await change();
  } on ChangedMeanwhileException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
  } on TaskException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(content: Text("Couldn't save: $error")));
  }
  return null;
}

/// Where commits go ([[Architecture#where-edits-go]], D5): an area on the
/// content branch is committed there, nothing to ask. One in the
/// checkout is committed to the checked-out branch; the first time, the
/// user chooses it or a branch of their own, `mobile/<handle>`. False when
/// they cancelled.
Future<bool> askWhereCommitsGo(
  BuildContext context,
  WidgetRef ref,
  CloneRecord record,
  RepositorySession session, [
  String area = 'tasks',
]) async {
  final state = session.state!;
  final onBranch =
      state.place.branch != null &&
      state.place.areas[area] == StorageMode.branch;
  if (onBranch) return true;
  final manager = await ref.read(repositoriesManagerProvider.future);
  if (await manager.commitsChosen(record.id)) return true;
  final work = await ref.read(workProvider(record).future);
  final branch = (await work.git.head()).branch;
  if (branch == null || !context.mounted) return branch != null;
  final choice = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Where should your edits go?'),
      content: Text(
        '${area == 'tasks' ? 'Tasks' : 'The wiki'} in this repository ${area == 'tasks' ? 'live' : 'lives'} with the code, so each edit is a commit. '
        'They can go to $branch, which everyone works on, or to a branch of your own '
        'that you merge later, for example with a pull request.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('A branch of my own'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Commit to $branch'),
        ),
      ],
    ),
  );
  if (choice == null) return false;
  if (!choice) {
    final name = await work.sync.startOwnBranch();
    await session.load();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Your edits go to $name, pushed with sync.')),
      );
    }
  }
  await manager.markCommitsChosen(record.id);
  return true;
}
