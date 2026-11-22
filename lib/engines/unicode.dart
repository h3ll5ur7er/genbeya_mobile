/// The parts of Unicode normalization Genbeya's rules use and Dart lacks:
/// `normalize("NFD")` and `\p{M}`, for the code points in the generated
/// table (tool/conformance/make-collation.mjs); others pass unchanged.
library;

import 'collation_table.dart';

/// Canonical decomposition (NFD) of the letters names use.
String nfd(String text) {
  final out = StringBuffer();
  for (final code in text.runes) {
    final parts = unicodeDecompositions[code];
    if (parts == null) {
      out.writeCharCode(code);
    } else {
      parts.forEach(out.writeCharCode);
    }
  }
  return out.toString();
}

/// Whether [code] is a combining mark (`\p{M}`).
bool isMark(int code) {
  var low = 0;
  var high = unicodeMarkRanges.length ~/ 2 - 1;
  while (low <= high) {
    final middle = (low + high) ~/ 2;
    if (code < unicodeMarkRanges[middle * 2]) {
      high = middle - 1;
    } else if (code > unicodeMarkRanges[middle * 2 + 1]) {
      low = middle + 1;
    } else {
      return true;
    }
  }
  return false;
}

/// [text] without its combining marks: `text.replace(/\p{M}/gu, "")`.
String withoutMarks(String text) =>
    String.fromCharCodes(text.runes.where((code) => !isMark(code)));
