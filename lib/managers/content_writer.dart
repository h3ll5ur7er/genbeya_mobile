/// Writing to a clone ([[Call chains#c4-change-a-task]]): every save is a
/// commit named after the change, signed with the clone's identity. Files
/// of an area kept on the content branch become a commit there, without a
/// checkout; others are written to the working tree and committed, with a
/// journal so that a write the app was killed during is committed on the
/// next start. One write at a time per clone.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../access/git/git_writer.dart';
import '../access/storage/json_store.dart';
import '../engines/content_layout.dart';
import 'repository_model.dart';

class ContentWriter {
  ContentWriter({
    required this.dir,
    required this.git,
    required this.journal,
    required this.signer,
  });

  /// The clone's folder.
  final String dir;
  final GitWriter git;

  /// Where a write in progress is recorded (in the app's storage, not the clone).
  final JsonStore journal;

  /// Who commits are signed as.
  final Future<Signer> Function() signer;

  Future<void> _queue = Future.value();

  /// Runs [action] after the writes before it.
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  /// Writes [files] (null deletes one) as one commit per place they live in,
  /// named [message]; the last commit's ID.
  Future<String> write(
    RepositoryState state,
    Map<String, String?> files,
    String message,
  ) => _serial(() async {
    final settings = state.settings;
    final onBranch = <String, String?>{};
    final inCheckout = <String, String?>{};
    for (final e in files.entries) {
      final area = contentAreaOf(
        e.key,
        wikiRoot: settings.wikiRoot,
        taskRoot: settings.taskRoot,
        pullRoot: settings.pullRoot,
      );
      final branch =
          area != null &&
          state.place.branch != null &&
          state.place.areas[area] == StorageMode.branch;
      (branch ? onBranch : inCheckout)[e.key] = e.value;
    }
    final who = await signer();
    String? last;
    if (onBranch.isNotEmpty) {
      last = await git.commitOntoBranch(
        state.place.branch!,
        {
          for (final e in onBranch.entries)
            e.key: e.value == null
                ? null
                : Uint8List.fromList(utf8.encode(e.value!)),
        },
        message,
        who,
      );
    }
    if (inCheckout.isNotEmpty) {
      await journal.write({
        'paths': inCheckout.keys.toList(),
        'message': message,
      });
      for (final e in inCheckout.entries) {
        await _writeFile(e.key, e.value);
      }
      last = await git.commitFiles(inCheckout.keys.toList(), message, who);
      await journal.write(null);
    }
    return last ?? (throw ArgumentError('Nothing to write.'));
  });

  /// Commits a write the app was stopped during, if the journal holds one
  /// and its files are still uncommitted; true when it did.
  Future<bool> recover() => _serial(() async {
    final entry = await journal.read();
    if (entry is! Map) return false;
    final paths = (entry['paths'] as List?)?.whereType<String>().toList() ?? [];
    final message = entry['message'] as String? ?? 'Edits from Genbeya Mobile';
    final dirty = (await git.head()).dirty.toSet();
    final pending = [
      for (final path in paths)
        if (dirty.contains(path)) path,
    ];
    if (pending.isNotEmpty) {
      await git.commitFiles(pending, message, await signer());
    }
    await journal.write(null);
    return pending.isNotEmpty;
  });

  /// Writes a file atomically: a temporary file, then a rename.
  Future<void> _writeFile(String path, String? content) async {
    final file = File('$dir/$path');
    if (content == null) {
      if (file.existsSync()) await file.delete();
      // Folders the file leaves empty go too, as desktop removes them.
      var folder = file.parent;
      while (folder.path.length > dir.length &&
          folder.existsSync() &&
          folder.listSync().isEmpty) {
        await folder.delete();
        folder = folder.parent;
      }
      return;
    }
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.genbeya-tmp');
    await temporary.writeAsBytes(utf8.encode(content), flush: true);
    await temporary.rename(file.path);
  }
}
