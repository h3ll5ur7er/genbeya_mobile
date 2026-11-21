/// Repository-relative paths: slash-separated, inside the working tree, never
/// into `.git`. Port of Genbeya's `src/utilities/repository-path.ts`.
library;

final _windowsReserved = RegExp(
  r'^(con|prn|aux|nul|com\d|lpt\d)(\..*)?$',
  caseSensitive: false,
);
const _maxLength = 4096;

bool _unsafeSegment(String segment, bool windows) {
  if (segment.isEmpty || segment == '.' || segment == '..') return true;
  if (segment.replaceAll(RegExp(r'[. ]+$'), '').toLowerCase() == '.git') {
    return true;
  }
  return windows &&
      (RegExp(r'^git~\d+$', caseSensitive: false).hasMatch(segment) ||
          RegExp(r'[. ]$').hasMatch(segment) ||
          RegExp(r'[:<>"|?*\x00-\x1f]').hasMatch(segment) ||
          _windowsReserved.hasMatch(segment));
}

/// Returns the path unchanged when it is a safe repository-relative path; throws otherwise.
String validateRepositoryPath(Object? value, bool windows) {
  if (value is! String || value.length > _maxLength || value.contains('\x00')) {
    throw const FormatException('Invalid path.');
  }
  if (value.startsWith('/') ||
      RegExp(r'^[a-z]:', caseSensitive: false).hasMatch(value) ||
      value.contains(r'\') ||
      value.split('/').any((segment) => _unsafeSegment(segment, windows))) {
    throw FormatException(
      '${value.isEmpty ? 'This path' : value} is not a valid path inside the repository.',
    );
  }
  return value;
}

/// True when `path` lies below `root` (a folder path; "" is the repository root).
bool within(String path, String root) =>
    root == '' || root == '.' || path.startsWith('$root/');
