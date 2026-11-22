/// The rules of full-text search: what a valid query is, which list a file
/// shows in, and how long lines are shortened around the match. Port of
/// Genbeya's `src/engines/search-engine.ts`; the core finds the lines.
library;

import 'repository_path.dart';
import 'task_engine.dart';

const searchQueryLimit = 200;
const searchFilesPerArea = 30;
const searchMatchesPerFile = 10;
const searchLineLength = 200;

/// Characters kept before the first match when a long line is shortened.
const _lead = 40;

class SearchQuery {
  const SearchQuery({
    required this.text,
    this.caseSensitive = false,
    this.regex = false,
    this.wholeWord = false,
  });

  final String text;
  final bool caseSensitive;
  final bool regex;
  final bool wholeWord;
}

class SearchException implements Exception {
  const SearchException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Characters [start] up to [end] of a line's text, in UTF-16 units.
typedef SearchRange = ({int start, int end});

class SearchEngine {
  SearchQuery validate(
    String text, {
    bool caseSensitive = false,
    bool regex = false,
    bool wholeWord = false,
  }) {
    if (text.trim().isEmpty) {
      throw const SearchException('Enter text to search for.');
    }
    if (text.length > searchQueryLimit) {
      throw const SearchException(
        'Search for at most $searchQueryLimit characters.',
      );
    }
    if (RegExp('[\r\n\u0000]').hasMatch(text)) {
      throw const SearchException('Search for text within one line.');
    }
    return SearchQuery(
      text: text,
      caseSensitive: caseSensitive,
      regex: regex,
      wholeWord: wholeWord,
    );
  }

  /// The list a file shows in: tasks and pages are Markdown files below
  /// their folders, pull requests those directly in theirs; everything
  /// else, task templates included, is code.
  String areaOf(
    String path, {
    required String wikiRoot,
    required String taskRoot,
    required String pullRoot,
  }) {
    bool markdown() => path.toLowerCase().endsWith('.md');
    if (isTaskFile(path, taskRoot)) return 'tasks';
    if (markdown() &&
        within(path, pullRoot) &&
        !path.substring(pullRoot.length + 1).contains('/')) {
      return 'pulls';
    }
    if (markdown() && within(path, wikiRoot)) return 'wiki';
    return 'code';
  }

  /// A long line shortened to the limit with "…", keeping the first match
  /// and some text before it.
  ({String text, List<SearchRange> ranges}) excerpt(
    String line,
    List<SearchRange> ranges,
  ) {
    const limit = searchLineLength;
    if (line.length <= limit) return (text: line, ranges: [...ranges]);
    final first = ranges.isEmpty ? 0 : ranges.first.start;
    final start = (first - _lead).clamp(
      0,
      line.length - limit < 0 ? 0 : line.length - limit,
    );
    final end = start + limit;
    final prefix = start > 0 ? '…' : '';
    final shift = prefix.length - start;
    return (
      text:
          prefix + line.substring(start, end) + (end < line.length ? '…' : ''),
      ranges: [
        for (final range in ranges)
          if (range.start < end && range.end > start)
            (
              start: (range.start > start ? range.start : start) + shift,
              end: (range.end < end ? range.end : end) + shift,
            ),
      ],
    );
  }
}
