/// The Genbeya merge for task files ([[Architecture#where-edits-go]]): when
/// a sync finds that a teammate and the phone changed the same task, the
/// two versions are merged the way the format was designed to merge, and
/// the merge gives up everywhere else.
///
/// - Fields three-way, one by one: the side that changed a field wins; both
///   changing it differently gives up. Labels merge as a set.
/// - The description: the side that changed it; both changing it gives up,
///   unless both only added time log entries, which are all kept.
/// - Comments, keyed by author, time and place: new ones from both sides in
///   time order; an edit or a deletion on one side applies; both touching
///   one comment differently gives up.
///
/// The result is written on top of the remote version with the task engine,
/// so its bytes are what Genbeya desktop writes for the merged task.
/// Genbeya desktop has no such merge (it stops for the user), so these rules
/// are this app's, and the tests in test/task_merge_test.dart pin them.
library;

import '../contracts/model.dart';
import 'js.dart';
import 'task_comments.dart';
import 'task_engine.dart';
import 'time_log.dart';

final _engine = TaskEngine();

/// Why a merge gave up: the file is left to the rescue branch.
class MergeConflict implements Exception {
  const MergeConflict(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// [base] the common ancestor, [remote] what the remote has, [local] the
/// phone's version; the merged file, or [MergeConflict].
String mergeTask({
  required String path,
  required String base,
  required String remote,
  required String local,
  required String taskRoot,
  required List<String> statuses,
}) {
  final Task b;
  final Task r;
  final Task l;
  try {
    b = _engine.parse(path, base, '', taskRoot);
    r = _engine.parse(path, remote, '', taskRoot);
    l = _engine.parse(path, local, '', taskRoot);
  } on TaskException catch (error) {
    throw MergeConflict('A version does not parse: ${error.message}');
  }
  if (r.id != l.id) throw const MergeConflict('Two different tasks.');

  T pick<T>(
    String what,
    T base,
    T remote,
    T local, [
    bool Function(T, T)? same,
  ]) {
    final equal = same ?? (T x, T y) => x == y;
    if (equal(local, base)) return remote;
    if (equal(remote, base) || equal(remote, local)) return local;
    throw MergeConflict('Both sides changed the $what.');
  }

  final fields = <String, FieldValue>{};
  final keys = {...b.fields.keys, ...r.fields.keys, ...l.fields.keys};
  for (final key in keys) {
    final value = pick<Object?>(
      'field $key',
      b.fields[key],
      r.fields[key],
      l.fields[key],
      (x, y) => jsJson(x) == jsJson(y),
    );
    if (value != null) fields[key] = value;
  }
  // Fields the merge drops are removed with an empty value, as the engine reads it.
  for (final key in r.fields.keys) {
    fields.putIfAbsent(key, () => '');
  }

  final input = TaskInput(
    title: pick('title', b.title, r.title, l.title),
    status: pick('status', b.status, r.status, l.status),
    priority: pick('priority', b.priority, r.priority, l.priority),
    assignee: pick('assignee', b.assignee, r.assignee, l.assignee),
    type: pick('type', b.type, r.type, l.type),
    labels: _labels(b.labels, r.labels, l.labels),
    body: _description(b.body, r.body, l.body),
    epic: r.epic,
    fields: fields,
  );
  final updated = _engine.serializeUpdate(
    remote,
    _engine.validate(input, statuses),
  );
  final blocks = _comments(_blocks(base), _blocks(remote), _blocks(local));
  return _engine.rewriteComments(updated, (_) => blocks);
}

/// The remote's labels, with those the phone added and without those it removed.
List<String> _labels(
  List<String> base,
  List<String> remote,
  List<String> local,
) {
  final added = local.where((x) => !base.contains(x) && !remote.contains(x));
  final removed = base.where((x) => !local.contains(x)).toSet();
  return [
    for (final label in remote)
      if (!removed.contains(label)) label,
    ...added,
  ];
}

String _description(String base, String remote, String local) {
  String norm(String text) => text.replaceAll(RegExp(r'\r\n?'), '\n').trim();
  if (norm(local) == norm(base)) return remote;
  if (norm(remote) == norm(base) || norm(remote) == norm(local)) return local;
  // Both changed: fine only when both just added time log entries.
  final b = splitTimeLog(base);
  final r = splitTimeLog(remote);
  final l = splitTimeLog(local);
  final sameText =
      norm(b.description) == norm(r.description) &&
      norm(b.description) == norm(l.description);
  bool onlyAdded(List<String> side) {
    final left = [...side];
    for (final line in b.lines) {
      if (!left.remove(line)) return false;
    }
    return true;
  }

  if (!sameText || !onlyAdded(r.lines) || !onlyAdded(l.lines)) {
    throw const MergeConflict('Both sides changed the description.');
  }
  final mine = [...l.lines];
  for (final line in b.lines) {
    mine.remove(line);
  }
  for (final line in r.lines) {
    mine.remove(line);
  }
  return appendTimeLogLines(remote, mine);
}

/// The comment blocks of a task file, keyed by author, date and place
/// among comments with both.
List<(String key, CommentBlock block)> _blocks(String file) {
  final raw = file.startsWith('﻿') ? file.substring(1) : file;
  final front = RegExp(r'^---\r?\n([\s\S]*?\r?\n)?---[ \t]*(?:\r?\n|$)')
      .firstMatch(raw);
  final body = front == null ? raw : raw.substring(front[0]!.length);
  final split = splitComments(body.replaceFirst(RegExp(r'^\r?\n'), ''));
  final seen = <String, int>{};
  return [
    for (final block in split.blocks)
      () {
        final key = '${block.comment.author}\n${block.comment.date}';
        final count = seen[key] ?? 0;
        seen[key] = count + 1;
        return ('$key\n$count', block);
      }(),
  ];
}

List<String> _comments(
  List<(String, CommentBlock)> base,
  List<(String, CommentBlock)> remote,
  List<(String, CommentBlock)> local,
) {
  final b = {for (final (k, block) in base) k: block.text};
  final r = {for (final (k, block) in remote) k: block.text};
  final l = {for (final (k, block) in local) k: block.text};
  final kept = <String>[];
  // Comments both sides started from: one side's edit or deletion applies.
  for (final (key, _) in base) {
    final text = (base: b[key], remote: r[key], local: l[key]);
    String? merged;
    if (text.local == text.base) {
      merged = text.remote;
    } else if (text.remote == text.base || text.remote == text.local) {
      merged = text.local;
    } else {
      throw const MergeConflict('Both sides changed the same comment.');
    }
    if (merged != null) kept.add(merged);
  }
  // New comments from both sides, in time order; the remote's first on a tie.
  final added = [
    for (final (key, block) in remote)
      if (!b.containsKey(key)) (block.comment.date, 0, block.text),
    for (final (key, block) in local)
      if (!b.containsKey(key) && !r.containsKey(key))
        (block.comment.date, 1, block.text),
  ];
  DateTime when(String date) =>
      DateTime.tryParse(date) ?? DateTime.fromMillisecondsSinceEpoch(0);
  final indexed = added.indexed.toList()
    ..sort((x, y) {
      final byTime = when(x.$2.$1).compareTo(when(y.$2.$1));
      if (byTime != 0) return byTime;
      final bySide = x.$2.$2 - y.$2.$2;
      return bySide != 0 ? bySide : x.$1 - y.$1;
    });
  return [...kept, for (final (_, item) in indexed) item.$3];
}
