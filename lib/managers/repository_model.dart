/// The repository as the app shows it: settings, the wiki tree, tasks and
/// people, read from Git's objects ([[Call chains#the-repository-model]]).
/// Each area is read from where it lives, the checked-out commit or the
/// content branch, as Genbeya's content store decides. Parsed files are
/// cached by blob ID and path, so loading again after a sync parses only
/// what changed; with a [ParseCache], across app starts too.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../access/git/git_objects.dart';
import '../contracts/model.dart';
import '../engines/content_layout.dart';
import '../engines/people_engine.dart';
import '../engines/settings_engine.dart';
import '../engines/task_engine.dart';
import '../engines/wiki_engine.dart';
import 'parse_cache.dart';

/// Recent commits whose authors count as the repository's people
/// (`AUTHOR_COMMITS` in content-manager.ts).
const authorCommits = 5000;

/// Genbeya's read limit for text (`TEXT_LIMIT` in file-store.ts).
const textLimit = 2 * 1024 * 1024;
const _settingsFile = '.genbeya.yml';

/// A file the model couldn't read or parse, with the reason to show.
class FileProblem {
  const FileProblem(this.path, this.message);
  final String path;
  final String message;
}

/// Where the content lives: the content branch and its commit, if this
/// clone uses one, and the place of each area.
class ContentPlace {
  const ContentPlace({
    required this.head,
    required this.branch,
    required this.branchCommit,
    required this.areas,
  });

  /// The checked-out commit.
  final String head;
  final String? branch;
  final String? branchCommit;
  final AreaModes areas;

  /// The commit [area] is read from.
  String commitOf(String area) =>
      areas[area] == StorageMode.branch && branchCommit != null
      ? branchCommit!
      : head;
}

class RepositoryState {
  const RepositoryState({
    required this.place,
    required this.settings,
    required this.settingsProblem,
    required this.codeFiles,
    required this.wiki,
    required this.tasks,
    required this.problems,
    required this.people,
    required this.me,
  });

  final ContentPlace place;
  final Settings settings;

  /// Why `.genbeya.yml` couldn't be read; the defaults are used meanwhile.
  final String? settingsProblem;

  /// The files of the checked-out commit.
  final List<GitFile> codeFiles;
  final List<WikiNode> wiki;
  final List<Task> tasks;

  /// Task files that couldn't be read or parsed.
  final List<FileProblem> problems;
  final List<Person> people;

  /// The user's handle among [people], by the identity Git signs commits
  /// with (`user.name`, `user.email`), if they are among them.
  final String? me;
}

/// One open repository's model.
class RepositoryModel {
  RepositoryModel(this.git, {required this.folderName, this.cache});

  final GitObjects git;

  /// Where what was parsed is kept between app starts, if anywhere.
  final ParseCache? cache;

  /// Whether [cache] was read into memory yet.
  var _restored = false;

  /// The newest save of [cache]; tests wait on it.
  Future<void> saved = Future.value();

  /// The clone's folder name: the settings' default name and task prefix.
  final String folderName;

  final _settings = SettingsEngine();
  final _tasks = TaskEngine();
  final _wiki = WikiEngine();
  final _people = PeopleEngine();

  /// Parsed tasks (or why not) by blob and path.
  final _parsed = <String, Object>{};

  /// How many files were parsed; tests check the cache with it.
  int parses = 0;

  /// Commit authors, read again only when HEAD moves.
  ({String head, List<CommitAuthor> authors})? _authors;

  RepositoryState? _state;
  RepositoryState? get state => _state;

  /// Reads the repository as it is now. Files whose blob was parsed before
  /// are taken from the cache.
  Future<RepositoryState> load() async {
    if (!_restored) {
      _restored = true;
      if (await cache?.read() case final restored?) {
        _parsed.addAll(restored.parsed);
        _authors ??= restored.authors;
      }
    }
    final parsedBefore = parses;
    final authorsBefore = _authors;
    final place = await locate();
    final filesOf = <String, Future<List<GitFile>>>{};
    Future<List<GitFile>> files(String commit) =>
        filesOf[commit] ??= git.listFiles(commit);

    final fallback = _settings.defaults(folderName);
    var settings = _settings.validate(fallback, false);
    String? settingsProblem;
    final settingsFile = (await files(place.commitOf('settings')))
        .where((file) => file.path == _settingsFile)
        .firstOrNull;
    if (settingsFile != null) {
      try {
        final text = await _text(settingsFile);
        settings = _settings.parse(text, fallback, false);
      } on SettingsException catch (error) {
        settingsProblem = error.message;
      } on FormatException catch (error) {
        settingsProblem = error.message;
      }
    }

    final wikiFiles = await files(place.commitOf('wiki'));
    final wiki = _wiki.tree(
      wikiFiles.map((file) => file.path),
      wikiRoot: settings.wikiRoot,
      wikiHome: settings.wikiHome,
    );

    final taskFiles = (await files(place.commitOf('tasks')))
        .where((file) => isTaskFile(file.path, settings.taskRoot))
        .toList();
    await _parseTasks(taskFiles, settings.taskRoot);
    final tasks = <Task>[];
    final problems = <FileProblem>[];
    for (final file in taskFiles) {
      switch (_parsed[_key(file, settings.taskRoot)]) {
        case final Task task:
          tasks.add(task);
        case final FileProblem problem:
          problems.add(problem);
      }
    }

    final authors = _authors?.head == place.head
        ? _authors!.authors
        : (_authors = (
            head: place.head,
            authors: await git.commitAuthors(authorCommits),
          )).authors;
    final people = _people.merge(
      PeopleSources(
        configured: settings.people,
        authors: authors,
        assignees: [
          for (final task in tasks)
            if (task.assignee.isNotEmpty) task.assignee,
        ],
        commenters: [
          for (final task in tasks)
            for (final comment in task.comments) comment.author,
        ],
      ),
    );

    // What this load used is kept, the rest dropped, when anything changed.
    final used = {for (final file in taskFiles) _key(file, settings.taskRoot)};
    if (cache != null &&
        (parses != parsedBefore ||
            _authors != authorsBefore ||
            _parsed.length != used.length)) {
      _parsed.removeWhere((key, _) => !used.contains(key));
      final files = (parsed: Map.of(_parsed), authors: _authors);
      saved = saved.then((_) => cache!.write(files)).catchError((Object _) {
        // The cache is only a shortcut; the next load tries again.
      });
    }

    return _state = RepositoryState(
      place: place,
      settings: settings,
      settingsProblem: settingsProblem,
      codeFiles: await files(place.head),
      wiki: wiki,
      tasks: tasks,
      problems: problems,
      people: people,
      me: _people.me(people, await _identity()),
    );
  }

