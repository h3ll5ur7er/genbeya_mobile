/// The task file format: one Markdown file per task with YAML frontmatter, the
/// description, then the comments. Port of Genbeya's
/// `src/engines/task-engine.ts`: updates rewrite known fields in place and keep
/// the file's byte order mark and line endings; what they write is checked
/// against Genbeya by the conformance cases in `tool/conformance/`.
library;

import 'dart:math';

import '../contracts/model.dart';
import 'js.dart';
import 'repository_path.dart';
import 'settings_engine.dart' show typeName;
import 'task_activity.dart';
import 'time_log.dart';
import 'task_comments.dart';
import 'text_style.dart';
import 'yaml/yaml_document.dart';

final _frontmatter = RegExp(r'^---\r?\n([\s\S]*?\r?\n)?---[ \t]*(?:\r?\n|$)');
const _defaultPriority = 'none';
const _templateFolder = '.templates';

/// The headings new templates of a type start with; other types get the last.
const _outlines = {
  'bug': ['Steps to reproduce', 'Expected', 'Actual', 'Environment'],
  'feature': ['Goal', 'Proposal', 'Done when'],
  '': ['Context', 'Done when'],
};
const _limits = (
  title: 300,
  type: 40,
  priority: 40,
  assignee: 120,
  label: 60,
  labels: 30,
  body: 1024 * 1024,
  epic: 120,
  fields: 50,
  field: 100,
  value: 2000,
  comment: 64 * 1024,
  items: 100,
);
const _notFields = [...taskKeys, '__proto__', 'constructor', 'prototype'];

class TaskException implements Exception {
  TaskException(this.message, {this.fromYaml = false});

  final String message;

  /// The YAML itself is invalid; the parser's message, not Genbeya's.
  final bool fromYaml;

  @override
  String toString() => message;
}

Never _fail(String message) => throw TaskException(message);

bool _isFieldKey(String key) =>
    key.trim().isNotEmpty &&
    key.length <= _limits.field &&
    !RegExp(r'[\x00-\x1f\x7f]').hasMatch(key) &&
    !_notFields.contains(key.toLowerCase());

bool _isFieldValue(Object? value) =>
    value is String ||
    value is bool ||
    (value is num && value.isFinite) ||
    (value is List && value.every((item) => item is String));

class Frontmatter {
  const Frontmatter({
    required this.document,
    required this.data,
    required this.body,
  });

  final YDocument document;
  final Map<String, Object?> data;
  final String body;
}

/// A Markdown file's YAML frontmatter, as a document to edit and as data, and the text after it.
Frontmatter splitFrontmatter(String file) {
  final raw = withoutByteOrderMark(file);
  final match = _frontmatter.firstMatch(raw);
  final YDocument document;
  try {
    document = parseYamlDocument(match?.group(1) ?? '');
  } on YamlDocumentException catch (error) {
    throw TaskException(
      'Invalid YAML frontmatter: ${error.message}',
      fromYaml: true,
    );
  }
  final data = document.toData() ?? <String, Object?>{};
  if (data is! Map) _fail('Frontmatter must be a YAML mapping.');
  return Frontmatter(
    document: document,
    data: {for (final e in data.entries) e.key.toString(): e.value},
    body: match != null ? raw.substring(match[0]!.length) : raw,
  );
}

List<String> _toList(Object? value) => value is List
    ? [for (final v in value) jsString(v)]
    : value is String
    ? value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
    : <String>[];

Map<String, FieldValue> _extraFields(Map<String, Object?> data) => {
  for (final e in data.entries)
    if (_isFieldKey(e.key) && _isFieldValue(e.value))
      e.key: e.value as FieldValue,
};

/// Frontmatter fields in their written order; empty or default optional fields are left out.
List<(String, Object?)> _fieldsOf(TaskInput input) => [
  ('title', input.title),
  if (input.type != null) ('type', input.type!.isEmpty ? null : input.type),
  ('status', input.status),
  ('priority', input.priority == _defaultPriority ? null : input.priority),
  ('assignee', input.assignee.isEmpty ? null : input.assignee),
  ('labels', input.labels.isEmpty ? null : [...input.labels]),
];

/// A Markdown file of frontmatter and a body, the body's surrounding blank lines trimmed.
String compose(String frontmatter, String body) {
  final text = body.replaceFirst(RegExp(r'^\s*\n'), '').trimRight();
  return '---\n$frontmatter---\n${text.isNotEmpty ? '\n$text\n' : ''}';
}

/// Markdown files below the task folder, outside folders whose names start with a dot.
bool isTaskFile(String path, String taskRoot) => _isTaskFile(path, taskRoot);

bool _isTaskFile(String path, String taskRoot) =>
    within(path, taskRoot) &&
    path.toLowerCase().endsWith('.md') &&
    !path
        .substring(taskRoot.length + 1)
        .split('/')
        .any((part) => part.startsWith('.'));

