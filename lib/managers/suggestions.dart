/// What `@`, `[[` and `//` offer while writing a comment, as desktop's
/// editor offers it (`mention-suggestions.ts`, `references.ts`
/// `referenceCandidates`, `smart-dates.ts`, `ui/calendar-date.ts`): the
/// same triggers, the same candidates, and the same text inserted, so a
/// comment written on the phone reads as one written on desktop.
library;

import '../contracts/model.dart';
import '../engines/collation.dart';

/// `@` and what follows it at the end of the text before the cursor; not
/// inside a word or an email.
final mentionTrigger = RegExp(
  r'(?<![\p{L}\p{N}_@./\\:+-])@([\p{L}\p{N}_.-]*)$',
  unicode: true,
);

/// The text after an unclosed `[[` on the current line.
final referenceTrigger = RegExp(r'\[\[([^\]|\n]*)$');

/// `//` and what follows it, not after a letter, digit or `:` (URLs).
final dateTrigger = RegExp(
  r'(?<![\p{L}\p{N}_:/])\/\/([\p{L}\p{N} -]*)$',
  unicode: true,
);

const _mentionLimit = 30;

int? _rank(Person person, String query) {
  if (query.isEmpty) return 3;
  final handle = person.handle.toLowerCase();
  final name = person.name.toLowerCase();
  final words = name.split(RegExp(r'\s+'));
  final email = (person.email ?? '').toLowerCase();
  if (handle.startsWith(query)) return 0;
  if (name.startsWith(query) || words.any((w) => w.startsWith(query))) {
    return 1;
  }
  if (email.startsWith(query) ||
      person.aliases.any((a) => a.toLowerCase().startsWith(query))) {
    return 2;
  }
  return handle.contains(query) || name.contains(query) || email.contains(query)
      ? 3
      : null;
}

/// The people [query] finds, best first; people with more commits first
/// among equals.
List<Person> mentionSuggestions(List<Person> people, String query) {
  final text = query.trim().toLowerCase();
  final ranked = [
    for (final person in people)
      if (_rank(person, text) case final rank?) (person: person, rank: rank),
  ];
  return stableSorted(
    ranked,
    (a, b) => a.rank != b.rank
        ? a.rank - b.rank
        : a.person.commits != b.person.commits
        ? b.person.commits - a.person.commits
        : collateFull(a.person.name, b.person.name),
  ).take(_mentionLimit).map((e) => e.person).toList();
}

/// What picking [person] inserts: the mention, and a space unless one follows.
String mentionText(Person person, String next) =>
    '@${person.handle}${RegExp(r'^\s').hasMatch(next) ? '' : ' '}';

/// A `[[` candidate: what goes between the brackets, what the list shows.
class ReferenceCandidate {
  const ReferenceCandidate({
    required this.target,
    required this.label,
    required this.kind,
    this.detail,
  });

  final String target;
  final String label;
  final String? detail;

  /// `task`, `page` or `file`.
  final String kind;
}

String normalizeTitle(String title) =>
    title.toLowerCase().replaceAll(RegExp(r'[-_\s]+'), ' ').trim();

/// Tasks by ID and title, pages by title (by path when titles repeat), and
/// the other files of the repository.
List<ReferenceCandidate> referenceCandidates({
  required List<Task> tasks,
  required List<({String path, String title})> pages,
  required List<String> files,
  required String wikiRoot,
}) {
  final titles = <String, int>{};
  for (final page in pages) {
    final key = normalizeTitle(page.title);
    titles[key] = (titles[key] ?? 0) + 1;
  }
  String below(String path) => path
      .substring(wikiRoot.isEmpty ? 0 : wikiRoot.length + 1)
      .replaceFirst(RegExp(r'\.md$'), '');
  final shown = {...pages.map((p) => p.path), ...tasks.map((t) => t.path)};
  return [
    for (final task in tasks)
      ReferenceCandidate(
        target: task.id,
        label: '${task.id} ${task.title}',
        detail: task.status.replaceAll(RegExp(r'[-_]+'), ' '),
        kind: 'task',
      ),
    for (final page in pages)
      titles[normalizeTitle(page.title)] == 1
          ? ReferenceCandidate(
              target: page.title,
              label: page.title,
              detail: 'page',
              kind: 'page',
            )
          : ReferenceCandidate(
              target: below(page.path),
              label: below(page.path),
              detail: 'page',
              kind: 'page',
            ),
    for (final path in files)
      if (!shown.contains(path))
        ReferenceCandidate(target: path, label: path, kind: 'file'),
  ];
}

/// What picking [candidate] inserts after `[[`: its target and the closing
/// brackets, unless [next] already starts with them.
String referenceText(ReferenceCandidate candidate, String next) =>
    next.startsWith(']]') ? candidate.target : '${candidate.target}]]';

// ---------- Dates (calendar-date.ts, smart-dates.ts) ----------

final _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Days since the epoch of a valid ISO date; null otherwise.
int? dayNumber(String iso) {
  final match = _isoDate.firstMatch(iso);
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
}

bool isDate(String iso) => dayNumber(iso) != null;

