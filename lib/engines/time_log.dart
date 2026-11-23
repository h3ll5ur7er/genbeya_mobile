/// A task's `## Time log` section. The split that activity uses, ported
/// from `splitTimeLog` in Genbeya's `src/utilities/planning.ts`; reading and
/// adding entries come with time tracking ([[GM-18]]).
library;

final _timeLog = RegExp(r'^##\s+Time log\s*$', caseSensitive: false);
final _sectionEnd = RegExp(r'^#{1,2}\s');
final _fence = RegExp(r'^\s*(`{3,}|~{3,})');
final _listItem = RegExp(r'^\s*[-*+]\s+');

/// Whether each line is inside a fenced code block, fences included.
List<bool> _fencedLines(List<String> lines) {
  String? fence;
  return [
    for (final line in lines)
      () {
        final marker = _fence.firstMatch(line)?.group(1);
        if (marker == null) return fence != null;
        if (fence == null) {
          fence = marker;
        } else if (marker[0] == fence![0] && marker.length >= fence!.length) {
          fence = null;
        }
        return true;
      }(),
  ];
}

/// The section from its heading to the next heading of level 1 or 2, and
/// the lines of its entries: list items outside code blocks.
({int start, int end, List<int> items})? _section(List<String> lines) {
  final fenced = _fencedLines(lines);
  var start = -1;
  for (var i = 0; i < lines.length; i++) {
    if (!fenced[i] && _timeLog.hasMatch(lines[i])) {
      start = i;
      break;
    }
  }
  if (start < 0) return null;
  var end = lines.length;
  for (var i = start + 1; i < lines.length; i++) {
    if (!fenced[i] && _sectionEnd.hasMatch(lines[i])) {
      end = i;
      break;
    }
  }
  return (
    start: start,
    end: end,
    items: [
      for (var i = start + 1; i < end; i++)
        if (!fenced[i] && _listItem.hasMatch(lines[i])) i,
    ],
  );
}

/// The time log's list items as written, and the description without the
/// section, for comparing versions of a task.
({String description, List<String> lines}) splitTimeLog(String body) {
  final lines = body.split(RegExp(r'\r?\n'));
  final section = _section(lines);
  if (section == null) return (description: body, lines: const []);
  return (
    description: [
      ...lines.sublist(0, section.start),
      ...lines.sublist(section.end),
    ].join('\n'),
    lines: [for (final index in section.items) lines[index].trim()],
  );
}

/// [body] with [lines] (time log list items, as written) after the last
/// entry of its time log section; the body as it is without one or without
/// lines to add. For the Genbeya merge, which keeps both sides' entries.
String appendTimeLogLines(String body, List<String> lines) {
  if (lines.isEmpty) return body;
  final newline = body.contains('\r\n') ? '\r\n' : '\n';
  final split = body.split(RegExp(r'\r?\n'));
  final section = _section(split);
  if (section == null) return body;
  final at = section.items.isEmpty ? section.start + 1 : section.items.last + 1;
  return [
    ...split.sublist(0, at),
    if (section.items.isEmpty) '',
    ...lines,
    ...split.sublist(at),
  ].join(newline);
}
