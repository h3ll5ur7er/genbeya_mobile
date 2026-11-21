/// Ticking a task-list checkbox in Markdown, as Genbeya desktop does it
/// (`toggleCheckboxAt` in src/client/app/markdown/task-checkbox.ts, and the
/// frontmatter rule of `stripFrontmatter` in src/client/app/core/file-resource.ts),
/// plus the stricter check this app makes first, because here the offset
/// comes from a web view whose messages are untrusted ([[Call chains#c5-render-a-page]]).
///
/// Offsets count UTF-16 code units, in Dart as in JavaScript.
library;

final _frontmatter = RegExp(r'^---\r?\n[\s\S]*?\r?\n---[ \t]*\r?\n');
final _checkbox = RegExp(r'\[( |x|X)\]');

/// A task list item's start as the renderer reports it: the list marker,
/// spaces, then the checkbox.
final _item = RegExp(r'(?:[-*+]|\d{1,9}[.)])[ \t]+\[[ xX]\]');

/// A page's text without its frontmatter: what Genbeya renders, and what
/// the offsets of its checkboxes count in.
String stripFrontmatter(String text) => text.replaceFirst(_frontmatter, '');

/// Flips the first checkbox (`[ ]` or `[x]`) at or after [offset]; the
/// source unchanged when there is none. Genbeya's own rule, kept as lenient
/// as it is so that the bytes written are the same.
String toggleCheckboxAt(String source, int offset) {
  if (offset < 0) throw RangeError.value(offset, 'offset');
  if (offset > source.length) return source;
  final match = _checkbox.firstMatch(source.substring(offset));
  if (match == null) return source;
  final at = offset + match.start + 1;
  return source.substring(0, at) +
      (match[1] == ' ' ? 'x' : ' ') +
      source.substring(at + 1);
}

/// Whether a task list item, with its checkbox, starts exactly at [offset].
/// The host writes only then: a stale or forged offset is refused rather
/// than ticking whatever checkbox comes next.
bool isCheckboxItemAt(String source, int offset) =>
    offset >= 0 &&
    offset <= source.length &&
    _item.matchAsPrefix(source, offset) != null;

/// A page's text with the checkbox ticked whose item starts at [offset] in
/// the rendered page ([stripFrontmatter]); null when no item starts there.
String? togglePageCheckbox(String content, int offset) {
  final at = content.length - stripFrontmatter(content).length + offset;
  if (offset < 0 || !isCheckboxItemAt(content, at)) return null;
  return toggleCheckboxAt(content, at);
}

/// A task's description with the checkbox ticked whose item starts at
/// [offset]; null when no item starts there. The task engine writes it.
String? toggleDescriptionCheckbox(String description, int offset) {
  if (!isCheckboxItemAt(description, offset)) return null;
  return toggleCheckboxAt(description, offset);
}
