/// One open repository: its model, where each path is read from, and what
/// the kit is given to render it (context, pages, files), read-only
/// ([[Call chains#c5-render-a-page]]).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../access/git/git_objects.dart';
import '../access/kit/kit_host.dart';
import '../contracts/model.dart';
import '../engines/content_layout.dart';
import '../engines/task_activity.dart';
import '../engines/task_engine.dart';
import '../engines/wiki_engine.dart';
import 'repository_model.dart';

class RepositorySession {
  RepositorySession(this.git, {required String folderName, this.author})
    : model = RepositoryModel(git, folderName: folderName);

  final GitObjects git;
  final RepositoryModel model;

  /// The name the user's comments are signed with (the clone's Git name).
  final String? author;
  final _wiki = WikiEngine();

  RepositoryState? get state => model.state;

  Future<RepositoryState> load() => model.load();

  RepositoryState get _state =>
      model.state ?? (throw StateError('The repository is not loaded yet.'));

  /// The commit a repository path is read from: its area's place, the
  /// checked-out commit for code.
  String commitOf(String path) {
    final settings = _state.settings;
    final area = contentAreaOf(
      path,
      wikiRoot: settings.wikiRoot,
      taskRoot: settings.taskRoot,
      pullRoot: settings.pullRoot,
    );
    return area == null ? _state.place.head : _state.place.commitOf(area);
  }

  Future<Uint8List> readBytes(String path, int maxBytes) async {
    final bytes = await git.readFileAt(commitOf(path), path, maxBytes);
    if (bytes == null) throw KitReadException('$path is not there.');
    return bytes;
  }

  Future<String> readText(String path) async {
    try {
      return decodeText(await readBytes(path, textLimit), path);
    } on FormatException catch (error) {
      throw KitReadException(error.message);
    }
  }

  /// A wiki page, whole, with its version.
  Future<KitPage> page(String path) async {
    final content = await readText(path);
    return KitPage(
      path: path,
      title: _wiki.titleOf(path),
      content: content,
      hash: fileHash(content),
    );
  }

  /// The kit's context in parts, each versioned by its content, so only the
  /// parts that changed are sent again.
  Map<String, KitContextPart> kitContext() {
    final state = _state;
    final settings = state.settings;
    final parts = <String, Object?>{
      'wiki': {
        'wikiRoot': settings.wikiRoot,
        'nodes': [for (final node in state.wiki) node.toJson()],
      },
      'tasks': [
        for (final task in state.tasks)
          {
            'id': task.id,
            'path': task.path,
            'title': task.title,
            'status': task.status,
          },
      ],
      // Plan macros wait for the planning port ([[GM-18]]).
      'plan': null,
      'files': [for (final file in state.codeFiles) file.path],
      'people': [for (final person in state.people) person.toJson()],
      'settings': {
        'statuses': settings.statuses,
        'hiddenColumns': settings.hiddenColumns,
        'types': [for (final type in settings.types) type.toJson()],
        'fields': [for (final field in settings.fields) field.toJson()],
      },
      'author': author,
    };
    return {
      for (final e in parts.entries)
        e.key: (version: _versionOf(e.value), value: e.value),
    };
  }

  static String _versionOf(Object? value) =>
      sha1.convert(utf8.encode(jsonEncode(value))).toString().substring(0, 16);

  /// A task's activity: the commits that changed it, newest first, and what
  /// each changed, as the desktop's task activity (at most 100 commits;
  /// larger versions list their commits without what changed).
  Future<TaskActivity> taskActivity(Task task) async {
    final history = await git.fileHistory(
      commitOf(task.path),
      task.path,
      limit: 100,
      maxBytes: 256 * 1024,
    );
    String? text(Uint8List? bytes) =>
        bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
    final taskRoot = _state.settings.taskRoot;
    return (
      entries: [
        for (final revision in history.revisions)
          (
            commit: revision.commit,
            author: revision.author,
            date: DateTime.fromMillisecondsSinceEpoch(revision.time * 1000),
            subject: revision.subject,
            changes: _taskEngine.changesBetween(
              revision.oldPath == null
                  ? null
                  : (path: revision.oldPath!, content: text(revision.before)),
              (path: revision.path, content: text(revision.after)),
              taskRoot,
            ),
          ),
      ],
      truncated: history.truncated,
    );
  }

  final _taskEngine = TaskEngine();

  /// What the kit may read: images, files and files as committed.
  KitFiles kitFiles() => _SessionFiles(this);
}

/// A commit of a task's activity and what it changed.
typedef ActivityEntry = ({
  String commit,
  String author,
  DateTime date,
  String subject,
  List<TaskChange> changes,
});

typedef TaskActivity = ({List<ActivityEntry> entries, bool truncated});

class _SessionFiles implements KitFiles {
  _SessionFiles(this.session);
  final RepositorySession session;

  @override
  Future<Uint8List> image(String path) =>
      session.readBytes(path, kitImageLimit);

  @override
  Future<String> file(String path) => session.readText(path);

  @override
  Future<String> fileAt(String path, String revision) async {
    final commit = await session.git.resolveCommit(revision);
    if (commit == null) {
      throw KitReadException('$revision is not in this clone.');
    }
    final bytes = await session.git.readFileAt(commit, path, kitTextLimit);
    if (bytes == null) throw KitReadException('$path is not in $revision.');
    try {
      return decodeText(bytes, path);
    } on FormatException catch (error) {
      throw KitReadException(error.message);
    }
  }

  @override
  Future<String> planHistory(String? baseline) =>
      Future.error(KitReadException('Burndowns come with planning (GM-18).'));
}
