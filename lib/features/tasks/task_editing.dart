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

/// What a change needs from the screen that asked for it, taken when it
/// was asked: the change goes on when the user has left the screen
/// meanwhile, as after ticking a checkbox and going back at once.
class EditScope {
  EditScope(BuildContext context)
    : container = ProviderScope.containerOf(context, listen: false),
      messenger = ScaffoldMessenger.of(context),
      _context = context;

  final ProviderContainer container;
  final ScaffoldMessengerState messenger;
  final BuildContext _context;

  /// The screen, while it is still there: for questions to ask.
  BuildContext? get context => _context.mounted ? _context : null;

  void say(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));
}

/// Runs a task change for [record] ([changeContent]).
Future<Task?> changeTask(
  EditScope scope,
  CloneRecord record,
  RepositorySession session,
  Future<Task?> Function(TaskWriter tasks) change,
) => changeContent(scope, record, session, 'tasks', () async {
  final tasks = await scope.container.read(taskWriterProvider(record).future);
  return change(tasks);
});

/// Runs a change to [area] of [record]: on the first edit of an area kept
/// in the checkout, asks where the commits go ([askWhereCommitsGo]); then
/// the change, whose problems are shown in a snack bar. What it returned,
/// or null when it didn't happen.
Future<T?> changeContent<T>(
  EditScope scope,
  CloneRecord record,
  RepositorySession session,
  String area,
  Future<T?> Function() change,
) async {
  try {
    if (!await askWhereCommitsGo(scope, record, session, area)) {
      return null;
    }
    return await change();
  } on ChangedMeanwhileException catch (error) {
    scope.say(error.message);
  } on TaskException catch (error) {
    scope.say(error.message);
  } on Object catch (error) {
    scope.say("Couldn't save: $error");
  }
  return null;
}

/// Where commits go ([[Architecture#where-edits-go]], D5): an area on the
/// content branch is committed there, nothing to ask. One in the
/// checkout is committed to the checked-out branch; the first time, the
/// user chooses it or a branch of their own, `mobile/<handle>`. False when
/// they cancelled, or left the screen before they could be asked.
Future<bool> askWhereCommitsGo(
  EditScope scope,
  CloneRecord record,
  RepositorySession session, [
  String area = 'tasks',
]) async {
  final state = session.state!;
  final onBranch =
      state.place.branch != null &&
      state.place.areas[area] == StorageMode.branch;
  if (onBranch) return true;
  final manager = await scope.container.read(
    repositoriesManagerProvider.future,
  );
  if (await manager.commitsChosen(record.id)) return true;
  final work = await scope.container.read(workProvider(record).future);
  final branch = (await work.git.head()).branch;
  if (branch == null) return false;
  final context = scope.context;
  if (context == null || !context.mounted) {
    scope.say(
      'Not saved: where your edits go needs your answer first. Try again.',
    );
    return false;
  }
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
    scope.say('Your edits go to $name, pushed with sync.');
  }
  await manager.markCommitsChosen(record.id);
  return true;
}
