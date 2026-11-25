/// Changing tasks from the phone ([[Call chains#c4-change-a-task]]), as
/// desktop's content manager does it (`createTask`, `updateTask`): the task
/// engine writes the file, [ContentWriter] commits it where the tasks live,
/// and the session reads the repository again for the screens to follow.
library;

import '../contracts/model.dart';
import '../engines/checkbox_engine.dart';
import '../engines/js.dart';
import '../engines/task_engine.dart';
import 'content_writer.dart';
import 'repository_model.dart';
import 'repository_session.dart';

/// The file changed since it was shown; reopen it to see the latest version.
class ChangedMeanwhileException implements Exception {
  const ChangedMeanwhileException([
    this.message =
        'This task changed meanwhile. Reopen it to see the latest version.',
  ]);

  final String message;

  @override
  String toString() => message;
}

class TaskWriter {
  TaskWriter({required this.session, required this.writer});

  final RepositorySession session;
  final ContentWriter writer;
  final _tasks = TaskEngine();

  RepositoryState get _state =>
      session.state ?? (throw StateError('The repository is not loaded yet.'));

  /// The task files there are, readable or not: for free IDs and epic spellings.
  List<String> _taskFiles() => [
    for (final task in _state.tasks) task.path,
    for (final problem in _state.problems) problem.path,
  ];

  /// [task] with [input]'s fields and description, committed as
  /// `Update <ID>: <title>`; another epic moves the file, which keeps its
  /// name. Throws [ChangedMeanwhileException] when the file is no longer the
  /// version [task] was read from, and [TaskException] for invalid input.
  Future<Task> update(Task task, TaskInput input) async {
    final state = _state;
    final settings = state.settings;
    final valid = _tasks.validate(input, settings.statuses);
    final original = await session.readText(task.path);
    if (fileHash(original) != task.hash) {
      throw const ChangedMeanwhileException();
    }
    final epic = _tasks.existingSpelling(
      valid.epic,
      _taskFiles(),
      settings.taskRoot,
    );
    final name = task.path.substring(task.path.lastIndexOf('/') + 1);
    final target = epic == task.epic
        ? task.path
        : _tasks.pathOf(
            settings.taskRoot,
            epic,
            name.substring(0, name.length - 3),
          );
    if (target != task.path && _taskFiles().contains(target)) {
      throw TaskException('$epic already has a task file named $name.');
    }
    final content = _tasks.serializeUpdate(original, valid);
    await writer.write(state, {
      if (target != task.path) task.path: null,
      target: content,
    }, 'Update ${task.id}: ${valid.title}');
    await session.load();
    return _tasks.parse(target, content, fileHash(content), settings.taskRoot);
  }

  /// [task] with the checkbox ticked whose item starts at [offset] in its
  /// description; null when no item starts there (the view was stale).
  Future<Task?> toggle(Task task, int offset) async {
    final body = toggleDescriptionCheckbox(task.body, offset);
    if (body == null) return null;
    return update(task, task.toInput().copyWith(body: body));
  }

  /// A new task with the next free ID of the task prefix, committed as
  /// `Create <ID>: <title>`.
  Future<Task> create(TaskInput input) async {
    final state = _state;
    final settings = state.settings;
    final valid = _tasks.validate(input, settings.statuses);
    final files = _taskFiles();
    // A free ID may still name a file in some epic, e.g. a task renamed on another branch.
    final fileNames = {
      for (final file in files)
        if (_tasks.isTaskFile(file, settings.taskRoot))
          file.substring(file.lastIndexOf('/') + 1),
    };
    final id = _tasks.nextId(settings.taskPrefix, [
      for (final task in state.tasks) task.id,
    ], (candidate) => fileNames.contains('$candidate.md'));
    final epic = _tasks.existingSpelling(valid.epic, files, settings.taskRoot);
    final path = _tasks.pathOf(settings.taskRoot, epic, id);
    final content = _tasks.serializeNew(id, valid);
    await writer.write(state, {path: content}, 'Create $id: ${valid.title}');
    await session.load();
    return _tasks.parse(path, content, fileHash(content), settings.taskRoot);
  }

  /// The name comments are signed with: the clone's Git name, as desktop's
  /// `author` makes it; refused while the clone has none.
  String commentAuthor() {
    final name = _tasks.commentAuthor(session.author ?? '');
    if (name.isEmpty) {
      throw TaskException(
        "Set the name your commits and comments are signed with first, in the repository's About.",
      );
    }
    return name;
  }

  /// [task] with a comment signed by the user, written now, after the others,
  /// committed as `Comment on <ID>`. Comments only ever go last, so the task
  /// needn't be the version shown, as on desktop.
  Future<Task> addComment(Task task, String text, {DateTime? now}) async {
    final comment = _tasks.validComment(text);
    final author = commentAuthor();
    final original = await session.readText(task.path);
    final current = _tasks.parse(
      task.path,
      original,
      fileHash(original),
      _state.settings.taskRoot,
    );
    final content = _tasks.addComment(
      original,
      author,
      now ?? DateTime.now(),
      comment,
    );
    return _writeTask(current, content, 'Comment on ${current.id}');
  }

  /// [task] with the text of comment [index] replaced, committed as
  /// `Edit a comment on <ID>`; only the user's own, in the version shown.
  Future<Task> editComment(Task task, int index, String text) async {
    final comment = _tasks.validComment(text);
    final original = await _ownComment(task, index);
    return _writeTask(
      task,
      _tasks.editComment(original, index, comment),
      'Edit a comment on ${task.id}',
    );
  }