String _isoOf(int days) => DateTime.fromMillisecondsSinceEpoch(
  days * Duration.millisecondsPerDay,
  isUtc: true,
).toIso8601String().substring(0, 10);

/// Today on this phone's calendar.
String todayIso([DateTime? now]) {
  final date = now ?? DateTime.now();
  String pad(int v) => v.toString().padLeft(2, '0');
  return '${date.year}-${pad(date.month)}-${pad(date.day)}';
}

String addDays(String iso, int days) => _isoOf(dayNumber(iso)! + days);

/// The same day [months] later, or the month's last day when it is shorter.
String addMonths(String iso, int months) {
  final parts = iso.split('-').map(int.parse).toList();
  final first = DateTime.utc(parts[0], parts[1] + months);
  final last = DateTime.utc(first.year, first.month + 1, 0).day;
  final date = DateTime.utc(
    first.year,
    first.month,
    parts[2] < last ? parts[2] : last,
  );
  return _isoOf(date.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay);
}

String endOfMonth(String iso) {
  final parts = iso.split('-').map(int.parse).toList();
  final date = DateTime.utc(parts[0], parts[1] + 1, 0);
  return _isoOf(date.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay);
}

/// 0 for Sunday to 6 for Saturday.
int weekdayOf(String iso) =>
    DateTime.fromMillisecondsSinceEpoch(
      dayNumber(iso)! * Duration.millisecondsPerDay,
      isUtc: true,
    ).weekday %
    7;

/// The next [day] (0 Sunday … 6 Saturday) after [iso]; a week later when [iso] is one.
String nextWeekday(String iso, int day) =>
    addDays(iso, ((day - weekdayOf(iso) + 6) % 7) + 1);

/// A date `//` offers; [date] null for the calendar, which asks.
typedef DateSuggestion = ({String label, String? date});

const _weekdays = [
  'sunday',
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
];

final _units = <(RegExp, String Function(String, int), String, String)>[
  (RegExp(r'^d(a(ys?)?)?$'), addDays, 'day', 'days'),
  (RegExp(r'^w(e(e(ks?)?)?)?$'), (f, c) => addDays(f, 7 * c), 'week', 'weeks'),
  (RegExp(r'^m(o(n(t(hs?)?)?)?)?$'), addMonths, 'month', 'months'),
  (
    RegExp(r'^y(e(a(rs?)?)?)?$'),
    (f, c) => addMonths(f, 12 * c),
    'year',
    'years',
  ),
];

List<({String label, String? date, List<String> words})> _presets(
  String today,
) => [
  (label: 'Today', date: today, words: ['today', 'now']),
  (label: 'Tomorrow', date: addDays(today, 1), words: ['tomorrow', 'tmr']),
  (
    label: 'Next Monday',
    date: nextWeekday(today, 1),
    words: ['next monday', 'monday'],
  ),
  (
    label: 'In a week',
    date: addDays(today, 7),
    words: ['in a week', 'week', 'next week'],
  ),
  (
    label: 'End of month',
    date: endOfMonth(today),
    words: ['end of month', 'eom', 'month'],
  ),
  (
    label: 'Pick a date…',
    date: null,
    words: ['pick a date', 'calendar', 'date'],
  ),
];

/// Dates [query] names, best first; everything usual for an empty query,
/// nothing for one that names no date. [formatDate] labels a typed date
/// (desktop shows it in the user's language, with the weekday).
List<DateSuggestion> dateSuggestions(
  String query,
  String today, {
  String Function(String iso)? formatDate,
}) {
  final text = query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final found = <DateSuggestion>[];
  if (isDate(text)) {
    found.add((label: formatDate?.call(text) ?? text, date: text));
  }
  final day = text.replaceFirst(RegExp(r'^next '), '');
  if (day.length >= 2) {
    for (final (index, name) in _weekdays.indexed) {
      if (name.startsWith(day)) {
        found.add((
          label: '${name[0].toUpperCase()}${name.substring(1)}',
          date: nextWeekday(today, index),
        ));
      }
    }
  }
  final distance = RegExp(r'^(?:in )?(\d{1,3}) ?([a-z]*)$').firstMatch(text);
  if (distance != null) {
    final count = int.parse(distance[1]!);
    for (final (unit, add, one, many) in _units) {
      if (unit.hasMatch(distance[2]!) || distance[2]!.isEmpty) {
        found.add((
          label: 'In $count ${count == 1 ? one : many}',
          date: add(today, count),
        ));
      }
    }
  }
  final presets = _presets(today);
  final usual = [
    for (final p in presets)
      if (text.isEmpty || p.words.any((w) => w.startsWith(text)))
        (label: p.label, date: p.date),
  ];
  final suggestions = [...found, ...usual];
  final dates = <DateSuggestion>[
    for (final (index, s) in suggestions.indexed)
      if (s.date != null &&
          suggestions.indexWhere((o) => o.date == s.date) == index)
        s,
  ];
  final calendar = presets.last;
  return dates.isNotEmpty || usual.isNotEmpty
      ? [...dates, (label: calendar.label, date: calendar.date)]
      : [];
}
