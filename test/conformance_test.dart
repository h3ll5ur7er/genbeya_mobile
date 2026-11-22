import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/contracts/model.dart';
import 'package:genbeya_mobile/engines/checkbox_engine.dart';
import 'package:genbeya_mobile/engines/collation.dart';
import 'package:genbeya_mobile/engines/content_layout.dart';
import 'package:genbeya_mobile/engines/file_tree.dart';
import 'package:genbeya_mobile/engines/people.dart';
import 'package:genbeya_mobile/engines/people_engine.dart';
import 'package:genbeya_mobile/engines/remote_url.dart';
import 'package:genbeya_mobile/engines/wiki_engine.dart';
import 'package:genbeya_mobile/engines/js.dart';
import 'package:genbeya_mobile/engines/settings_engine.dart';
import 'package:genbeya_mobile/engines/task_engine.dart';

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
        final change = input['change']! as Map<String, Object?>;
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
          fields: {...task.fields, ...?changedFields},
        );
        final statuses = (input['statuses']! as List).cast<String>();
        return {
          'output': _tasks.serializeUpdate(
            content,
            _tasks.validate(taskInput, statuses),
          ),
        };
      case 'collate':
        final strings = (input['strings']! as List).cast<String>().toList();
        stableSort(strings, collate);
        return {'output': strings};
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
