import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../access/native/native_git_objects.dart';
import '../../contracts/clones.dart';
import '../../managers/repository_session.dart';
import '../repositories/providers.dart';

/// The open repository's session, loaded; one per clone.
final sessionProvider = FutureProvider.family<RepositorySession, CloneRecord>((
  ref,
  record,
) async {
  final manager = await ref.watch(repositoriesManagerProvider.future);
  final identity = await manager.identityOf(record);
  final session = RepositorySession(
    NativeGitObjects(manager.folderOf(record)),
    folderName: record.name,
    author: identity?.name,
    remote: record.url,
    branch: record.branch,
    record: record,
  );
  await session.load();
  return session;
});
