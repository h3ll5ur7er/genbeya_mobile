/// How tasks are ordered, filtered, grouped and labelled on the list and the
/// board: a port of Genbeya's `src/client/app/features/tasks/task-model.ts`
/// and the due dates of `due-dates.ts`, so the phone shows the same order
/// and the same filters as the desktop.
library;

import '../contracts/model.dart';
import '../engines/collation.dart';
import '../engines/people.dart';

const priorities = ['urgent', 'high', 'medium', 'low', 'none'];

/// An assignee filter for tasks nobody has.
const unassigned = '-';

class TaskFilters {
  const TaskFilters({
    this.query = '',
    this.assignee,
    this.label,
    this.priority,
    this.epic,
    this.type,
    this.milestone,
  });

  final String query;

  /// An assignee, [unassigned], or null for everyone.
  final String? assignee;
  final String? label;
  final String? priority;

  /// An epic, '' for tasks without one, or null for all.
  final String? epic;

  /// A task type, '' for tasks without one, or null for all.
  final String? type;

  /// A milestone, '' for tasks without one, or null for all.
  final String? milestone;

  bool get isEmpty =>
      query.trim().isEmpty &&
      assignee == null &&
      label == null &&
      priority == null &&
      epic == null &&
      type == null &&
      milestone == null;

  TaskFilters copyWith({
    String? query,
    String? Function()? assignee,
    String? Function()? label,
    String? Function()? priority,
    String? Function()? epic,
    String? Function()? type,
    String? Function()? milestone,
  }) => TaskFilters(
    query: query ?? this.query,
    assignee: assignee == null ? this.assignee : assignee(),
    label: label == null ? this.label : label(),
    priority: priority == null ? this.priority : priority(),
    epic: epic == null ? this.epic : epic(),
    type: type == null ? this.type : type(),
    milestone: milestone == null ? this.milestone : milestone(),
  );
}

/// "in-progress" → "In progress".
String titleCase(String text) {
  final spaced = text.replaceAll(RegExp(r'[-_]+'), ' ');
  return spaced.isEmpty
      ? spaced
      : spaced[0].toUpperCase() + spaced.substring(1);
}

/// Generated UUIDs are shortened; readable IDs are shown whole.
String displayId(String id) =>
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-', caseSensitive: false).hasMatch(id)
    ? id.substring(0, 8)
    : id;

/// An epic's name for people: its folder path, or "No epic".
String epicName(String epic) => epic.isEmpty ? 'No epic' : epic;

/// The milestone a task counts towards, '' for none (planning.ts `milestoneOf`).
String milestoneOf(Task task) {
  final value = task.fields['milestone'];
  return value == null ? '' : '$value'.trim();
}

int _priorityRank(String priority) {
  final index = priorities.indexOf(priority);
  return index < 0 ? priorities.length : index;
}

int _numberOf(String id) =>
    int.tryParse(RegExp(r'(\d+)$').firstMatch(id)?.group(1) ?? '0') ?? 0;

/// Highest priority first, then the newest numbered task.
int compareTasks(Task a, Task b) {
  final byPriority = _priorityRank(a.priority) - _priorityRank(b.priority);
  if (byPriority != 0) return byPriority;
  final byNumber = _numberOf(b.id) - _numberOf(a.id);
  if (byNumber != 0) return byNumber;
  return collateFull(a.title, b.title);
}

/// Who an assignee is: the same for every way of writing them.
typedef Identify = String Function(String assignee);

/// Identifies assignees by person: a handle, a name or an email of the same
/// person are one.
Identify identifyBy(List<Person> people) {
  final index = PeopleIndex(people);
  return (assignee) => index.find(assignee)?.handle ?? assignee;
}

String _asWritten(String assignee) => assignee;

/// Tasks matching the filters, sorted.
List<Task> visibleTasks(
  List<Task> tasks,
  TaskFilters filters, {
  Identify identify = _asWritten,
}) {
  final assignee = filters.assignee != null && filters.assignee != unassigned
      ? identify(filters.assignee!)
      : null;
  final query = filters.query.trim().toLowerCase();
  final shown = tasks.where((task) {
    if (query.isNotEmpty &&
        ![
          task.id,
          task.title,
          task.assignee,
          ...task.labels,
        ].join(' ').toLowerCase().contains(query)) {
      return false;
    }
    if (filters.assignee != null &&
        !((assignee != null &&
                task.assignee.isNotEmpty &&
                identify(task.assignee) == assignee) ||
            (filters.assignee == unassigned && task.assignee.isEmpty))) {
      return false;
    }
    if (filters.label != null && !task.labels.contains(filters.label)) {
      return false;
    }
    if (filters.priority != null && task.priority != filters.priority) {
      return false;
    }
    if (filters.epic != null && task.epic != filters.epic) return false;
    if (filters.type != null && task.type != filters.type) return false;
    if (filters.milestone != null && milestoneOf(task) != filters.milestone) {
      return false;
    }
    return true;
  }).toList();
  stableSort(shown, compareTasks);
  return shown;
}

