import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../access/native/native_git_remote.dart';
import '../../access/storage/secret_store.dart';
import '../../managers/repositories_manager.dart';

/// The clones on this phone, kept in the app's private storage.
final repositoriesManagerProvider = FutureProvider<RepositoriesManager>((
  ref,
) async {
  final root = await getApplicationSupportDirectory();
  return RepositoriesManager(
    root: root,
    git: const NativeGitRemote(),
    secrets: const KeychainSecretStore(),
    deviceName:
        'Genbeya Mobile (${Platform.isIOS ? 'iPhone' : Platform.operatingSystem})',
  );
});

/// The clones and how each stands; invalidated after adding, removing or
/// syncing one.
final clonesProvider = FutureProvider<List<CloneStatus>>((ref) async {
  final manager = await ref.watch(repositoriesManagerProvider.future);
  final clones = await manager.clones();
  return Future.wait(clones.map(manager.status));
});
