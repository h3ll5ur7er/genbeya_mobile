/// Comments on a task live at the end of its file, below a "## Comments"
/// heading, one "### Author — 2026-10-10 14:32+02:00" heading each. Port of
/// Genbeya's `src/engines/task-comments.ts`.
library;

import '../contracts/model.dart';

const _sectionHeading = '## Comments';
final _section = RegExp(r'^## Comments[ \t]*$');
final _comment = RegExp(
  r'^### (\S.*?) [—–-] (\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?)(Z|[+-]\d{2}:?\d{2})?[ \t]*$',
);
final _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})');

class CommentBlock {
  const CommentBlock({
    required this.comment,
    required this.heading,
    required this.text,
  });

  final TaskComment comment;
  final String heading;

  /// The comment's whole text as written.
  final String text;
}

class SplitBody {
  const SplitBody({required this.description, required this.blocks});

  /// The Markdown above the comments, as written.
  final String description;
  final List<CommentBlock> blocks;
}

bool _isBlank(String line) => line.trim().isEmpty;

List<String> _trimBlankLines(List<String> lines) {
  var start = 0;
  var end = lines.length;
  while (start < end && _isBlank(lines[start])) {
    start++;
  }
  while (end > start && _isBlank(lines[end - 1])) {
    end--;
  }
  return lines.sublist(start, end);
}

TaskComment _commentOf(RegExpMatch match, String body) {
  final offset = match[4];
  final zone = offset != null && offset != 'Z' && !offset.contains(':')
      ? '${offset.substring(0, 3)}:${offset.substring(3)}'
      : (offset ?? '');
  return TaskComment(
    author: match[1]!.trim(),
    date: '${match[2]}T${match[3]}$zone',
    body: body,
  );
}

/// Which lines lie in a fenced code block, fences included, and the fence still open at the end.
({List<bool> fenced, String? open}) _fences(List<String> lines) {
  final fenced = <bool>[];
  String? open;
  for (final line in lines) {
    final fence = _fence.firstMatch(line);
    final rest = fence != null ? line.substring(fence[0]!.length) : '';
    if (open != null) {
      fenced.add(true);
      if (fence != null &&
          fence[1]![0] == open[0] &&
          fence[1]!.length >= open.length &&
          rest.trim().isEmpty) {
        open = null;
      }
    } else if (fence != null && !(fence[1]![0] == '`' && rest.contains('`'))) {
      fenced.add(true);
      open = fence[1]!;
    } else {
      fenced.add(false);
    }
  }
  return (fenced: fenced, open: open);
}

String commentHeading(String author, String timestamp) =>
    '### $author — $timestamp';

String _pad(int value) => value.toString().padLeft(2, '0');

/// [date] to the minute, with its UTC offset: "2026-10-10 14:32+02:00", as
/// comments and replies are signed (Genbeya's `timestampOf`).
String timestampOf(DateTime date) {
  final offset = date.timeZoneOffset.inMinutes;
  final zone =
      '${offset < 0 ? '-' : '+'}${_pad(offset.abs() ~/ 60)}:${_pad(offset.abs() % 60)}';
  return '${date.year}-${_pad(date.month)}-${_pad(date.day)} ${_pad(date.hour)}:${_pad(date.minute)}$zone';
}

String commentBlock(String heading, String body) =>
    body.isNotEmpty ? '$heading\n\n$body' : heading;

/// The description and the comments of a task's body.
SplitBody splitComments(String body) {
  final lines = body
      .split('\n')
      .map(
        (line) =>
            line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
      )
      .toList();
  final fenced = _fences(lines).fenced;
  var start = -1;
  var next = -1;
  for (var i = lines.length - 1; i >= 0; i--) {
    if (!fenced[i] &&
        _section.hasMatch(lines[i]) &&
        next >= 0 &&
        !fenced[next] &&
        _comment.hasMatch(lines[next])) {
      start = i;
    }
    if (!_isBlank(lines[i])) next = i;
  }
  if (start < 0) return SplitBody(description: body, blocks: const []);
  final before = body.split('\n').sublist(0, start).join('\n').trimRight();
  final blocks = <CommentBlock>[];
  RegExpMatch? match;
  var heading = '';
  var content = <String>[];
  void close() {
    final current = match;
    if (current == null) return;
    final text = _trimBlankLines(content).join('\n');
    blocks.add(
      CommentBlock(
        comment: _commentOf(current, text),
        heading: heading,
        text: commentBlock(heading, text),
      ),
    );
  }

  for (var i = start + 1; i < lines.length; i++) {
    final line = lines[i];
    final found = fenced[i] ? null : _comment.firstMatch(line);
    if (found != null) {
      close();
      match = found;
      heading = line.trimRight();
      content = [];
    } else {
      content.add(line);
    }
  }
  close();
  return SplitBody(
    description: before.isNotEmpty
        ? '$before${body.contains('\r\n') ? '\r\n' : '\n'}'
        : '',
    blocks: blocks,
  );
}

/// `description` followed by the comment `blocks`; no section without comments.
String joinComments(String description, List<String> blocks) {
  final text = description.trimRight();
  if (blocks.isEmpty) return text.isNotEmpty ? '$text\n' : '';
  return '${text.isNotEmpty ? '$text\n\n' : ''}$_sectionHeading\n\n${blocks.join('\n\n')}\n';
}

/// Escapes lines that would read as a comment heading, and closes a code fence left open.
String protectHeadings(String text) {
  final lines = text.split('\n');
  final fences = _fences([
    for (final line in lines)
      line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
  ]);
  final protectedText = [
    for (var i = 0; i < lines.length; i++)
      !fences.fenced[i] &&
              _comment.hasMatch(
                lines[i].endsWith('\r')
                    ? lines[i].substring(0, lines[i].length - 1)
                    : lines[i],
              )
          ? '\\${lines[i]}'
          : lines[i],
  ].join('\n');
  final open = fences.open;
  return open != null
      ? '$protectedText${protectedText.endsWith('\n') ? '' : '\n'}$open'
      : protectedText;
}