class TaskEngine {
  /// `path` is the task file below `taskRoot`; its folder there is the task's epic.
  Task parse(String path, String content, String hash, String taskRoot) {
    final front = splitFrontmatter(content);
    final data = front.data;
    if (data['id'] == null || data['title'] == null || data['status'] == null) {
      _fail('A task needs id, title and status in its frontmatter.');
    }
    final split = splitComments(front.body.replaceFirst(RegExp(r'^\r?\n'), ''));
    return Task(
      id: jsString(data['id']),
      path: path,
      title: jsString(data['title']),
      status: jsString(data['status']),
      priority: jsString(data['priority'] ?? _defaultPriority),
      assignee: jsString(data['assignee'] ?? ''),
      labels: _toList(data['labels']),
      type: jsString(data['type'] ?? ''),
      fields: _extraFields(data),
      body: split.description,
      epic: epicOf(path, taskRoot),
      hash: hash,
      comments: [for (final block in split.blocks) block.comment],
    );
  }

  String epicOf(String path, String taskRoot) {
    if (!within(path, taskRoot)) return '';
    final below = path.substring(taskRoot.length + 1);
    return below.contains('/')
        ? below.substring(0, below.lastIndexOf('/'))
        : '';
  }

  /// Where the task `id` of `epic` lives.
  String pathOf(String taskRoot, String epic, String id) =>
      [taskRoot, if (epic.isNotEmpty) epic, '$id.md'].join('/');

  /// Checks and normalises client input against the project's workflow states.
  TaskInput validate(TaskInput input, List<String> statuses) {
    String text(String value, String label, int max) {
      if (value.length > max) _fail('Invalid $label.');
      return value;
    }

    String line(String value, String label, int max) =>
        text(value, label, max).replaceAll(RegExp(r'[\r\n]+'), ' ').trim();

    final title = line(input.title, 'title', _limits.title);
    if (title.isEmpty) _fail('A task needs a title.');
    if (!statuses.contains(input.status)) {
      _fail('Choose one of the configured workflow states.');
    }
    if (input.labels.length > _limits.labels) _fail('Use at most 30 labels.');
    final priority = line(input.priority, 'priority', _limits.priority);
    final labels = <String>[];
    for (final label
        in input.labels
            .map((l) => line(l, 'label', _limits.label))
            .where((l) => l.isNotEmpty)) {
      if (!labels.contains(label)) labels.add(label);
    }
    return TaskInput(
      title: title,
      status: input.status,
      priority: priority.isEmpty ? _defaultPriority : priority,
      assignee: line(input.assignee, 'assignee', _limits.assignee),
      labels: labels,
      body: protectHeadings(
        text(
          input.body,
          'description',
          _limits.body,
        ).replaceAll(RegExp(r'\r\n?'), '\n'),
      ),
      epic: _validEpic(input.epic),
      type: input.type == null ? null : line(input.type!, 'type', _limits.type),
      fields: input.fields == null ? null : _validFields(input.fields!),
    );
  }

  String _validEpic(String value) {
    if (value.length > _limits.epic) _fail('Invalid epic.');
    final parts = value
        .split('/')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    final epic = parts.join('/');
    if (epic.isEmpty) return '';
    try {
      if (parts.any((part) => part.startsWith('.'))) {
        throw const FormatException();
      }
      return validateRepositoryPath(epic, false);
    } on FormatException {
      _fail('"$epic" is not a valid epic name.');
    }
  }

  Map<String, FieldValue> _validFields(Map<String, FieldValue> value) {
    if (value.length > _limits.fields) _fail('Invalid fields.');
    for (final entry in value.entries) {
      if (!_isFieldKey(entry.key)) _fail('Invalid field ${entry.key}.');
      final field = entry.value;
      bool tooLong(String text) => text.length > _limits.value;
      if (!_isFieldValue(field) ||
          (field is String && tooLong(field)) ||
          (field is List &&
              (field.length > _limits.items ||
                  field.cast<String>().any(tooLong)))) {
        _fail('Invalid value of ${entry.key}.');
      }
    }
    return {...value};
  }

  /// `original` with the fields and description of `input`; its comments stay
  /// as they are, and so do fields that `input` does not name.
  /// A comment's text, checked and normalised.
  String validComment(String value) {
    if (value.length > _limits.comment) _fail('Invalid comment.');
    final text = value.replaceAll(RegExp(r'\r\n?'), '\n').trim();
    if (text.isEmpty) _fail('Write a comment first.');
    return protectHeadings(text);
  }

  /// A person's name as comments are signed with it: one line, bounded.
  String commentAuthor(String name) {
    final line = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    return line.length > _limits.assignee
        ? line.substring(0, _limits.assignee)
        : line;
  }

