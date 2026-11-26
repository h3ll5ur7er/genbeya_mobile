/// **Today** ([[Experience#today]]): what needs the user, computed from the
/// files. "Me" is the person the clone's Git identity matches
/// (`RepositoryState.me`). Uses Genbeya's own rules: mentions as its
/// renderer finds them (`mentionPattern`, aliases included), dates as its
/// `remarkDates` finds them, and due as `dueTone` says.
library;

import '../contracts/model.dart';
import '../engines/collation.dart';
import '../engines/people.dart';
import 'repository_model.dart';
import 'search.dart';
import 'task_views.dart';

/// A date on its own: not part of a word, number, path, version or timestamp
/// (Genbeya's `DATE` in src/client/app/markdown/dates.ts).
final _date = RegExp(
  r'(?<![\p{L}\p{N}_/\\.:-])(\d{4}-\d{2}-\d{2})(?![\p{L}\p{N}_]|[-/:.][\p{L}\p{N}])',
  unicode: true,
);

/// An open task list item and its text.
final _openItem = RegExp(r'^\s*(?:>\s*)*(?:[-*+]|\d{1,9}[.)])\s+\[ \]\s+(.*)$');
final _fence = RegExp(r'^\s*(```|~~~)');

/// A task assigned to the user that isn't done, with its nearest due date.
typedef TodayTask = ({Task task, String? due, DueTone? tone});

/// Where the user is mentioned: a comment (with its date), a task's
/// description or a page.
typedef TodayMention = ({
  String kind,
  String path,
  String title,
  String text,
  String? date,
});

/// An open checklist item with a date, in the user's tasks or mentioning them.
typedef TodayItem = ({
  String path,
  String title,
  String text,
  String date,
  DueTone? tone,
});

class Today {
  const Today({
    required this.me,
    required this.tasks,
    required this.mentions,
    required this.checklist,
  });

  /// Who the user is among the repository's people; null when the identity
  /// matches no one, and then the rest is empty.
  final Person? me;
  final List<TodayTask> tasks;
  final List<TodayMention> mentions;
  final List<TodayItem> checklist;

  bool get isEmpty => tasks.isEmpty && mentions.isEmpty && checklist.isEmpty;
}

/// At most this many mentions are listed.
const todayMentionLimit = 30;

/// Today for [state] [on] a day (`YYYY-MM-DD`). [pageHits] are the wiki's
/// lines a search for `@handle` found (the session's `search`); tasks are
/// read from the model.
Today buildToday(
  RepositoryState state, {
  required String on,
  List<ContentHit> pageHits = const [],
}) {
  final people = PeopleIndex(state.people);
  final me = state.people.where((p) => p.handle == state.me).firstOrNull;
  if (me == null) {
    return const Today(me: null, tasks: [], mentions: [], checklist: []);
  }
  final settings = state.settings;
  final statuses = settings.statuses;
  final done = statuses.isEmpty ? null : statuses.last;
  bool mentionsMe(String text) => mentionPattern
      .allMatches(text)
      .any((m) => people.mentioned(m[1]!)?.handle == me.handle);
  bool mine(Task task) =>
      task.assignee.isNotEmpty &&
      people.find(task.assignee)?.handle == me.handle;

  // My open tasks: furthest along first, then due, then as the board sorts.
  final tasks = <TodayTask>[
    for (final task in state.tasks)
      if (mine(task) && task.status != done)
        () {
          final dates = dueDatesOf(task, settings, on)
            ..sort((a, b) => a.date.compareTo(b.date));
          final first = dates.firstOrNull;
          return (task: task, due: first?.date, tone: first?.tone);
        }(),
  ];
  tasks.sort((a, b) {
    final byStatus =
        statuses.indexOf(b.task.status) - statuses.indexOf(a.task.status);
    if (byStatus != 0) return byStatus;
    if (a.due != b.due) {
      if (a.due == null) return 1;
      if (b.due == null) return -1;
      return a.due!.compareTo(b.due!);
    }
    return compareTasks(a.task, b.task);
  });

  // Mentions: others' comments with their dates, newest first; then descriptions and pages.
  final dated = <TodayMention>[];
  final undated = <TodayMention>[];
  final checklist = <TodayItem>[];
  String taskTitle(Task task) => '${displayId(task.id)} ${task.title}';
  for (final task in state.tasks) {
    for (final comment in task.comments) {
      final line = comment.body.split('\n').where(mentionsMe).firstOrNull;
      if (line != null && people.find(comment.author)?.handle != me.handle) {
        dated.add((
          kind: 'comment',
          path: task.path,
          title: taskTitle(task),
          text: '${comment.author}: ${line.trim()}',
          date: comment.date,
        ));
      }
    }
    final lines = _prose(task.body);
    final mentioning = lines.where(mentionsMe).firstOrNull;
    if (mentioning != null) {
      undated.add((
        kind: 'task',
        path: task.path,
        title: taskTitle(task),
        text: mentioning.trim(),
        date: null,
      ));
    }
    if (task.status == done) continue;
    final assigned = mine(task);
    for (final line in lines) {
      final item = _openItem.firstMatch(line)?[1];
      if (item == null || !(assigned || mentionsMe(item))) continue;
      final date = _firstDate(item);
      if (date == null) continue;
      checklist.add((
        path: task.path,
        title: taskTitle(task),
        text: item.trim(),
        date: date,
        tone: dueTone(date, on),
      ));
    }
  }
  for (final hit in pageHits) {
    final lines = [
      for (final match in hit.matches)
        if (mentionsMe(match.text)) match.text,
    ];
    if (lines.isEmpty) continue;
    undated.add((
      kind: 'page',
      path: hit.path,
      title: hit.title,
      text: lines.first.trim(),
      date: null,
    ));
    for (final line in lines) {
      final item = _openItem.firstMatch(line)?[1];
      final date = item == null ? null : _firstDate(item);
      if (item == null || date == null) continue;
      checklist.add((
        path: hit.path,
        title: hit.title,
        text: item.trim(),
        date: date,
        tone: dueTone(date, on),
      ));
    }
  }
  // Comment dates carry their offsets: compared as times, not as text.
  DateTime? at(String date) => DateTime.tryParse(date);
  dated.sort((a, b) {
    final (x, y) = (at(a.date!), at(b.date!));
    return x != null && y != null ? y.compareTo(x) : b.date!.compareTo(a.date!);
  });
  checklist.sort((a, b) => a.date.compareTo(b.date));
  final mentions = [
    ...dated,
    ...stableSorted(undated, (a, b) => collate(a.title, b.title)),
  ].take(todayMentionLimit).toList();
  return Today(me: me, tasks: tasks, mentions: mentions, checklist: checklist);
}

/// The lines of Markdown outside fenced code.
List<String> _prose(String markdown) {
  final lines = <String>[];
  var fenced = false;
  for (final line in markdown.split('\n')) {
    if (_fence.hasMatch(line)) {
      fenced = !fenced;
      continue;
    }
    if (!fenced) lines.add(line.replaceFirst(RegExp(r'\r$'), ''));
  }
  return lines;
}

String? _firstDate(String text) {
  final dates = [
    for (final m in _date.allMatches(text))
      if (isDate(m[1]!)) m[1]!,
  ]..sort();
  return dates.firstOrNull;
}