/// The configured states, then any other states tasks are in (shown so
/// they can be moved out).
List<String> columnsOf(List<String> statuses, List<Task> tasks) => [
  ...statuses,
  ...{
    for (final task in tasks)
      if (!statuses.contains(task.status)) task.status,
  },
];

/// The assignees of tasks, once per person; JavaScript's default sort.
List<String> peopleOf(List<Task> tasks, {Identify identify = _asWritten}) => {
  for (final task in tasks)
    if (task.assignee.isNotEmpty) identify(task.assignee),
}.toList()..sort();

List<String> labelsOf(List<Task> tasks) =>
    {for (final task in tasks) ...task.labels}.toList()..sort();

/// The milestones tasks count towards, sorted.
List<String> milestonesOf(List<Task> tasks) => {
  for (final task in tasks)
    if (milestoneOf(task).isNotEmpty) milestoneOf(task),
}.toList()..sort();

int? _phaseOf(String epic) {
  final match = RegExp(r'^(\d+)(?: |$)').firstMatch(epic);
  return match == null ? null : int.parse(match[1]!);
}

/// Epics that start with a phase number by that number, then the others;
/// alphabetically among equals, so 2 comes before 10.
int compareEpics(String a, String b) {
  final phaseA = _phaseOf(a);
  final phaseB = _phaseOf(b);
  if (phaseA != phaseB) {
    if (phaseA == null) return 1;
    if (phaseB == null) return -1;
    return phaseA - phaseB;
  }
  return collateBase(a, b);
}

/// Epics that hold tasks, in [compareEpics] order.
List<String> epicsOf(List<Task> tasks) => stableSorted({
  for (final task in tasks)
    if (task.epic.isNotEmpty) task.epic,
}, compareEpics);

/// The configured type of this name, or the generic look of one that isn't.
TaskType typeLook(String name, List<TaskType> types) =>
    types.where((type) => type.name == name).firstOrNull ??
    TaskType(name: name, icon: genericTypeIcon);

/// The configured types, then other types that tasks have.
List<TaskType> typesOf(List<TaskType> types, List<Task> tasks) => [
  ...types,
  ...({
    for (final task in tasks)
      if (task.type.isNotEmpty && !types.any((t) => t.name == task.type))
        task.type,
  }.toList()..sort()).map((name) => typeLook(name, types)),
];

/// Swimlanes: every epic, then the tasks without one.
List<String> lanesOf(List<Task> tasks) => [...epicsOf(tasks), ''];

/// The colour of a state: grey first, green last, distinct ones between.
enum StatusTone { gray, blue, yellow, purple, orange, green, other }

StatusTone statusTone(int index, int count) {
  const middle = [
    StatusTone.blue,
    StatusTone.yellow,
    StatusTone.purple,
    StatusTone.orange,
  ];
  if (index < 0) return StatusTone.other;
  if (index == count - 1) return StatusTone.green;
  if (index == 0) return StatusTone.gray;
  return middle[(index - 1) % middle.length];
}

/// A label's hue, as the desktop picks it (`labelColor`).
int labelHue(String label) {
  const hues = [250, 160, 25, 210, 320, 45, 280, 185];
  var hash = 0;
  for (final unit in label.codeUnits) {
    hash = (hash * 33 + unit).toSigned(32);
  }
  return hues[hash.abs() % hues.length];
}

// ---------- Due dates ----------

/// Open work due within this many days is due soon.
const dueSoonDays = 2;

enum DueTone { overdue, soon }

int? _dayNumber(String iso) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
}

bool isDate(String iso) => _dayNumber(iso) != null;

/// Today on this phone's calendar.
String today([DateTime? now]) {
  final time = now ?? DateTime.now();
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${pad(time.month)}-${pad(time.day)}';
}

/// How urgent open work due on [iso] is [on]; null when not due yet, or done.
DueTone? dueTone(String iso, String on, {bool done = false}) {
  if (done) return null;
  final days = _dayNumber(iso)! - _dayNumber(on)!;
  return days < 0
      ? DueTone.overdue
      : (days <= dueSoonDays ? DueTone.soon : null);
}

typedef DueDate = ({String field, String date, DueTone? tone});

/// The task's date fields, overdue once passed and due soon when near,
/// until the task reaches the last workflow state.
List<DueDate> dueDatesOf(Task task, Settings settings, String on) {
  final done =
      settings.statuses.isNotEmpty && task.status == settings.statuses.last;
  return [
    for (final field in settings.fields)
      if (field.type == 'date' && isDate('${task.fields[field.name] ?? ''}'))
        (
          field: field.name,
          date: '${task.fields[field.name]}',
          tone: dueTone('${task.fields[field.name]}', on, done: done),
        ),
  ];
}