  /// [original] with a comment by [author], written at [date], after the others.
  String addComment(
    String original,
    String author,
    DateTime date,
    String text,
  ) {
    final heading = commentHeading(commentAuthor(author), timestampOf(date));
    return rewriteComments(
      original,
      (body) => [
        for (final block in body.blocks) block.text,
        commentBlock(heading, text),
      ],
    );
  }

  /// [original] with the text of comment [index] replaced; its author and date stay.
  String editComment(String original, int index, String text) =>
      rewriteComments(
        original,
        (body) => [
          for (final (i, block) in body.blocks.indexed)
            i == index ? commentBlock(block.heading, text) : block.text,
        ],
        index: index,
      );

  String removeComment(String original, int index) => rewriteComments(
    original,
    (body) => [
      for (final (i, block) in body.blocks.indexed)
        if (i != index) block.text,
    ],
    index: index,
  );

  /// [original] with the comment texts [change] makes of its comments; the
  /// frontmatter and description stay as written. [index] must name a
  /// comment. Genbeya's `withComments`.
  String rewriteComments(
    String original,
    List<String> Function(SplitBody body) change, {
    int? index,
  }) {
    final raw = withoutByteOrderMark(original);
    final frontmatter = _frontmatter.firstMatch(raw);
    if (frontmatter == null) {
      _fail('A task needs id, title and status in its frontmatter.');
    }
    final body = splitComments(
      raw.substring(frontmatter[0]!.length).replaceFirst(RegExp(r'^\r?\n'), ''),
    );
    if (index != null && (index < 0 || index >= body.blocks.length)) {
      _fail(
        'This comment no longer exists. Reopen the task to see the latest version.',
      );
    }
    final text = joinComments(body.description, change(body));
    return applyTextStyle(
      '${frontmatter[0]!.trimRight()}\n${text.isEmpty ? '' : '\n$text'}',
      textStyleOf(original),
    );
  }

  /// What changed about a task from [before] (null: it did not exist) to
  /// [after]. A version's content is null where Git didn't show it (a move
  /// without edits).
  List<TaskChange> changesBetween(
    ({String path, String? content})? before,
    ({String path, String? content}) after,
    String taskRoot,
  ) {
    if (before?.content == null || after.content == null) {
      if (before == null) {
        return [
          {'kind': 'created'},
        ];
      }
      final from = epicOf(before.path, taskRoot);
      final to = epicOf(after.path, taskRoot);
      return from == to
          ? []
          : [
              {'kind': 'field', 'field': 'epic', 'from': from, 'to': to},
            ];
    }
    return diffTasks(
      _stateOf(before!.path, before.content!, taskRoot),
      _stateOf(after.path, after.content!, taskRoot),
    );
  }

  /// A version of a task as its activity sees it; broken frontmatter reads as empty.
  TaskState _stateOf(String path, String content, String taskRoot) {
    var data = <String, Object?>{};
    var body = content;
    try {
      final front = splitFrontmatter(content);
      data = front.data;
      body = front.body;
    } on TaskException {
      // Old versions may be broken; their body still counts.
    }
    final split = splitComments(body.replaceFirst(RegExp(r'^\r?\n'), ''));
    // Logging time changes the time log, not the description.
    final log = splitTimeLog(split.description);
    String text(String key, [String fallback = '']) =>
        data[key] == null ? fallback : jsString(data[key]);
    final fields = _extraFields(data);
    return TaskState(
      title: text('title'),
      type: text('type'),
      status: text('status'),
      priority: text('priority', _defaultPriority),
      assignee: text('assignee'),
      epic: epicOf(path, taskRoot),
      labels: _toList(data['labels']),
      description: log.description,
      comments: [for (final block in split.blocks) block.comment],
      timeLog: log.lines,
      fields: {
        for (final e in fields.entries)
          e.key: e.value is List
              ? (e.value as List).join(', ')
              : jsString(e.value),
      },
      other: {
        for (final e in data.entries)
          if (!_notFields.contains(e.key) && !fields.containsKey(e.key))
            e.key: jsJson(e.value),
      },
    );
  }

  /// Markdown files below the task folder, outside folders whose names start with a dot.
  bool isTaskFile(String path, String taskRoot) => _isTaskFile(path, taskRoot);

  String templatePath(String taskRoot, String type) {
    if (!typeName.hasMatch(type)) _fail('Invalid task type.');
    return '$taskRoot/$_templateFolder/$type.md';
  }

