/// The byte order mark and line ending of a text file, so saves that rewrite a
/// whole file keep both as the file had them. Port of Genbeya's
/// `src/utilities/text-style.ts`.
library;

const _bom = '﻿';

class TextStyle {
  const TextStyle({required this.bom, required this.eol});

  final bool bom;

  /// "\n" or "\r\n".
  final String eol;
}

/// New files: no byte order mark, LF line endings.
const lfStyle = TextStyle(bom: false, eol: '\n');

String withoutByteOrderMark(String text) =>
    text.startsWith(_bom) ? text.substring(1) : text;

/// The style of `text`; its first line ending decides.
TextStyle textStyleOf(String text) {
  final end = text.indexOf('\n');
  return TextStyle(
    bom: text.startsWith(_bom),
    eol: end > 0 && text[end - 1] == '\r' ? '\r\n' : '\n',
  );
}

/// `text`, whatever its line endings and mark, in `style`.
String applyTextStyle(String text, TextStyle style) =>
    (style.bom ? _bom : '') +
    withoutByteOrderMark(text).replaceAll(RegExp(r'\r?\n'), style.eol);
