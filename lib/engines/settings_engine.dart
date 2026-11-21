/// Project settings: defaults, validation and reading `.genbeya.yml`. Port of
/// Genbeya's `src/engines/settings-engine.ts`; messages are the same.
library;

import '../contracts/model.dart';
import 'js.dart';
import 'repository_path.dart';
import 'text_style.dart';
import 'yaml/yaml_document.dart';

const settingsFile = '.genbeya.yml';
const _defaultStatuses = ['backlog', 'todo', 'in-progress', 'review', 'done'];
final _defaultTypes = [
  for (final name in ['bug', 'feature', 'improvement', 'chore'])
    TaskType.named(name),
];
const _limits = (
  types: 20,
  fields: 30,
  options: 30,
  option: 60,
  people: 500,
  aliases: 20,
  personText: 120,
);
final _icon = RegExp(r'^[a-z][a-z0-9-]{0,39}$');

/// Type names also name template files, so they stay plain.
final typeName = RegExp(r'^[A-Za-z0-9][\w -]{0,39}$');
final _fieldName = RegExp(r'^[A-Za-z][\w-]{0,39}$');
final _handle = RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9_-]{0,37}[A-Za-z0-9])?$');
final _email = RegExp(r'^[^\s@]+@[^\s@]+$');
final _date = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

class SettingsException implements Exception {
  SettingsException(this.message, {this.fromYaml = false});

  final String message;

  /// The YAML itself is invalid; the parser's message, not Genbeya's.
  final bool fromYaml;

  @override
  String toString() => message;
}

Never _fail(String message) => throw SettingsException(message);

