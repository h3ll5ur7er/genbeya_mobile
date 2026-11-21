import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genbeya_mobile/app.dart';

void main() {
  testWidgets('opens on the repositories screen and reaches the spikes', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: GenbeyaApp()));
    expect(find.text('Repositories'), findsOneWidget);
    expect(find.text('No repositories yet'), findsOneWidget);

    await tester.tap(find.text('Open the spikes'));
    await tester.pumpAndSettle();
    expect(find.text('Git core'), findsOneWidget);
  });
}
