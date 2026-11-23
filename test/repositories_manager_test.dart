import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/git/git_remote.dart';
import 'package:genbeya_mobile/access/storage/secret_store.dart';
import 'package:genbeya_mobile/contracts/clones.dart';
import 'package:genbeya_mobile/managers/repositories_manager.dart';

import 'support/fake_remote.dart';

void main() {
  late Directory root;
  late FakeRemote git;
  late MemorySecretStore secrets;
  late RepositoriesManager manager;

  setUp(() {
    root = Directory.systemTemp.createTempSync('repositories');
    git = FakeRemote();
    secrets = MemorySecretStore();
    manager = RepositoriesManager(
      root: root,
      git: git,
      secrets: secrets,
      deviceName: 'Pixel',
    );
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'clones a public repository with its content branch, then lists it',
    () async {
      git.branchesOf['https://github.com/genbeya/genbeya.git'] = [
        'main',
        'develop',
        'genbeya',
      ];
      final plan = await manager.prepare(
        ' https://github.com/genbeya/genbeya.git ',
      );
      expect(plan.credential, CredentialKind.none);
      expect(plan.hasContentBranch, isTrue);
      expect(plan.repository.name, 'genbeya');
      final progress = <CloneProgress>[];
      final record = await manager.add(
        plan,
        identity: (name: 'Ada Lovelace', email: 'ada@example.com'),
        onProgress: progress.add,
      );
      expect(git.calls, ['clone https://github.com/genbeya/genbeya.git main']);
      expect(git.lastExtra, ['genbeya']);
      expect(git.lastDepth, defaultDepth);
      expect(progress, hasLength(1));
      expect(record.contentBranch, 'genbeya');
      expect(record.id, startsWith('genbeya-'));
      expect(await manager.identityOf(record), (
        name: 'Ada Lovelace',
        email: 'ada@example.com',
      ));
      expect(await manager.lastIdentity(), (
        name: 'Ada Lovelace',
        email: 'ada@example.com',
      ));

      final reopened = RepositoriesManager(
        root: root,
        git: git,
        secrets: secrets,
      );
      final listed = await reopened.clones();
      expect([for (final r in listed) r.name], ['genbeya']);
      final status = await reopened.status(listed.single);
      expect(status.head?.ahead, 2);
      expect(status.bytes, 5);
    },
  );

  test(
    'a credential in the URL is never stored, and a token goes to the keychain',
    () async {
      await manager.saveToken('GitHub.com', 'x-access-token', 'ghp_secret');
      git.branchesOf['https://github.com/acme/private.git'] = ['main'];
      final plan = await manager.prepare(
        'https://me:ghp_pasted@github.com/acme/private.git',
      );
      expect(plan.url, 'https://github.com/acme/private.git');
      expect(plan.credential, CredentialKind.token);
      expect(git.lastAccess?.token, 'ghp_secret');
      await manager.add(plan, depth: null);
      expect(git.lastDepth, isNull);
      final stored = File('${root.path}/repositories.json').readAsStringSync();
      expect(stored, isNot(contains('ghp_')));
      expect(RepositoriesManager.tokenUser('gitlab.example.com'), 'oauth2');
    },
  );

  test(
    'SSH uses the key made on this device, and asks about host keys',
    () async {
      const url = 'git@github.com:acme/private.git';
      git.branchesOf[url] = ['main'];
      git.failNext = const HostKeyUnknown('github.com', 'SHA256:host');
      await expectLater(manager.prepare(url), throwsA(isA<HostKeyUnknown>()));
      await manager.trustHostKey('SHA256:host');
      final plan = await manager.prepare(url);
      expect(plan.credential, CredentialKind.sshKey);
      expect(git.lastAccess?.username, 'git');
      expect(git.lastAccess?.privateKey, 'PRIVATE-1');
      expect(git.lastAccess?.trustedHostKeys, ['SHA256:host']);
      final key = await manager.deviceKey();
      expect(key.publicKey, 'ssh-ed25519 AAAA1 Pixel');
      expect(git.keys, 1, reason: 'one key per device, made once');
      expect(
        File('${root.path}/remote-settings.json').readAsStringSync(),
        isNot(contains('PRIVATE')),
      );
    },
  );

  test('a failed clone leaves nothing, and is not listed', () async {
    git.branchesOf['https://example.com/a/b'] = ['main'];
    final plan = await manager.prepare('https://example.com/a/b');
    git.failNext = const Cancelled();
    await expectLater(manager.add(plan), throwsA(isA<Cancelled>()));
    expect(await manager.clones(), isEmpty);
    expect(Directory('${root.path}/clones').listSync(), isEmpty);
  });

  test('refuses what is no remote repository', () async {
    for (final url in ['/srv/repo.git', 'ext::sh -c x', '', 'C:/repo']) {
      await expectLater(
        manager.prepare(url),
        throwsFormatException,
        reason: url,
      );
    }
  });

  test('removes a clone and its folder', () async {
    git.branchesOf['https://example.com/a/b'] = ['main'];
    final record = await manager.add(
      await manager.prepare('https://example.com/a/b'),
    );
    expect(Directory(manager.folderOf(record)).existsSync(), isTrue);
    await manager.remove(record.id);
    expect(Directory(manager.folderOf(record)).existsSync(), isFalse);
    expect(await manager.clones(), isEmpty);
  });

  test(
    'a clone made without credentials pushes with a token saved since',
    () async {
      const url = 'https://github.com/acme/app.git';
      expect((await manager.accessFor(url, CredentialKind.none)).token, isNull);
      await manager.saveToken('github.com', 'x-access-token', 'secret');
      final access = await manager.accessFor(url, CredentialKind.none);
      expect(access.token, 'secret');
      expect(access.username, 'x-access-token');
      expect(
        (await manager.accessFor(
          'https://gitlab.com/a/b.git',
          CredentialKind.none,
        )).token,
        isNull,
        reason: 'only to the host it was saved for',
      );
    },
  );
}