/// "TaskBoard" → "TB", "my project" → "MP", "atlas" → "ATL".
String _prefixFor(String name) {
  final capitals = RegExp('[A-Z]').allMatches(name).map((m) => m[0]!).toList();
  final words = name
      .split(RegExp('[^A-Za-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  final prefix = capitals.length >= 2
      ? capitals.join()
      : words.length >= 2
      ? words.map((w) => w[0]).join()
      : (words.isEmpty ? 'T' : words.first);
  final shortened = capitals.length < 2 && words.length < 2 && prefix.length > 3
      ? prefix.substring(0, 3)
      : prefix;
  final upper = shortened.toUpperCase();
  final short = upper.length > 6 ? upper.substring(0, 6) : upper;
  return short.isEmpty ? 'T' : short;
}

String _iconOf(Object? value, String owner) {
  if (value is! String || !_icon.hasMatch(value)) {
    _fail('Choose an icon for $owner.');
  }
  return value;
}

TaskType _validType(Object? entry) {
  final map = entry is Map ? entry : const {};
  final name = trimmed(map['name']);
  final tone = map['tone'];
  if (!typeName.hasMatch(name)) {
    _fail(
      '"$name" is not a valid type name: use letters, digits, spaces, - and _.',
    );
  }
  if (tone != null && !tones.contains(tone)) {
    _fail('Choose a known colour for the type $name.');
  }
  return TaskType(
    name: name,
    icon: _iconOf(map['icon'], 'the type $name'),
    tone: tone is String && tone.isNotEmpty ? tone : null,
  );
}

FieldDefinition _validField(Object? entry) {
  final map = entry is Map ? entry : const {};
  final name = trimmed(map['name']);
  final type = map.containsKey('type') ? map['type'] : 'text';
  final options = map['options'];
  if (!_fieldName.hasMatch(name)) {
    _fail(
      '"$name" is not a valid field name: start with a letter, then use letters, digits, - and _.',
    );
  }
  if (taskKeys.contains(name.toLowerCase())) {
    _fail('$name is a built-in task property.');
  }
  if (!fieldTypes.contains(type)) {
    _fail(
      'The field $name must be text, number, date, choice, effort or tasks.',
    );
  }
  if (type != 'choice') {
    return FieldDefinition(name: name, type: type as String);
  }
  final values = options is List
      ? [for (final o in options) o is num ? jsNumber(o) : trimmed(o)]
      : <String>[];
  if (values.isEmpty ||
      values.length > _limits.options ||
      values.toSet().length != values.length ||
      values.any((o) => o.isEmpty || o.length > _limits.option)) {
    _fail('Give the choice field $name 1–${_limits.options} unique options.');
  }
  return FieldDefinition(name: name, type: 'choice', options: values);
}

PersonEntry _validPerson(Object? entry) {
  final map = entry is Map ? entry : const {};
  final handle = trimmed(map['handle']);
  if (!_handle.hasMatch(handle)) {
    _fail(
      '"$handle" is not a valid handle: use letters, digits, - and _, starting and ending with a letter or digit.',
    );
  }
  final name = trimmed(map['name']);
  if (name.isEmpty || name.length > _limits.personText) {
    _fail('Give @$handle a name.');
  }
  final rawEmail = map['email'];
  final email = trimmed(rawEmail);
  if (rawEmail != null &&
      (!_email.hasMatch(email) || email.length > _limits.personText)) {
    _fail('The email of @$handle is not valid.');
  }
  final rawAliases = map['aliases'];
  final others = rawAliases is List
      ? [for (final a in rawAliases) trimmed(a)]
      : null;
  if ((rawAliases != null && others == null) ||
      (others != null &&
          (others.length > _limits.aliases ||
              others.any((a) => a.isEmpty || a.length > _limits.personText)))) {
    _fail('List up to ${_limits.aliases} aliases of @$handle.');
  }
  return PersonEntry(
    handle: handle,
    name: name,
    email: rawEmail != null ? email : null,
    aliases: others != null && others.isNotEmpty ? others : null,
  );
}

/// A date as Genbeya accepts it: `YYYY-MM-DD`, with a month and a day JavaScript can parse.
bool _isDate(Object? value) {
  if (value is! String) return false;
  final match = _date.firstMatch(value);
  if (match == null) return false;
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  return month >= 1 && month <= 12 && day >= 1 && day <= 31;
}

void _unique(Iterable<String> names, String message) {
  final list = names.map((n) => n.toLowerCase()).toList();
  if (list.toSet().length != list.length) _fail(message);
}

/// Parts of the app, once each and in the app's order.
List<String> validParts(Object? value, String what) {
  if (value is! List || value.any((p) => !parts.contains(p))) {
    _fail('List $what by their names: ${parts.join(', ')}.');
  }
  return parts.where(value.contains).toList();
}

class SettingsEngine {
  /// The settings of a repository without `.genbeya.yml`, as plain data.
  Map<String, Object?> defaults(String name) => {
    'name': name,
    'wikiRoot': 'docs',
    'wikiHome': 'Home.md',
    'taskRoot': 'tasks',
    'taskPrefix': _prefixFor(name),
    'statuses': [..._defaultStatuses],
    'statusIcons': <String, Object?>{},
    'hiddenColumns': <Object?>[],
    'types': [for (final t in _defaultTypes) t.toJson()],
    'fields': <Object?>[],
    'people': <Object?>[],
    'pullRoot': 'pulls',
    'pullPrefix': 'PR',
    'requiredApprovals': 1,
    'todosBlockMerge': true,
    'unused': <Object?>[],
    'workdays': ['mon', 'tue', 'wed', 'thu', 'fri'],
    'holidays': <Object?>[],
    'milestones': <Object?>[],
  };

  Settings validate(Map<Object?, Object?> value, bool windows) {
    String text(Object? input, String label, int max) {
      if (input is! String || input.trim().isEmpty || input.length > max) {
        _fail('$label is required (up to $max characters).');
      }
      return input.trim();
    }

    String folder(Object? input, String label) {
      try {
        return validateRepositoryPath(text(input, label, 200), windows);
      } on FormatException catch (error) {
        _fail(error.message);
      }
    }

    final name = text(value['name'], 'Project name', 120);
    final wikiRoot = folder(value['wikiRoot'], 'Wiki folder');
    final taskRoot = folder(value['taskRoot'], 'Task folder');
    final wikiHome = folder(value['wikiHome'], 'Wiki home');
    if (!wikiHome.endsWith('.md')) {
      _fail('The wiki home must be a Markdown file.');
    }
    if (wikiRoot == taskRoot ||
        within(wikiRoot, taskRoot) ||
        within(taskRoot, wikiRoot)) {
      _fail('Wiki and task folders must not contain each other.');
    }
    final pullRoot = folder(value['pullRoot'], 'Pull request folder');
    if ([wikiRoot, taskRoot].any(
      (other) =>
          other == pullRoot ||
          within(pullRoot, other) ||
          within(other, pullRoot),
    )) {
      _fail(
        'The pull request folder must not contain the wiki or task folder, nor be inside them.',
      );
    }
    final pullPrefix = text(
      value['pullPrefix'],
      'Pull request prefix',
      12,
    ).toUpperCase();
    if (!RegExp(r'^[A-Z][A-Z0-9]*$').hasMatch(pullPrefix)) {
      _fail(
        'The pull request prefix uses letters and digits, starting with a letter.',
      );
    }
    final requiredApprovals = value['requiredApprovals'];
    if (!isInteger(requiredApprovals) ||
        (requiredApprovals as num) < 0 ||
        requiredApprovals > 20) {
      _fail('Required approvals is a whole number from 0 to 20.');
    }
    final todosBlockMerge = value['todosBlockMerge'];
    if (todosBlockMerge is! bool) {
      _fail('Whether open to-dos block a merge is true or false.');
    }

    final workdays = value['workdays'];
    final holidays = value['holidays'];
    final milestones = value['milestones'];
    if (workdays is! List ||
        workdays.isEmpty ||
        workdays.any((d) => !weekdays.contains(d))) {
      _fail('List the working days as ${weekdays.join(', ')}: at least one.');
    }
    if (holidays is! List ||
        holidays.length > 500 ||
        !holidays.every(_isDate)) {
      _fail('List the holidays as dates, written 2026-12-25 (up to 500).');
    }
    if (milestones is! List || milestones.length > 100) {
      _fail('List the milestones (up to 100).');
    }
    final validMilestones = [
      for (final milestone in milestones)
        () {
          final map = milestone is Map ? milestone : const {};
          final text = trimmed(map['name']);
          if (text.isEmpty || text.length > 60) {
            _fail('Give each milestone a name of up to 60 characters.');
          }
          if (!_isDate(map['due'])) {
            _fail('Give the milestone $text a date, written 2026-12-01.');
          }
          return Milestone(name: text, due: map['due'] as String);
        }(),
    ];
    _unique(
      validMilestones.map((m) => m.name),
      'Milestone names must be unique.',
    );

    final unused = validParts(
      value['unused'],
      "the parts the project doesn't use",
    );
    final taskPrefix = text(
      value['taskPrefix'],
      'Task prefix',
      12,
    ).toUpperCase();
    if (!RegExp(r'^[A-Z][A-Z0-9]*$').hasMatch(taskPrefix)) {
      _fail('The task prefix uses letters and digits, starting with a letter.');
    }
    final rawStatuses = value['statuses'];
    final statuses = rawStatuses is List
        ? [for (final s in rawStatuses) trimmed(s)]
        : <String>[];
    if (statuses.isEmpty ||
        statuses.length > 12 ||
        statuses.toSet().length != statuses.length ||
        statuses.any((s) => s.isEmpty || s.length > 40)) {
      _fail('Use 1–12 unique workflow states.');
    }
    final icons = value['statusIcons'];
    if (icons is! Map) _fail('Invalid icons of workflow states.');
    final statusIcons = {
      for (final status in statuses)
        if (icons.containsKey(status))
          status: _iconOf(icons[status], 'the state $status'),
    };
    final hidden = value['hiddenColumns'];
    if (hidden is! List) _fail('List the hidden columns as workflow states.');
    final hiddenColumns = statuses.where(hidden.contains).toList();
    final rawTypes = value['types'];
    if (rawTypes is! List || rawTypes.length > _limits.types) {
      _fail('List the task types (up to ${_limits.types}).');
    }
    final types = [for (final t in rawTypes) _validType(t)];
    _unique(types.map((t) => t.name), 'Task type names must be unique.');
    final rawFields = value['fields'];
    if (rawFields is! List || rawFields.length > _limits.fields) {
      _fail('List the custom fields (up to ${_limits.fields}).');
    }
    final fields = [for (final f in rawFields) _validField(f)];
    _unique(fields.map((f) => f.name), 'Custom field names must be unique.');
    final rawPeople = value['people'];
    if (rawPeople is! List || rawPeople.length > _limits.people) {
      _fail('List the people (up to ${_limits.people}).');
    }
    final people = [for (final p in rawPeople) _validPerson(p)];
    _unique(people.map((p) => p.handle), 'Handles of people must be unique.');
    final handles = {for (final p in people) p.handle.toLowerCase(): p};
    for (final person in people) {
      for (final alias in person.aliases ?? const <String>[]) {
        final other = handles[alias.toLowerCase()];
        if (other != null && other != person) {
          _fail(
            "An alias of @${person.handle} is another person's handle: $alias.",
          );
        }
      }
    }
    final holidayList = holidays.cast<String>().toSet().toList()..sort();
    return Settings(
      name: name,
      wikiRoot: wikiRoot,
      wikiHome: wikiHome,
      taskRoot: taskRoot,
      taskPrefix: taskPrefix,
      statuses: statuses,
      statusIcons: statusIcons,
      hiddenColumns: hiddenColumns,
      types: types,
      fields: fields,
      people: people,
      pullRoot: pullRoot,
      pullPrefix: pullPrefix,
      requiredApprovals: requiredApprovals.toInt(),
      todosBlockMerge: todosBlockMerge,
      unused: unused,
      workdays: weekdays.where(workdays.contains).toList(),
      holidays: holidayList,
      milestones: validMilestones,
    );
  }

  /// Reads a settings file over `fallback`; unknown keys are ignored here.
  Settings parse(String content, Map<String, Object?> fallback, bool windows) {
    final YDocument document;
    try {
      document = parseYamlDocument(withoutByteOrderMark(content));
    } on YamlDocumentException catch (error) {
      throw SettingsException(error.message, fromYaml: true);
    }
    final data = document.toData() ?? <String, Object?>{};
    if (data is! Map) _fail('Settings must be a YAML mapping.');
    final statuses = data['statuses'];
    final entries = statuses is List
        ? [
            for (final e in statuses) e is Map ? e : {'name': e},
          ]
        : null;
    final types = data['types'];
    return validate({
      ...fallback,
      ...data,
      'statuses': entries != null
          ? [for (final e in entries) e['name']]
          : fallback['statuses'],
      'statusIcons': entries != null
          ? {
              for (final e in entries)
                if (e['icon'] != null) jsString(e['name']): e['icon'],
            }
          : fallback['statusIcons'],
      'types': types is List
          ? [
              for (final t in types)
                t is String ? TaskType.named(t.trim()).toJson() : t,
            ]
          : (types ?? fallback['types']),
      'fields': data['fields'] ?? fallback['fields'],
      'people': data['people'] ?? fallback['people'],
    }, windows);
  }
}