  /// The description of a template, and the fields its frontmatter presets
  /// (not id, title, type or status).
  TaskTemplate parseTemplate(String content) {
    final front = splitFrontmatter(content);
    final data = front.data;
    final fields = _extraFields(data);
    return TaskTemplate(
      body: front.body.replaceFirst(RegExp(r'^\r?\n'), ''),
      priority: data['priority'] == null ? null : jsString(data['priority']),
      assignee: data['assignee'] == null ? null : jsString(data['assignee']),
      labels: data['labels'] == null ? null : _toList(data['labels']),
      fields: fields.isEmpty ? null : fields,
    );
  }

  /// A first template for a type, to edit in Genbeya.
  String newTemplate(String type) => [
    '---',
    '# New $type tasks start with the description below. Fields here, such as',
    '# priority, assignee, labels or custom fields, preset theirs too.',
    '---',
    '',
    for (final heading in _outlines[type.toLowerCase()] ?? _outlines['']!) ...[
      '## $heading',
      '',
    ],
  ].join('\n');

  /// [epic] spelled like the existing epic folders among [files] that differ
  /// from it only in case, folder by folder: Windows and macOS see one folder
  /// in both spellings.
  String existingSpelling(String epic, List<String> files, String taskRoot) {
    final folders = <String, String>{};
    for (final file in files) {
      final parts = epicOf(file, taskRoot).split('/');
      for (
        var length = 1;
        length <= parts.length && parts[0].isNotEmpty;
        length++
      ) {
        final folder = parts.sublist(0, length).join('/');
        folders.putIfAbsent(folder.toLowerCase(), () => folder);
      }
    }
    var spelled = '';
    for (final part in epic.isEmpty ? const <String>[] : epic.split('/')) {
      final folder = spelled.isEmpty ? part : '$spelled/$part';
      spelled = folders[folder.toLowerCase()] ?? folder;
    }
    return spelled;
  }

  /// `PREFIX-n`, one past the highest number used with the prefix. [taken]
  /// reports IDs whose file names exist although no task claims them (for
  /// example a task renamed on another branch).
  String nextId(
    String prefix,
    Iterable<String> ids, [
    bool Function(String id)? taken,
  ]) {
    final pattern = RegExp(
      '^${RegExp.escape(prefix)}-(\\d+)\$',
      caseSensitive: false,
    );
    num highest = 0;
    for (final id in ids) {
      final match = pattern.firstMatch(id);
      if (match != null) highest = max(highest, double.parse(match[1]!));
    }
    String id;
    do {
      id = '$prefix-${jsNumber(++highest)}';
    } while (taken?.call(id) ?? false);
    return id;
  }

  /// A new task's file: `id`, the fields in their written order, then the
  /// custom fields, and the description; LF line endings.
  String serializeNew(String id, TaskInput input) {
    final entries = <(String, Object?)>[
      ('id', id),
      ..._fieldsOf(input),
      for (final e in (input.fields ?? const <String, FieldValue>{}).entries)
        if (e.value != '') (e.key, e.value),
    ];
    // A JavaScript object: keys that are array indices come first, ascending;
    // a key given twice keeps its first place and its last value.
    final values = <String, Object?>{};
    for (final (key, value) in entries) {
      values[key] = value;
    }
    final keys = values.keys.toList();
    final indices = keys.where(_isArrayIndex).toList()
      ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
    final ordered = [...indices, ...keys.where((k) => !_isArrayIndex(k))];
    final map = YMap([
      for (final key in ordered)
        if (values[key] != null) YPair(YScalar(key), createNode(values[key])),
    ]);
    return applyTextStyle(
      compose(YDocument(map).toString(), input.body),
      lfStyle,
    );
  }

  String serializeUpdate(String original, TaskInput input) {
    final front = splitFrontmatter(original);
    final document = front.document;
    final map = _ensureMap(document);
    for (final (key, value) in _fieldsOf(input)) {
      if (value == null) {
        map.delete(key);
      } else {
        map.set(key, value);
      }
    }
    final written = document.toData();
    for (final entry
        in (input.fields ?? const <String, FieldValue>{}).entries) {
      final value = entry.value;
      if (value == '') {
        map.delete(entry.key);
      } else if (jsJson(written is Map ? written[entry.key] : null) !=
          jsJson(value)) {
        map.set(entry.key, value);
      }
    }
    final comments = [
      for (final block in splitComments(
        front.body.replaceFirst(RegExp(r'^\r?\n'), ''),
      ).blocks)
        block.text,
    ];
    return applyTextStyle(
      compose(document.toString(), joinComments(input.body, comments)),
      textStyleOf(original),
    );
  }

  YMap _ensureMap(YDocument document) {
    final contents = document.contents;
    if (contents is YMap) return contents;
    final map = YMap([]);
    document.contents = map;
    return map;
  }
}

/// Whether [key] is an array index, which JavaScript objects list first.
bool _isArrayIndex(String key) {
  if (!RegExp(r'^(?:0|[1-9]\d{0,9})$').hasMatch(key)) return false;
  return int.parse(key) < 4294967295;
}
