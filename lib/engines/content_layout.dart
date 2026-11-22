/// Where wiki pages, tasks, settings and pull requests live: in the checkout,
/// or on the shared content branch (`genbeya`, or what `genbeya.branch`
/// names). The branch's `.genbeya-content` file, in Git's config format,
/// lists the areas it holds; a branch without it holds every area. As in
/// Genbeya's `src/access/content/content-store.ts`, which reads the file
/// with `git config --blob <commit>:.genbeya-content --list`.
library;

/// The content areas, as Genbeya's `CONTENT_AREAS`.
const contentAreas = ['wiki', 'tasks', 'settings', 'pulls'];

const defaultContentBranch = 'genbeya';
const areasFile = '.genbeya-content';

enum StorageMode { checkout, branch }

typedef AreaModes = Map<String, StorageMode>;

AreaModes everyArea(StorageMode mode) => {
  for (final area in contentAreas) area: mode,
};

/// The areas a content branch holds, from its `.genbeya-content` (null when
/// it has none): every area when the file is missing or Git can't read it,
/// else `branch` for the areas set to it and `checkout` for the rest.
AreaModes areasOf(String? file) {
  if (file == null) return everyArea(StorageMode.branch);
  final entries = parseGitConfig(file);
  if (entries == null) return everyArea(StorageMode.branch);
  // `new Map(lines)`: the last value of a key wins.
  // Genbeya trims each value, and reads a key without `=` as no value.
  final values = {for (final (key, value) in entries) key: value?.trim()};
  return {
    for (final area in contentAreas)
      area: values['areas.$area'] == 'branch'
          ? StorageMode.branch
          : StorageMode.checkout,
  };
}

final _sectionName = RegExp(r'^[A-Za-z0-9.-]+$');
final _keyName = RegExp(r'[A-Za-z][A-Za-z0-9-]*');

/// The entries of a file in Git's config format as `git config --list`
/// prints them (`section.key`, lower case; `section.sub.key` keeps the
/// subsection's case), with the value, or null for a key without `=`.
/// Null when Git would refuse the file.
List<(String, String?)>? parseGitConfig(String text) {
  final entries = <(String, String?)>[];
  var source = text;
  if (source.startsWith('﻿')) source = source.substring(1);
  String? section;
  var i = 0;
  final n = source.length;

  bool isSpace(String c) => c == ' ' || c == '\t';
  void skipSpace() {
    while (i < n && isSpace(source[i])) {
      i++;
    }
  }

  void skipLine() {
    while (i < n && source[i] != '\n') {
      i++;
    }
    if (i < n) i++;
  }

  bool atLineEnd() =>
      i >= n ||
      source[i] == '\n' ||
      (source[i] == '\r' && i + 1 < n && source[i + 1] == '\n') ||
      source[i] == '#' ||
      source[i] == ';';

  while (i < n) {
    skipSpace();
    if (i >= n) break;
    final c = source[i];
    if (c == '\n' || c == '\r') {
      i++;
      continue;
    }
    if (c == '#' || c == ';') {
      skipLine();
      continue;
    }
    if (c == '[') {
      final end = source.indexOf(']', i);
      if (end < 0) return null;
      final header = source.substring(i + 1, end);
      final quote = header.indexOf('"');
      if (quote < 0) {
        final name = header.trim();
        if (!_sectionName.hasMatch(name) || header != name) return null;
        // `[section.sub]` is the old spelling of a subsection, lower-cased.
        section = name.toLowerCase();
      } else {
        final name = header.substring(0, quote).trimRight();
        if (!_sectionName.hasMatch(name) || name.contains('.')) return null;
        if (!header.endsWith('"') || header.length - 1 == quote) return null;
        final sub = StringBuffer();
        for (var k = quote + 1; k < header.length - 1; k++) {
          var ch = header[k];
          if (ch == '\n') return null;
          if (ch == '"') return null;
          if (ch == r'\') {
            k++;
            if (k >= header.length - 1) return null;
            ch = header[k];
          }
          sub.write(ch);
        }
        section = '${name.toLowerCase()}.$sub';
      }
      i = end + 1;
      skipSpace();
      // Git reads a variable on the header's line too: `[areas] wiki = branch`.
      if (atLineEnd()) skipLine();
      continue;
    }
    // A variable: name, then `= value` or nothing.
    final match = _keyName.matchAsPrefix(source, i);
    if (match == null) return null;
    // Git takes variables before any section too; they belong to no area.
    final key = '${section ?? ''}.${match[0]!.toLowerCase()}';
    i = match.end;
    skipSpace();
    if (atLineEnd()) {
      entries.add((key, null));
      skipLine();
      continue;
    }
    if (source[i] != '=') return null;
    i++;
    final value = _readValue(source, i);
    if (value == null) return null;
    entries.add((key, value.$1));
    i = value.$2;
  }
  return entries;
}

/// A value after `=`: up to the line's end or a comment outside quotes,
/// spaces trimmed except inside quotes, escapes and continued lines read.
/// The value and where the next line starts, or null when Git would refuse it.
(String, int)? _readValue(String source, int start) {
  final out = StringBuffer();
  var i = start;
  final n = source.length;
  var quoted = false;
  // Spaces are kept only once more text follows them.
  var pending = StringBuffer();
  var started = false;
  while (i < n) {
    final c = source[i];
    if (c == '\n' || (c == '\r' && i + 1 < n && source[i + 1] == '\n')) {
      if (quoted) return null;
      break;
    }
    if (!quoted && (c == '#' || c == ';')) {
      while (i < n && source[i] != '\n') {
        i++;
      }
      break;
    }
    if (c == ' ' || c == '\t') {
      if (started || quoted) pending.write(c);
      i++;
      continue;
    }
    if (c == '"') {
      quoted = !quoted;
      started = true;
      out.write(pending);
      pending = StringBuffer();
      i++;
      continue;
    }
    if (c == r'\') {
      if (i + 1 >= n) return null;
      final next = source[i + 1];
      if (next == '\n') {
        i += 2;
        continue;
      }
      if (next == '\r' && i + 2 < n && source[i + 2] == '\n') {
        i += 3;
        continue;
      }
      final escaped = switch (next) {
        'n' => '\n',
        't' => '\t',
        'b' => '\b',
        '"' => '"',
        r'\' => r'\',
        _ => null,
      };
      if (escaped == null) return null;
      out
        ..write(pending)
        ..write(escaped);
      pending = StringBuffer();
      started = true;
      i += 2;
      continue;
    }
    out
      ..write(pending)
      ..write(c);
    pending = StringBuffer();
    started = true;
    i++;
  }
  if (quoted) return null;
  if (i < n && source[i] == '\r') i++;
  if (i < n && source[i] == '\n') i++;
  return (out.toString(), i);
}
