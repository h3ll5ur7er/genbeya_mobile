import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/features/repository/changes_screen.dart';
import 'package:genbeya_mobile/managers/sync_manager.dart';

void main() {
  test('a sync says what it did, a renumbering included', () {
    final report = SyncReport()
      ..pushed['main'] = 2
      ..renumbered['GM-9'] = 'GM-12';
    expect(report.nothingToDo, isFalse);
    expect(
      describeSync(report),
      "GM-9 was taken meanwhile by someone else's task: yours is GM-12 now, and what you wrote refers to GM-12.\n"
      'Pushed 2 commits to main.',
    );
    expect(describeSync(SyncReport()), 'Up to date.');
  });
}
