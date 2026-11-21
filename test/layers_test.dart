import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The layers below the features stay free of Flutter, so they can run
/// headless later (background sync) and match Genbeya's engines one to one.
/// See docs/Architecture.md.
const pureLayers = [
  'lib/contracts',
  'lib/engines',
  'lib/access',
  'lib/managers',
];
final forbidden = RegExp(
  r'''^\s*(import|export)\s+['"](package:flutter/|package:flutter_riverpod/|package:material_ui/|package:cupertino_ui/|dart:ui)''',
  multiLine: true,
);

void main() {
  test('contracts, engines, access and managers import no Flutter', () {
    final offenders = <String>[];
    for (final layer in pureLayers) {
      final dir = Directory(layer);
      if (!dir.existsSync()) continue;
      for (final file
          in dir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        if (forbidden.hasMatch(file.readAsStringSync())) {
          offenders.add(file.path);
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'These files import Flutter: $offenders',
    );
  });
}
