/// The types every layer agrees on, mirroring Genbeya's `src/contracts/model.ts`
/// in names and JSON shape, so conformance cases compare one to one.
library;

const priorities = ['urgent', 'high', 'medium', 'low', 'none'];
const tones = ['gray', 'blue', 'green', 'yellow', 'orange', 'red', 'purple'];
const fieldTypes = ['text', 'number', 'date', 'choice', 'effort', 'tasks'];

/// The frontmatter keys Genbeya writes itself; custom fields use other names.
const taskKeys = [
  'id',
  'title',
  'type',
  'status',
  'priority',
  'assignee',
  'labels',
  'epic',
];
const weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const parts = [
  'wiki',
  'tasks',
  'planning',
  'timelog',
  'code',
  'changes',
  'history',
  'pulls',
  'terminal',
];

const genericTypeIcon = 'circle-dot';

const _knownTypes = <String, (String, String)>{
  'bug': ('bug', 'red'),
  'feature': ('sparkles', 'purple'),
  'improvement': ('trending-up', 'blue'),
  'chore': ('wrench', 'gray'),
  'task': ('square-check', 'blue'),
  'story': ('book-open', 'green'),
  'docs': ('file-text', 'green'),
  'question': ('circle-question-mark', 'yellow'),
  'research': ('flask-conical', 'orange'),
};

/// A kind of task, such as a bug. `icon` names a Lucide icon.
class TaskType {
  const TaskType({required this.name, required this.icon, this.tone});

  /// A type of this name with its usual icon and colour.
  factory TaskType.named(String name) {
    final known = _knownTypes[name.toLowerCase()];
    return known == null
        ? TaskType(name: name, icon: genericTypeIcon)
        : TaskType(name: name, icon: known.$1, tone: known.$2);
  }

  final String name;
  final String icon;
  final String? tone;

  Map<String, Object?> toJson() => {
    'name': name,
    'icon': icon,
    if (tone != null) 'tone': tone,
  };
}

/// A custom task field: a frontmatter key with an editor.
class FieldDefinition {
  const FieldDefinition({required this.name, required this.type, this.options});

  final String name;
  final String type;
  final List<String>? options;

  Map<String, Object?> toJson() => {
    'name': name,
    'type': type,
    if (options != null) 'options': options,
  };
}

/// A person as `.genbeya.yml` lists them.
class PersonEntry {
  const PersonEntry({
    required this.handle,
    required this.name,
    this.email,
    this.aliases,
  });

  final String handle;
  final String name;
  final String? email;
  final List<String>? aliases;

  Map<String, Object?> toJson() => {
    'handle': handle,
    'name': name,
    if (email != null) 'email': email,
    if (aliases != null) 'aliases': aliases,
  };
}

class Milestone {
  const Milestone({required this.name, required this.due});

  final String name;

  /// `YYYY-MM-DD`.
  final String due;

  Map<String, Object?> toJson() => {'name': name, 'due': due};
}

/// Project settings, stored in `.genbeya.yml`.
class Settings {
  const Settings({
    required this.name,
    required this.wikiRoot,
    required this.wikiHome,
    required this.taskRoot,
    required this.taskPrefix,
    required this.statuses,
    required this.statusIcons,
    required this.hiddenColumns,
    required this.types,
    required this.fields,
    required this.people,
    required this.pullRoot,
    required this.pullPrefix,
    required this.requiredApprovals,
    required this.todosBlockMerge,
    required this.unused,
    required this.workdays,
    required this.holidays,
    required this.milestones,
  });

  final String name;
  final String wikiRoot;
  final String wikiHome;
  final String taskRoot;
  final String taskPrefix;
  final List<String> statuses;
  final Map<String, String> statusIcons;
  final List<String> hiddenColumns;
  final List<TaskType> types;
  final List<FieldDefinition> fields;
  final List<PersonEntry> people;
  final String pullRoot;
  final String pullPrefix;
  final int requiredApprovals;
  final bool todosBlockMerge;
  final List<String> unused;
  final List<String> workdays;
  final List<String> holidays;
  final List<Milestone> milestones;

  Map<String, Object?> toJson() => {
    'name': name,
    'wikiRoot': wikiRoot,
    'wikiHome': wikiHome,
    'taskRoot': taskRoot,
    'taskPrefix': taskPrefix,
    'statuses': statuses,
    'statusIcons': statusIcons,
    'hiddenColumns': hiddenColumns,
    'types': [for (final t in types) t.toJson()],
    'fields': [for (final f in fields) f.toJson()],
    'people': [for (final p in people) p.toJson()],
    'pullRoot': pullRoot,
    'pullPrefix': pullPrefix,
    'requiredApprovals': requiredApprovals,
    'todosBlockMerge': todosBlockMerge,
    'unused': unused,
    'workdays': workdays,
    'holidays': holidays,
    'milestones': [for (final m in milestones) m.toJson()],
  };
}

/// A comment below a task's description.
class TaskComment {
  const TaskComment({
    required this.author,
    required this.date,
    required this.body,
  });

  final String author;

  /// ISO date and time, with the offset when the heading has one.
  final String date;
  final String body;

  Map<String, Object?> toJson() => {
    'author': author,
    'date': date,
    'body': body,
  };
}

/// The value of a custom field: a String, a num, a bool or a `List<String>`.
typedef FieldValue = Object;

class Task {
  const Task({
    required this.id,
    required this.path,
    required this.title,
    required this.status,
    required this.priority,
    required this.assignee,
    required this.labels,
    required this.type,
    required this.fields,
    required this.body,
    required this.epic,
    required this.hash,
    required this.comments,
  });

  final String id;
  final String path;
  final String title;
  final String status;
  final String priority;
  final String assignee;
  final List<String> labels;
  final String type;
  final Map<String, FieldValue> fields;
  final String body;
  final String epic;
  final String hash;
  final List<TaskComment> comments;

  Map<String, Object?> toJson() => {
    'id': id,
    'path': path,
    'title': title,
    'status': status,
    'priority': priority,
    'assignee': assignee,
    'labels': labels,
    'type': type,
    'fields': fields,
    'body': body,
    'epic': epic,
    'hash': hash,
    'comments': [for (final c in comments) c.toJson()],
  };

  /// What a client sends to change this task: everything, as `inputOf` does in
  /// Genbeya's task-model.ts.
  TaskInput toInput() => TaskInput(
    title: title,
    status: status,
    priority: priority,
    assignee: assignee,
    labels: labels,
    type: type,
    fields: fields,
    body: body,
    epic: epic,
  );
}

/// A task's editable properties, as clients send them.
class TaskInput {
  const TaskInput({
    required this.title,
    required this.status,
    required this.priority,
    required this.assignee,
    required this.labels,
    required this.body,
    required this.epic,
    this.type,
    this.fields,
  });

  final String title;
  final String status;
  final String priority;
  final String assignee;
  final List<String> labels;
  final String body;
  final String epic;

  /// Absent: the type stays as it is. Empty: the task has no type.
  final String? type;

  /// Absent: custom fields stay as they are. An empty string removes a field.
  final Map<String, FieldValue>? fields;

  TaskInput copyWith({
    String? title,
    String? status,
    String? priority,
    String? assignee,
    List<String>? labels,
    String? body,
    String? epic,
    String? type,
    Map<String, FieldValue>? fields,
  }) => TaskInput(
    title: title ?? this.title,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    assignee: assignee ?? this.assignee,
    labels: labels ?? this.labels,
    body: body ?? this.body,
    epic: epic ?? this.epic,
    type: type ?? this.type,
    fields: fields ?? this.fields,
  );
}
