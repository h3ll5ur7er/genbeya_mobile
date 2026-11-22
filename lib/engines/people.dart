/// Handles and `@mentions`: the rules shared by the people engine, which
/// gives everyone a handle, and the screens, which render mentions of them.
/// Port of Genbeya's `src/utilities/people.ts`.
library;

import '../contracts/model.dart';
import 'unicode.dart';

/// Letters, digits, `-` and `_`, starting and ending with a letter or digit;
/// at most 39 characters, as on GitHub.
final handlePattern = RegExp(
  r'^[A-Za-z0-9](?:[A-Za-z0-9_-]{0,37}[A-Za-z0-9])?$',
);
const _handleLength = 39;

/// `@handle` in text. Not inside a word, an email (`ada@example.com`) or a
/// path (`/@ada`), and not followed by more of one (`@ada.lovelace`,
/// `@ada@example.com`); a full stop or dash ending a sentence is no part of it.
final mentionPattern = RegExp(
  r'(?<![\p{L}\p{N}_@./\\:+-])@([A-Za-z0-9](?:[A-Za-z0-9_-]*[A-Za-z0-9])?)(?![\p{L}\p{N}_@]|[.-][\p{L}\p{N}])',
  unicode: true,
);

/// "Ada Lovelace" → "ada-lovelace", "Zoë.O'Brien" → "zoe-o-brien": a valid
/// handle, or "" when nothing is left.
String handleSlug(String text) {
  final slug = withoutMarks(nfd(text))
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  return slug
      .substring(0, slug.length < _handleLength ? slug.length : _handleLength)
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

String _key(String text) => text.trim().toLowerCase();

/// Lookups of people by handle, and by any name, email or alias that means
/// them; build once per list.
class PeopleIndex {
  PeopleIndex(this.people) {
    void add(Map<String, Person> map, String name, Person person) {
      if (_key(name).isNotEmpty) map.putIfAbsent(_key(name), () => person);
    }

    for (final person in people) {
      byHandle[_key(person.handle)] = person;
      for (final name in [person.name, person.email ?? '', ...person.aliases]) {
        add(byKey, name, person);
      }
      for (final alias in person.aliases) {
        add(byAlias, alias, person);
      }
    }
  }

  final List<Person> people;
  final byHandle = <String, Person>{};

  /// Names, emails and aliases.
  final byKey = <String, Person>{};
  final byAlias = <String, Person>{};

  /// The person [text] names: a handle (with or without `@`), a name, an
  /// email or an alias, ignoring case.
  Person? find(String text) {
    final name = _key(text);
    if (name.isEmpty) return null;
    return byHandle[name.replaceFirst(RegExp('^@'), '')] ?? byKey[name];
  }

  /// The person an `@mention` means: by handle, or by an alias that is
  /// shaped like one.
  Person? mentioned(String handle) {
    final name = _key(handle);
    return byHandle[name] ??
        (handlePattern.hasMatch(handle) ? byAlias[name] : null);
  }
}