  /// [task] without comment [index], committed as `Delete a comment on <ID>`;
  /// only the user's own, in the version shown.
  Future<Task> deleteComment(Task task, int index) async {
    final original = await _ownComment(task, index);
    return _writeTask(
      task,
      _tasks.removeComment(original, index),
      'Delete a comment on ${task.id}',
    );
  }

  /// Whether the user wrote [comment], as desktop decides it.
  bool isMine(TaskComment comment) {
    final name = _tasks.commentAuthor(session.author ?? '');
    return name.isNotEmpty && comment.author == name;
  }

  /// The file of [task] as shown, if comment [index] is the user's.
  Future<String> _ownComment(Task task, int index) async {
    final original = await session.readText(task.path);
    if (fileHash(original) != task.hash) {
      throw const ChangedMeanwhileException();
    }
    final current = _tasks.parse(
      task.path,
      original,
      task.hash,
      _state.settings.taskRoot,
    );
    if (index < 0 || index >= current.comments.length) {
      throw const ChangedMeanwhileException(
        'This comment no longer exists. Reopen the task to see the latest version.',
      );
    }
    if (current.comments[index].author != commentAuthor()) {
      throw TaskException('You can only change your own comments.');
    }
    return original;
  }

  Future<Task> _writeTask(Task task, String content, String message) async {
    await writer.write(_state, {task.path: content}, message);
    await session.load();
    return _tasks.parse(
      task.path,
      content,
      fileHash(content),
      _state.settings.taskRoot,
    );
  }

  /// What a new task of [type] starts with, from its template; null when
  /// the type has none.
  Future<TaskTemplate?> template(String type) async {
    if (type.isEmpty) return null;
    final String path;
    try {
      path = _tasks.templatePath(_state.settings.taskRoot, type);
    } on TaskException {
      return null;
    }
    final String content;
    try {
      content = await session.readText(path);
    } on Object {
      return null;
    }
    return _tasks.parseTemplate(content);
  }
}

/// A new task's input before anything is chosen (desktop's task-panel.ts `empty`).
TaskInput emptyDraft(String status, {String epic = ''}) => TaskInput(
  title: '',
  status: status,
  priority: 'none',
  assignee: '',
  labels: const [],
  body: '',
  epic: epic,
);

/// What a template put into a new task.
class FromTemplate {
  const FromTemplate({
    this.body,
    this.priority,
    this.assignee,
    this.labels,
    this.fields,
  });

  static const none = FromTemplate();

  final String? body;
  final String? priority;
  final String? assignee;
  final List<String>? labels;
  final Map<String, FieldValue>? fields;
}

/// [draft] with [template]'s description, unless someone wrote one already,
/// and its presets where the draft has none (desktop's `withTemplate`).
({TaskInput draft, FromTemplate applied}) withTemplate(
  TaskInput draft,
  TaskTemplate template,
) {
  final body = draft.body.trim().isEmpty && (template.body.isNotEmpty)
      ? template.body
      : null;
  final priority =
      draft.priority == 'none' &&
          (template.priority?.isNotEmpty ?? false) &&
          template.priority != 'none'
      ? template.priority
      : null;
  final assignee =
      draft.assignee.isEmpty && (template.assignee?.isNotEmpty ?? false)
      ? template.assignee
      : null;
  final labels = draft.labels.isEmpty && (template.labels?.isNotEmpty ?? false)
      ? template.labels
      : null;
  final fields = {
    for (final e in (template.fields ?? const <String, FieldValue>{}).entries)
      if ((draft.fields?[e.key] ?? '') == '') e.key: e.value,
  };
  final applied = FromTemplate(
    body: body,
    priority: priority,
    assignee: assignee,
    labels: labels,
    fields: fields.isEmpty ? null : fields,
  );
  return (
    draft: TaskInput(
      title: draft.title,
      status: draft.status,
      priority: priority ?? draft.priority,
      assignee: assignee ?? draft.assignee,
      labels: labels ?? draft.labels,
      body: body ?? draft.body,
      epic: draft.epic,
      type: draft.type,
      fields: {...?draft.fields, ...fields},
    ),
    applied: applied,
  );
}

/// [draft] without what a template put in, except what the user changed
/// since (desktop's `withoutTemplate`).
TaskInput withoutTemplate(TaskInput draft, FromTemplate applied) {
  bool same(Object? a, Object? b) => jsJson(a) == jsJson(b);
  return TaskInput(
    title: draft.title,
    status: draft.status,
    priority: applied.priority != null && same(draft.priority, applied.priority)
        ? 'none'
        : draft.priority,
    assignee: applied.assignee != null && same(draft.assignee, applied.assignee)
        ? ''
        : draft.assignee,
    labels: applied.labels != null && same(draft.labels, applied.labels)
        ? const []
        : draft.labels,
    body: applied.body != null && same(draft.body, applied.body)
        ? ''
        : draft.body,
    epic: draft.epic,
    type: draft.type,
    fields: draft.fields == null
        ? null
        : {
            for (final e in draft.fields!.entries)
              if (applied.fields == null ||
                  !applied.fields!.containsKey(e.key) ||
                  !same(applied.fields![e.key], e.value))
                e.key: e.value,
          },
  );
}
