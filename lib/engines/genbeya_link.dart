/// `genbeya://open?remote=<url>&task=<id>` and its siblings `page=`,
/// `file=` and `commit=`. Links come from outside (the clipboard, the
/// operating system), so parsing accepts only these keys, once each, with
/// values that name an item: never a local path as remote, never a path
/// outside the repository. Opening a link only shows the item. Port of
/// Genbeya's `src/utilities/genbeya-link.ts`.
library;

import 'remote_url.dart';
import 'repository_path.dart';

const genbeyaLinkPrefix = 'genbeya://open';
const _maxLength = 8192;
final _link = RegExp(r'^genbeya://open/?\?([^#]*)$', caseSensitive: false);
final _taskId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$');
final _commit = RegExp(r'^[0-9a-f]{7,64}$', caseSensitive: false);

/// What a link points at: `page`, `task`, `file` or `commit`, and its value.
typedef LinkItem = ({String kind, String value});

typedef GenbeyaLink = ({String remote, LinkItem item});

/// Values stay readable: slashes, colons and at signs need no escaping.
String _encode(String value) => Uri.encodeComponent(value)
    .replaceAllMapped(RegExp('%(2F|3A|40)'), (m) => Uri.decodeComponent(m[0]!));

/// The link to [item] of [remote]; credentials in the remote are left out.
String formatGenbeyaLink(String remote, LinkItem item) =>
    '$genbeyaLinkPrefix?remote=${_encode(withoutCredentials(remote))}&${item.kind}=${_encode(item.value)}';

LinkItem? _itemOf(String kind, String value) {
  String? path([bool Function(String path)? check]) {
    try {
      validateRepositoryPath(value, false);
    } on FormatException {
      return null;
    }
    return check == null || check(value) ? value : null;
  }

  switch (kind) {
    case 'task':
      return _taskId.hasMatch(value) ? (kind: kind, value: value) : null;
    case 'commit':
      return _commit.hasMatch(value)
          ? (kind: kind, value: value.toLowerCase())
          : null;
    case 'page':
      final page = path((candidate) => candidate.endsWith('.md'));
      return page == null ? null : (kind: kind, value: page);
    case 'file':
      final file = path();
      return file == null ? null : (kind: kind, value: file);
  }
  return null;
}

/// The link [text] holds, or null when it is anything else or carries
/// anything unexpected.
GenbeyaLink? parseGenbeyaLink(String text) {
  if (text.length > _maxLength) return null;
  final query = _link.firstMatch(text.trim())?.group(1);
  if (query == null || query.isEmpty) return null;
  final values = <String, String>{};
  for (final pair in query.split('&')) {
    final separator = pair.indexOf('=');
    if (separator < 0) return null;
    final key = pair.substring(0, separator);
    if (values.containsKey(key)) return null;
    try {
      values[key] = Uri.decodeComponent(pair.substring(separator + 1));
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  }
  final remote = values.remove('remote');
  if (remote == null ||
      remote.isEmpty ||
      parseRemote(remote) == null ||
      values.length != 1) {
    return null;
  }
  final entry = values.entries.single;
  final item = _itemOf(entry.key, entry.value);
  return item == null ? null : (remote: remote, item: item);
}

/// "task GENBEYA-12", "page docs/Home.md", "commit 1a2b3c4d".
String describeLinkItem(LinkItem item) =>
    '${item.kind} ${item.kind == 'commit' ? item.value.substring(0, 8) : item.value}';
