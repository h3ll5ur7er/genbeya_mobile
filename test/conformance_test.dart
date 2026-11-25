import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/contracts/model.dart';
import 'package:genbeya_mobile/engines/checkbox_engine.dart';
import 'package:genbeya_mobile/engines/collation.dart';
import 'package:genbeya_mobile/engines/content_layout.dart';
import 'package:genbeya_mobile/engines/file_tree.dart';
import 'package:genbeya_mobile/engines/genbeya_link.dart';
import 'package:genbeya_mobile/engines/people.dart';
import 'package:genbeya_mobile/engines/people_engine.dart';
import 'package:genbeya_mobile/engines/remote_url.dart';
import 'package:genbeya_mobile/engines/search_engine.dart';
import 'package:genbeya_mobile/engines/wiki_engine.dart';
import 'package:genbeya_mobile/engines/js.dart';
import 'package:genbeya_mobile/engines/settings_engine.dart';
import 'package:genbeya_mobile/engines/task_engine.dart';
import 'package:genbeya_mobile/managers/suggestions.dart';

/// Runs every case in tool/conformance/cases through the Dart engines and
/// compares with what Genbeya's engines produced (tool/conformance/expected,
/// written by `npm run expected` there). See docs/Architecture.md, Conformance.
void main() {
  final cases =
      Directory('tool/conformance/cases')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in cases) {
    final c = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final expected = jsonDecode(
      File(file.path.replaceFirst('/cases/', '/expected/')).readAsStringSync(),
    ) as Map<String, Object?>;
    test('${c['kind']} ${c['id']}', () {
      final actual = _run(
        c['kind']! as String,
        c['input']! as Map<String, Object?>,
      );
      final error = expected['error'] as String?;
      if (error != null) {
        expect(
          actual['error'],
          isNotNull,
          reason: 'Genbeya refuses this: $error',
        );
        if (actual['fromYaml'] != true) expect(actual['error'], error);
        return;
      }
      expect(actual['error'], isNull, reason: 'Genbeya accepts this');
      final key = expected.keys.firstWhere((k) => k != 'genbeya');
      expect(jsJson(actual[key]), jsJson(expected[key]));
    });
  }
}

final _settings = SettingsEngine();
final _tasks = TaskEngine();
final _wiki = WikiEngine();
final _people = PeopleEngine();
final _search = SearchEngine();

