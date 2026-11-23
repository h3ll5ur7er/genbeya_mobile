import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../access/native/native_git_writer.dart';
import '../../access/storage/json_store.dart';
import '../../contracts/clones.dart';
import '../../engines/people.dart';
import '../../managers/content_writer.dart';
import '../../managers/sync_manager.dart';
import '../repositories/providers.dart';
import 'session_provider.dart';

/// Writing to a clone and syncing it: one writer and one sync per clone.
typedef RepositoryWork = ({
  ContentWriter writer,
  SyncManager sync,
  NativeGitWriter git,
});

final workProvider = FutureProvider.family<RepositoryWork, CloneRecord>((
  ref,
  record,
) async {
  final manager = await ref.watch(repositoriesManagerProvider.future);
  final session = await ref.watch(sessionProvider(record).future);
  final dir = manager.folderOf(record);
  final git = NativeGitWriter(dir);
  Future<({String name, String email})> signer() async {
    final identity = await manager.identityOf(record);
    return identity == null || identity.name.isEmpty
        ? (name: 'Genbeya Mobile', email: '')
        : (name: identity.name, email: identity.email);
  }

  final writer = ContentWriter(
    dir: dir,
    git: git,
    journal: JsonStore(File('${manager.root.path}/journals/${record.id}.json')),
    signer: signer,
  );
  return (
    writer: writer,
    git: git,
    sync: SyncManager(
      git: git,
      writer: writer,
      access: () => manager.accessFor(record.url, record.credential),
      signer: signer,
      handle: () {
        final me = session.state?.me;
        if (me != null) return me;
        final slug = handleSlug(session.author ?? '');
        return slug.isEmpty ? 'phone' : slug;
      },
    ),
  );
});