  /// Who Git signs commits as in this clone; the app sets it per repository.
  Future<({String name, String email})?> _identity() async {
    final name = await git.configValue('user.name');
    final email = await git.configValue('user.email');
    if (name == null && email == null) return null;
    return (name: name?.trim() ?? '', email: email?.trim() ?? '');
  }

  /// Where each area lives, as `ContentStore.layout` decides: the content
  /// branch (local, else the remote's) unless `genbeya.storage` is
  /// `worktree`, with the areas its `.genbeya-content` lists.
  Future<ContentPlace> locate() async {
    final head = await git.resolveCommit('HEAD');
    if (head == null) throw StateError('The clone has no checked-out commit.');
    final storage = await git.configValue('genbeya.storage');
    final branch =
        await git.configValue('genbeya.branch') ?? defaultContentBranch;
    final tip = storage == 'worktree'
        ? null
        : await git.resolveCommit('refs/heads/$branch') ??
              await git.resolveCommit('refs/remotes/origin/$branch');
    if (tip == null) {
      return ContentPlace(
        head: head,
        branch: null,
        branchCommit: null,
        areas: everyArea(StorageMode.checkout),
      );
    }
    final file = await git.readFileAt(tip, areasFile, 64 * 1024);
    return ContentPlace(
      head: head,
      branch: branch,
      branchCommit: tip,
      // Git reads the file as bytes; names and values are ASCII anyway.
      areas: areasOf(
        file == null ? null : utf8.decode(file, allowMalformed: true),
      ),
    );
  }

  String _key(GitFile file, String taskRoot) =>
      '${file.blob}\u0000${file.path}\u0000$taskRoot';

  Future<void> _parseTasks(List<GitFile> files, String taskRoot) async {
    final missing = [
      for (final file in files)
        if (!_parsed.containsKey(_key(file, taskRoot))) file,
    ];
    if (missing.isEmpty) return;
    final small = [
      for (final file in missing)
        if (file.size <= textLimit && !file.link) file,
    ];
    final bytes = await git.readBlobs([
      for (final file in small) file.blob,
    ], textLimit);
    for (final file in missing) {
      final at = small.indexOf(file);
      parses++;
      _parsed[_key(file, taskRoot)] = at < 0 || bytes[at] == null
          ? FileProblem(
              file.path,
              file.link
                  ? '${file.path} is a symbolic link.'
                  : '${file.path} is larger than 2 MB.',
            )
          : _parseTask(file, bytes[at]!, taskRoot);
    }
  }

  Object _parseTask(GitFile file, Uint8List bytes, String taskRoot) {
    try {
      final text = decodeText(bytes, file.path);
      return _tasks.parse(file.path, text, fileHash(text), taskRoot);
    } on TaskException catch (error) {
      return FileProblem(file.path, error.message);
    } on FormatException catch (error) {
      return FileProblem(file.path, error.message);
    }
  }

  Future<String> _text(GitFile file) async {
    if (file.size > textLimit || file.link) {
      throw FormatException('${file.path} is larger than 2 MB.');
    }
    final bytes = (await git.readBlobs([file.blob], textLimit)).single;
    if (bytes == null) {
      throw FormatException('${file.path} is larger than 2 MB.');
    }
    return decodeText(bytes, file.path);
  }
}

/// Decodes UTF-8 strictly, keeping a byte order mark, as Genbeya's
/// `decodeText` does; binary or malformed files are refused by name.
String decodeText(Uint8List bytes, String name) {
  if (bytes.contains(0)) throw FormatException('$name is a binary file.');
  try {
    // Dart's decoder drops a leading byte order mark; Genbeya keeps it
    // (`ignoreBOM: true`), and so must the text, its hash and what is written.
    final bom =
        bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf;
    return bom ? '\ufeff${utf8.decode(bytes.sublist(3))}' : utf8.decode(bytes);
  } on FormatException {
    throw FormatException('$name is not UTF-8 text.');
  }
}

/// The version stamp of file contents: hex SHA-256 of the text's UTF-8
/// bytes, as Genbeya's `sha256` in src/utilities/bytes.ts.
String fileHash(String text) => sha256.convert(utf8.encode(text)).toString();
