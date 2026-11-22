/// The repository's people, merged from what names them: the people the
/// settings list, recent commit authors, comment authors and assignees.
/// Everyone gets a unique handle for `@mentions`. Port of Genbeya's
/// `src/engines/people-engine.ts`.
library;

import '../contracts/model.dart';
import 'collation.dart';
import 'people.dart';

/// Commits by one name and email, as `git log --format=%aN%x00%aE` prints
/// them (with .mailmap applied).
typedef CommitAuthor = ({String name, String email, int commits});

class PeopleSources {
  const PeopleSources({
    this.configured = const [],
    this.authors = const [],
    this.assignees = const [],
    this.commenters = const [],
  });

  /// From the settings; they win.
  final List<PersonEntry> configured;
  final List<CommitAuthor> authors;

  /// Task assignees as the tasks write them: a handle, a name or an email.
  final List<String> assignees;

  /// Comment authors' names.
  final List<String> commenters;
}

/// Email local parts that name a mailbox rather than a person.
const _genericMailboxes = {'noreply', 'no-reply', 'root'};

class _Draft {
  _Draft(this.handle, this.name, this.email);
  String? handle;
  String name;
  String? email;
  final aliases = <String>[];
  int commits = 0;
}

String _key(String text) => text.trim().toLowerCase();

/// "ada@example.com" → "ada"; GitHub's "123+ada@users.noreply.github.com" →
/// "ada"; "ada+git@…" → "ada".
String _mailbox(String email) {
  final parts = email.split('@');
  final local = parts.isNotEmpty ? parts[0] : '';
  final domain = parts.length > 1 ? parts[1] : '';
  final name = domain.toLowerCase() == 'users.noreply.github.com'
      ? local.substring(local.indexOf('+') + 1)
      : local.split('+')[0];
  return _genericMailboxes.contains(name.toLowerCase()) ? '' : name;
}

class PeopleEngine {
  List<Person> merge(PeopleSources sources) {
    final drafts = <_Draft>[];

    /// Who each name, email, alias and handle means, lower case.
    final owners = <String, _Draft>{};
    void claim(_Draft draft, String text) {
      if (_key(text).isNotEmpty) owners.putIfAbsent(_key(text), () => draft);
    }

    /// Adds another name or email of [draft], unless it is the one shown or known already.
    void alias(_Draft draft, String text) {
      final known = [
        draft.name,
        draft.email ?? '',
        ...draft.aliases,
      ].any((other) => _key(other) == _key(text));
      if (_key(text).isNotEmpty && !known) draft.aliases.add(text.trim());
      claim(draft, text);
    }

    _Draft create(String name, String? email, [String? handle]) {
      final trimmed = email?.trim();
      final draft = _Draft(
        handle,
        name.trim(),
        trimmed == null || trimmed.isEmpty ? null : trimmed,
      );
      drafts.add(draft);
      for (final text in [handle ?? '', draft.name, draft.email ?? '']) {
        claim(draft, text);
      }
      return draft;
    }

    for (final entry in sources.configured) {
      final draft = create(entry.name, entry.email, entry.handle);
      for (final text in entry.aliases ?? const <String>[]) {
        alias(draft, text);
      }
    }

    // One author per email, named as most commits name them; the busiest
    // come first, so they keep their name and email.
    final byEmail = <String, List<CommitAuthor>>{};
    for (final author in sources.authors) {
      final email = _key(author.email);
      final id = email.isNotEmpty ? email : 'name:${_key(author.name)}';
      (byEmail[id] ??= []).add(author);
    }
    final groups = [
      for (final names in byEmail.values)
        (
          names: stableSorted(names, (a, b) => b.commits - a.commits),
          commits: names.fold<int>(0, (sum, author) => sum + author.commits),
        ),
    ];
    stableSort(
      groups,
      (a, b) => b.commits - a.commits != 0
          ? b.commits - a.commits
          : collateFull(_key(a.names[0].email), _key(b.names[0].email)),
    );
    for (final (:names, :commits) in groups) {
      final top = names.first;
      final email = top.email.trim();
      final draft =
          (email.isNotEmpty ? owners[_key(email)] : null) ??
          names
              .map((author) => owners[_key(author.name)])
              .nonNulls
              .firstOrNull ??
          create(top.name, email.isEmpty ? null : email);
      if (draft.email == null && email.isNotEmpty) draft.email = email;
      draft.commits += commits;
      for (final author in names) {
        alias(draft, author.name);
      }
      alias(draft, email);
    }

    for (final name in sources.commenters) {
      if (_key(name).isNotEmpty && !owners.containsKey(_key(name))) {
        create(name, null);
      }
    }

    final taken = {
      for (final draft in drafts)
        if (draft.handle != null) _key(draft.handle!),
    };
    void assignHandles() {
      // In a fixed order, so the same people always get the same handles.
      final pending = drafts.where((draft) => draft.handle == null).toList();
      stableSort(
        pending,
        (a, b) => collateFull(_key(a.email ?? a.name), _key(b.email ?? b.name)),
      );
      for (final draft in pending) {
        final first = draft.name.split(RegExp(r'\s+'))[0];
        final slugs = [
          _mailbox(draft.email ?? ''),
          draft.name,
          first,
        ].map(handleSlug).where((slug) => slug.isNotEmpty).toList();
        final candidates = slugs.isNotEmpty ? slugs : ['person'];
        var handle = candidates
            .where((candidate) => !taken.contains(candidate))
            .firstOrNull;
        if (handle == null) {
          final base = candidates.first;
          var number = 2;
          while (taken.contains('$base-$number')) {
            number++;
          }
          handle = '$base-$number';
        }
        draft.handle = handle;
        taken.add(handle);
        claim(draft, handle);
      }
    }

    assignHandles();

    // Assignees may be written as a handle, a name or an email.
    for (final assignee in sources.assignees) {
      if (_key(assignee).isNotEmpty && !owners.containsKey(_key(assignee))) {
        create(assignee, null);
      }
    }
    assignHandles();

    final people = [
      for (final draft in drafts)
        Person(
          handle: draft.handle!,
          name: draft.name,
          email: draft.email,
          aliases: draft.aliases,
          commits: draft.commits,
        ),
    ];
    stableSort(people, (a, b) {
      final byName = collateFull(a.name, b.name);
      return byName != 0 ? byName : collateFull(a.handle, b.handle);
    });
    return people;
  }

  /// The handle of the user Git knows as [identity], by email, else by name;
  /// null when they are none of [people].
  String? me(List<Person> people, ({String name, String email})? identity) {
    if (identity == null) return null;
    final index = PeopleIndex(people);
    return (index.find(identity.email) ?? index.find(identity.name))?.handle;
  }
}