Map<String, Object?> _run(String kind, Map<String, Object?> input) {
  try {
    switch (kind) {
      case 'settings.parse':
        final settings = _settings.parse(
          input['content']! as String,
          _settings.defaults(input['folderName']! as String),
          input['windows'] as bool? ?? false,
        );
        return {'settings': settings.toJson()};
      case 'task.parse':
        final task = _tasks.parse(
          input['path']! as String,
          input['content']! as String,
          'hash',
          input['taskRoot']! as String,
        );
        return {'task': task.toJson()};
      case 'task.update':
        final content = input['content']! as String;
        final task = _tasks.parse(
          input['path']! as String,
          content,
          'hash',
          input['taskRoot']! as String,
        );
        final change = input['change'] as Map<String, Object?>? ?? const {};
        final body = switch (input['edit']) {
          'append' => '${task.body.trimRight()}\n\nAdded on the phone.\n',
          'replace' => 'New text\r\n\r\n- [ ] item\r\n',
          _ => null,
        };
        final changedFields = (change['fields'] as Map<String, Object?>?)?.map(
          (k, v) => MapEntry<String, FieldValue>(
            k,
            v is List ? v.cast<String>() : v!,
          ),
        );
        final taskInput = task.toInput().copyWith(
          title: change['title'] as String?,
          status: change['status'] as String?,
          priority: change['priority'] as String?,
          labels: (change['labels'] as List?)?.cast<String>(),
          type: change['type'] as String?,
          assignee: change['assignee'] as String?,
          epic: change['epic'] as String?,
          body: body,
          fields: {...task.fields, ...?changedFields},
        );
        final statuses = (input['statuses']! as List).cast<String>();
        return {
          'output': _tasks.serializeUpdate(
            content,
            _tasks.validate(taskInput, statuses),
          ),
        };
      case 'suggest.mentions':
        final people = [
          for (final p
              in (input['people']! as List).cast<Map<String, Object?>>())
            Person(
              handle: p['handle']! as String,
              name: p['name']! as String,
              email: p['email'] as String?,
              aliases: (p['aliases']! as List).cast<String>(),
              commits: p['commits']! as int,
            ),
        ];
        return {
          'output': [
            for (final query in (input['queries']! as List).cast<String>())
              () {
                final found = mentionSuggestions(people, query);
                return {
                  'handles': [for (final p in found) p.handle],
                  'insert': found.isEmpty
                      ? null
                      : [
                          mentionText(found[0], ''),
                          mentionText(found[0], ' x'),
                        ],
                };
              }(),
          ],
        };
      case 'suggest.references':
        final tasks = [
          for (final t
              in (input['tasks']! as List).cast<Map<String, Object?>>())
            _tasks.parse(
              t['path']! as String,
              '---\nid: ${t['id']}\ntitle: "${t['title']}"\nstatus: ${t['status']}\n---\n',
              'hash',
              'tasks',
            ),
        ];
        return {
          'output': [
            for (final c in referenceCandidates(
              tasks: tasks,
              pages: [
                for (final p
                    in (input['pages']! as List).cast<Map<String, Object?>>())
                  (path: p['path']! as String, title: p['title']! as String),
              ],
              files: (input['files']! as List).cast<String>(),
              wikiRoot: input['wikiRoot']! as String,
            ))
              {
                'target': c.target,
                'label': c.label,
                'detail': ?c.detail,
                'kind': c.kind,
              },
          ],
        };
      case 'suggest.dates':
        final today = input['today']! as String;
        return {
          'output': [
            for (final query in (input['queries']! as List).cast<String>())
              [
                for (final s in dateSuggestions(query, today))
                  {
                    'date': s.date,
                    'label': s.date == query.trim() ? null : s.label,
                  },
              ],
          ],
        };
      case 'task.new':
        final statuses = (input['statuses']! as List).cast<String>();
        return {
          'output': _tasks.serializeNew(
            input['id']! as String,
            _tasks.validate(
              _taskInput(input['input']! as Map<String, Object?>),
              statuses,
            ),
          ),
        };
      case 'task.nextId':
        final taken = (input['taken']! as List).cast<String>().toSet();
        return {
          'output': _tasks.nextId(
            input['prefix']! as String,
            (input['ids']! as List).cast<String>(),
            taken.contains,
          ),
        };
      case 'task.spelling':
        final files = (input['files']! as List).cast<String>();
        return {
          'output': [
            for (final epic in (input['epics']! as List).cast<String>())
              _tasks.existingSpelling(
                epic,
                files,
                input['taskRoot']! as String,
              ),
          ],
        };
      case 'task.template':
        if (input['types'] case final List types) {
          return {
            'output': {
              'templates': [
                for (final type in types.cast<String>())
                  _tasks.newTemplate(type),
              ],
              'paths': [
                for (final type in (input['paths']! as List).cast<String>())
                  _orError(() => _tasks.templatePath('tasks', type)),
              ],
            },
          };
        }
        return {
          'output': _tasks.parseTemplate(input['content']! as String).toJson(),
        };
      case 'collate':
        final strings = (input['strings']! as List).cast<String>().toList();
        stableSort(strings, collate);
        return {'output': strings};
      case 'link.parse':
        Map<String, Object?> itemJson(LinkItem item) => {
          'kind': item.kind,
          switch (item.kind) {
            'task' => 'id',
            'commit' => 'hash',
            _ => 'path',
          }: item.value,
        };
        return {
          'output': [
            for (final text in (input['texts']! as List).cast<String>())
              switch (parseGenbeyaLink(text)) {
                null => null,
                final link => {
                  'remote': link.remote,
                  'item': itemJson(link.item),
                  'described': describeLinkItem(link.item),
                },
              },
          ],
        };
      case 'link.format':
        return {
          'output': [
            for (final link
                in (input['links']! as List).cast<Map<String, Object?>>())
              () {
                final item = link['item']! as Map<String, Object?>;
                final value =
                    (item['id'] ?? item['hash'] ?? item['path'])! as String;
                return formatGenbeyaLink(link['remote']! as String, (
                  kind: item['kind']! as String,
                  value: value,
                ));
              }(),
          ],
        };
      case 'web.url':
        return {
          'output': {
            'files': [
              for (final f in (input['files']! as List).cast<List>())
                webFileUrl(
                  f[0] as String,
                  path: f[1] as String,
                  branch: f[2] as String,
                ),
            ],
            'commits': [
              for (final c in (input['commits']! as List).cast<List>())
                webCommitUrl(c[0] as String, c[1] as String),
            ],
          },
        };
      case 'search.area':
        final paths = (input['paths']! as List).cast<String>();
        return {
          'output': [
            for (final settings
                in (input['settings']! as List).cast<Map<String, Object?>>())
              [
                for (final path in paths)
                  _search.areaOf(
                    path,
                    wikiRoot: settings['wikiRoot']! as String,
                    taskRoot: settings['taskRoot']! as String,
                    pullRoot: settings['pullRoot']! as String,
                  ),
              ],
          ],
        };
      case 'search.excerpt':
        return {
          'output': [
            for (final item
                in (input['lines']! as List).cast<Map<String, Object?>>())
              () {
                final excerpt = _search.excerpt(item['line']! as String, [
                  for (final range
                      in (item['ranges']! as List).cast<Map<String, Object?>>())
                    (start: range['start']! as int, end: range['end']! as int),
                ]);
                return {
                  'text': excerpt.text,
                  'ranges': [
                    for (final range in excerpt.ranges)
                      {'start': range.start, 'end': range.end},
                  ],
                };
              }(),
          ],
        };
      case 'area.of':
        final paths = (input['paths']! as List).cast<String>();
        return {
          'output': [
            for (final settings
                in (input['settings']! as List).cast<Map<String, Object?>>())
              [
                for (final path in paths)
                  contentAreaOf(
                    path,
                    wikiRoot: settings['wikiRoot']! as String,
                    taskRoot: settings['taskRoot']! as String,
                    pullRoot: settings['pullRoot']! as String,
                  ),
              ],
          ],
        };
      case 'remote.parse':
        return {
          'output': [
            for (final url in (input['urls']! as List).cast<String>())
              {
                'remote': parseRemote(url)?.toJson(),
                'helper': namesRemoteHelper(url),
                'safe': withoutCredentials(url),
              },
          ],
        };
      case 'remote.same':
        return {
          'output': [
            for (final pair in (input['pairs']! as List).cast<List>())
              sameRepository(pair[0] as String, pair[1] as String),
          ],
        };
      case 'areas.parse':
        return {
          'output': {
            for (final e in areasOf(input['file'] as String?).entries)
              e.key: e.value.name,
          },
        };
      case 'collate.base':
        final strings = (input['strings']! as List).cast<String>().toList();
        stableSort(strings, collateBase);
        return {'output': strings};
      case 'collate.full':
        final strings = (input['strings']! as List).cast<String>().toList();
        stableSort(strings, collateFull);
        return {'output': strings};
      case 'file.tree':
        final files = (input['files']! as List).cast<String>();
        return {
          'output': [for (final node in buildFileTree(files)) node.toJson()],
        };
      case 'wiki.tree':
        final files = (input['files']! as List).cast<String>();
        final wikiRoot = input['wikiRoot']! as String;
        final wikiHome = input['wikiHome']! as String;
        return {
          'output': {
            'tree': [
              for (final node in _wiki.tree(
                files,
                wikiRoot: wikiRoot,
                wikiHome: wikiHome,
              ))
                node.toJson(),
            ],
            'pages': [
              for (final page in _wiki.pages(
                files,
                wikiRoot: wikiRoot,
                wikiHome: wikiHome,
              ))
                {'title': page.title, 'path': page.path},
            ],
          },
        };
      case 'people.merge':
        final sources = input['sources']! as Map<String, Object?>;
        List<String> strings(String key) =>
            (sources[key]! as List).cast<String>();
        final merged = _people.merge(
          PeopleSources(
            configured: [
              for (final entry
                  in (sources['configured']! as List)
                      .cast<Map<String, Object?>>())
                PersonEntry(
                  handle: entry['handle']! as String,
                  name: entry['name']! as String,
                  email: entry['email'] as String?,
                  aliases: (entry['aliases'] as List?)?.cast<String>(),
                ),
            ],
            authors: [
              for (final author
                  in (sources['authors']! as List).cast<Map<String, Object?>>())
                (
                  name: author['name']! as String,
                  email: author['email']! as String,
                  commits: author['commits']! as int,
                ),
            ],
            assignees: strings('assignees'),
            commenters: strings('commenters'),
          ),
        );
        return {
          'output': {
            'people': [for (final person in merged) person.toJson()],
            'me': [
              for (final identity
                  in (input['identities']! as List)
                      .cast<Map<String, Object?>>())
                _people.me(merged, (
                  name: identity['name']! as String,
                  email: identity['email']! as String,
                )),
            ],
          },
        };
      case 'handle.slug':
        return {
          'output': [
            for (final text in (input['texts']! as List).cast<String>())
              handleSlug(text),
          ],
        };
      case 'task.comment':
        final content = input['content']! as String;
        return {
          'output': switch (input['op']) {
            'add' => _tasks.addComment(
              content,
              input['author']! as String,
              DateTime.parse(input['date']! as String).toUtc(),
              _tasks.validComment(input['text']! as String),
            ),
            'edit' => _tasks.editComment(
              content,
              input['index']! as int,
              _tasks.validComment(input['text']! as String),
            ),
            _ => _tasks.removeComment(content, input['index']! as int),
          },
        };
      case 'task.changes':
        ({String path, String? content})? version(Object? value) =>
            value is Map<String, Object?>
            ? (
                path: value['path']! as String,
                content: value['content'] as String?,
              )
            : null;
        return {
          'output': _tasks.changesBetween(
            version(input['before']),
            version(input['after'])!,
            input['taskRoot']! as String,
          ),
        };
      case 'page.toggle':
        // Where an item starts, the app's checked toggle writes Genbeya's
        // bytes; elsewhere it refuses, and the lenient port still matches.
        final content = input['content']! as String;
        final offset = input['offset']! as int;
        final checked = togglePageCheckbox(content, offset);
        if ((checked != null) != input['item']) {
          return {'error': 'The item check disagrees at $offset.'};
        }
        final at = content.length - stripFrontmatter(content).length + offset;
        return {'output': checked ?? toggleCheckboxAt(content, at)};
      case 'task.toggle':
        final content = input['content']! as String;
        final offset = input['offset']! as int;
        final task = _tasks.parse(
          input['path']! as String,
          content,
          'hash',
          input['taskRoot']! as String,
        );
        final checked = toggleDescriptionCheckbox(task.body, offset);
        if ((checked != null) != input['item']) {
          return {'error': 'The item check disagrees at $offset.'};
        }
        final body = checked ?? toggleCheckboxAt(task.body, offset);
        final statuses = (input['statuses']! as List).cast<String>();
        return {
          'output': _tasks.serializeUpdate(
            content,
            _tasks.validate(task.toInput().copyWith(body: body), statuses),
          ),
        };
    }
    throw StateError('Unknown case kind $kind');
  } on SettingsException catch (error) {
    return {'error': error.message, 'fromYaml': error.fromYaml};
  } on TaskException catch (error) {
    return {'error': error.message, 'fromYaml': error.fromYaml};
  }
}

FieldValue _fieldValue(Object? value) =>
    value is List ? value.cast<String>() : value!;

/// A task input as the client sends it.
TaskInput _taskInput(Map<String, Object?> json) => TaskInput(
  title: json['title']! as String,
  status: json['status']! as String,
  priority: json['priority']! as String,
  assignee: json['assignee']! as String,
  labels: (json['labels']! as List).cast<String>(),
  body: json['body']! as String,
  epic: json['epic']! as String,
  type: json['type'] as String?,
  fields: (json['fields'] as Map<String, Object?>?)?.map(
    (k, v) => MapEntry(k, _fieldValue(v)),
  ),
);

Object? _orError(Object? Function() run) {
  try {
    return run();
  } on TaskException catch (error) {
    return {'error': error.message};
  }
}
