import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/storage/secret_store.dart';
import 'package:genbeya_mobile/app.dart';
import 'package:genbeya_mobile/features/repositories/providers.dart';
import 'package:genbeya_mobile/managers/repositories_manager.dart';

import 'support/fake_remote.dart';

void main() {
  testWidgets('opens on the repositories screen and reaches the spikes', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('app');
    addTearDown(() => root.deleteSync(recursive: true));
    final manager = RepositoriesManager(
      root: root,
      git: FakeRemote(),
      secrets: MemorySecretStore(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoriesManagerProvider.overrideWith((ref) async => manager),
        ],
        child: const GenbeyaApp(listenForLinks: false),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Repositories'), findsOneWidget);
    expect(find.text('No repositories yet'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);

    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spikes'));
    await tester.pumpAndSettle();
    expect(find.text('Git core'), findsOneWidget);
  });
}
