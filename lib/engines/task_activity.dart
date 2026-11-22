/// What changed about a task between two versions of its file, for its
/// activity. Port of Genbeya's `src/engines/task-activity.ts`.
library;

import '../contracts/model.dart';

/// A version of a task as far as its activity is concerned.
class TaskState {
  const TaskState({
    required this.title,
    required this.type,
    required this.status,
    required this.priority,
    required this.assignee,
    required this.epic,
    required this.labels,
    required this.description,
    required this.comments,
    required this.timeLog,
    required this.fields,
    required this.other,
  });

  final String title;
  final String type;
  final String status;
  final String priority;
  final String assignee;
  final String epic;
  final List<String> labels;
  final String description;
  final List<TaskComment> comments;

  /// The time log's entries as written; the description is without them.
  final List<String> timeLog;

  /// Custom fields with a plain value, by name, as text.
  final Map<String, String> fields;

  /// Other frontmatter fields, by name, as JSON.
  final Map<String, String> other;

  String field(String name) => switch (name) {
    'title' => title,
    'type' => type,
    'status' => status,
    'priority' => priority,
    'assignee' => assignee,
    _ => epic,
  };
}

/// A change between two versions of a task, as Genbeya's `TaskChange`.
typedef TaskChange = Map<String, Object?>;

const _fields = ['title', 'type', 'status', 'priority', 'assignee', 'epic'];

/// The names of the entries that differ between [before] and [after], sorted.
List<String> _changedNames(
  Map<String, String> before,
  Map<String, String> after,
) => ({
  ...before.keys,
  ...after.keys,
}.toList()..sort()).where((name) => before[name] != after[name]).toList();

/// Entries added to a time log and how many left it, each line counted as
/// often as it is there; null when it didn't change.
TaskChange? _timeLogChange(List<String> before, List<String> after) {
  final left = [...before];
  final added = <String>[];
  for (final line in after) {
    final at = left.indexOf(line);
    if (at < 0) {
      added.add(line.replaceFirst(RegExp(r'^[-*+]\s+'), ''));
    } else {
      left.removeAt(at);
    }
  }
  return added.isNotEmpty || left.isNotEmpty
      ? {'kind': 'timelog', 'added': added, 'removed': left.length}
      : null;
}

/// Text without its outer whitespace, with LF line breaks.
String _normalized(String text) =>
    text.replaceAll(RegExp(r'\r\n?'), '\n').trim();

/// Comment texts by author, date and place among the comments with both.
Map<String, String> _keyed(List<TaskComment> comments) {
  final seen = <String, int>{};
  return {
    for (final comment in comments)
      () {
        final key = '${comment.author}\n${comment.date}';
        final count = seen[key] ?? 0;
        seen[key] = count + 1;
        return '$key\n$count';
      }(): comment.body,
  };
}

List<TaskChange> _commentChanges(
  List<TaskComment> before,
  List<TaskComment> after,
) {
  final old = _keyed(before);
  final now = _keyed(after);
  final added = now.keys.where((key) => !old.containsKey(key)).length;
  final edited = now.entries
      .where((e) => old.containsKey(e.key) && old[e.key] != e.value)
      .length;
  final removed = old.keys.where((key) => !now.containsKey(key)).length;
  return added > 0 || edited > 0 || removed > 0
      ? [
          {
            'kind': 'comments',
            'added': added,
            'edited': edited,
            'removed': removed,
          },
        ]
      : [];
}

/// The changes from [before] to [after]; a task without a [before] was created.
List<TaskChange> diffTasks(TaskState? before, TaskState after) {
  if (before == null) {
    return [
      {'kind': 'created'},
    ];
  }
  final changes = <TaskChange>[
    for (final field in _fields)
      if (before.field(field) != after.field(field))
        {
          'kind': 'field',
          'field': field,
          'from': before.field(field),
          'to': after.field(field),
        },
  ];
  final added = after.labels.where((l) => !before.labels.contains(l)).toList();
  final removed = before.labels
      .where((l) => !after.labels.contains(l))
      .toList();
  if (added.isNotEmpty || removed.isNotEmpty) {
    changes.add({'kind': 'labels', 'added': added, 'removed': removed});
  }
  if (_normalized(before.description) != _normalized(after.description)) {
    changes.add({'kind': 'description'});
  }
  changes.addAll(_commentChanges(before.comments, after.comments));
  final logged = _timeLogChange(before.timeLog, after.timeLog);
  if (logged != null) changes.add(logged);
  for (final field in _changedNames(before.fields, after.fields)) {
    changes.add({
      'kind': 'custom',
      'field': field,
      'from': before.fields[field] ?? '',
      'to': after.fields[field] ?? '',
    });
  }
  final other = _changedNames(before.other, after.other);
  if (other.isNotEmpty) changes.add({'kind': 'other', 'fields': other});
  return changes;
}
