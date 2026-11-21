import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/contracts/model.dart';
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
    }
    throw StateError('Unknown case kind $kind');
  } on SettingsException catch (error) {
    return {'error': error.message, 'fromYaml': error.fromYaml};
  } on TaskException catch (error) {
    return {'error': error.message, 'fromYaml': error.fromYaml};
  }
}
