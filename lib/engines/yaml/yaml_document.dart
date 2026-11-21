/// A YAML document that can be edited and written back exactly as Genbeya
/// writes it.
///
/// Genbeya edits frontmatter and `.genbeya.yml` with the JavaScript `yaml`
/// package (2.9.1): `parseDocument`, `set`, `delete`, then
/// `toString({ flowCollectionPadding: false })`. That re-renders the whole
/// document: comments and styles are kept, spacing and indentation are
/// normalised, long quoted strings are folded. This file reproduces it:
///
/// - parsing uses `package:yaml` for values, styles and spans, and attaches
///   comments and blank lines the way `yaml`'s composer does
///   (`resolve-props.js`, `composer.js` `parsePrelude`);
/// - editing follows `YAMLMap.add`: a scalar keeps its node, style and
///   comments when set to another scalar;
/// - writing is a port of `yaml/dist/stringify/*.js`.
///
/// It covers what frontmatter holds: block and flow mappings and sequences,
/// scalars in every style, comments. Anchors, aliases and tags are not
/// written back.
library;

import 'dart:convert';

import 'package:yaml/yaml.dart';

import '../js.dart';

enum ScalarType { plain, quoteSingle, quoteDouble, blockLiteral, blockFolded }

abstract class YNode {
  String? commentBefore;
  String? comment;
  bool spaceBefore = false;

  /// The value as plain Dart data, as `toJS()` gives it.
  Object? toData();
}

class YScalar extends YNode {
  YScalar(
    this.value, {
    this.type,
    this.format,
    this.minFractionDigits,
    this.source,
  });

  Object? value;
  ScalarType? type;

  /// `HEX`, `OCT` or `EXP` for numbers written that way.
  String? format;
  int? minFractionDigits;

  /// The scalar as written, for booleans and nulls that keep their spelling.
  String? source;

  @override
  Object? toData() => value;
}

class YSeq extends YNode {
  YSeq(this.items, {this.flow = false});

  final List<YNode> items;
  bool flow;

  @override
  Object? toData() => [for (final item in items) item.toData()];
}

class YPair {
  YPair(this.key, this.value);

  final YScalar key;
  YNode value;
}

class YMap extends YNode {
  YMap(this.items, {this.flow = false});

  final List<YPair> items;
  bool flow;

  @override
  Object? toData() => {
    for (final pair in items) jsString(pair.key.value): pair.value.toData(),
  };

  YPair? _find(String key) {
    for (final pair in items) {
      if (pair.key.value == key) return pair;
    }
    return null;
  }

  bool has(String key) => _find(key) != null;

  /// As `YAMLMap.set`: a scalar keeps its node when set to a scalar, anything
  /// else replaces the value; new keys go last.
  void set(String key, Object? value) {
    final previous = _find(key);
    if (previous == null) {
      items.add(YPair(YScalar(key), createNode(value)));
    } else if (previous.value is YScalar && _isScalarValue(value)) {
      (previous.value as YScalar).value = value;
    } else {
      previous.value = createNode(value);
    }
  }

  void delete(String key) => items.removeWhere((pair) => pair.key.value == key);
}

class YDocument {
  YDocument(this.contents, {this.commentBefore, this.comment});

  YNode? contents;
  String? commentBefore;
  String? comment;

  Object? toData() => contents?.toData();

  /// The document as `doc.toString({ flowCollectionPadding: false })` writes it.
  @override
  String toString() => _stringifyDocument(this);
}

bool _isScalarValue(Object? value) =>
    value == null || value is String || value is num || value is bool;

/// A node for a plain value, as `doc.createNode` makes one.
YNode createNode(Object? value) {
  if (value is YNode) return value;
  if (value is List) return YSeq([for (final item in value) createNode(item)]);
  if (value is Map) {
    return YMap([
      for (final entry in value.entries)
        YPair(YScalar(entry.key.toString()), createNode(entry.value)),
    ]);
  }
  return YScalar(value);
}

class YamlDocumentException implements Exception {
  YamlDocumentException(this.message);

  final String message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Parsing

/// Parses `text` into an editable document. Throws [YamlDocumentException] on
/// invalid YAML.
YDocument parseYamlDocument(String text) {
  final YamlNode root;
  try {
    root = loadYamlNode(text);
  } on YamlException catch (error) {
    throw YamlDocumentException(error.message);
  }
  final lines = text
      .split('\n')
      .map(
        (line) =>
            line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
      )
      .toList();
  final parser = _Parser(lines);
  if (root is YamlScalar && root.value == null && root.span.length == 0) {
    final prelude = parser.prelude(0, lines.length - 1);
    return YDocument(
      null,
      commentBefore: prelude.$1.isEmpty ? null : prelude.$1,
    );
  }
  final contents = parser.node(root);
  final document = YDocument(contents);
  final firstLine = root.span.start.line;
  final prelude = parser.prelude(
    0,
    (contents is YMap && contents.items.isNotEmpty && !contents.flow
            ? firstLine
            : root.span.start.line) -
        1,
  );
  final comment = prelude.$1;
  if (comment.isNotEmpty) {
    if (prelude.$2) {
      document.commentBefore = comment;
    } else if (contents is YMap &&
        !contents.flow &&
        contents.items.isNotEmpty) {
      final key = contents.items.first.key;
      key.commentBefore = key.commentBefore == null
          ? comment
          : '$comment\n${key.commentBefore}';
    } else if (contents is YSeq &&
        !contents.flow &&
        contents.items.isNotEmpty) {
      final item = contents.items.first;
      item.commentBefore = item.commentBefore == null
          ? comment
          : '$comment\n${item.commentBefore}';
    } else {
      contents.commentBefore = contents.commentBefore == null
          ? comment
          : '$comment\n${contents.commentBefore}';
    }
  }
  final trailing = parser.gap(parser.lastLine(root) + 1, lines.length - 1).$2;
  if (trailing.isNotEmpty) {
    if (contents is YMap && !contents.flow ||
        contents is YSeq && !contents.flow) {
      contents.comment = trailing;
    } else {
      document.comment = trailing;
    }
  }
  return document;
}

class _Parser {
  _Parser(this.lines);

  final List<String> lines;

  static final _trailing = RegExp(r'^[ \t]+#(.*)$');

  bool _isBlank(String line) => line.trim().isEmpty;

  String? _commentText(String line) {
    final trimmed = line.trimLeft();
    if (!trimmed.startsWith('#')) return null;
    final text = trimmed.substring(1);
    return text.isEmpty ? ' ' : text;
  }

  /// The comment and whether an empty line followed it, as `parsePrelude`.
  (String, bool) prelude(int from, int to) {
    var comment = '';
    var atComment = false;
    var afterEmptyLine = false;
    for (var i = from; i <= to && i < lines.length; i++) {
      final text = _commentText(lines[i]);
      if (text != null) {
        comment +=
            (comment == '' ? '' : (afterEmptyLine ? '\n\n' : '\n')) + text;
        atComment = true;
        afterEmptyLine = false;
        // The line's own newline token.
        atComment = false;
      } else {
        if (!atComment) afterEmptyLine = true;
        atComment = false;
      }
    }
    return (comment, afterEmptyLine);
  }

  /// `spaceBefore` and the comment of the lines between two items, as `resolveProps`.
  (bool, String) gap(int from, int to) {
    var spaceBefore = false;
    var atNewline = true;
    var comment = '';
    var commentSep = '';
    for (var i = from; i <= to && i < lines.length; i++) {
      final line = lines[i];
      final text = _commentText(line);
      if (text != null) {
        comment = comment.isEmpty ? text : comment + commentSep + text;
        commentSep = '';
        atNewline = false;
        // Its newline token.
        commentSep += '\n';
        atNewline = true;
      } else if (_isBlank(line)) {
        if (atNewline) {
          if (comment.isNotEmpty) {
            comment += '\n';
          } else {
            spaceBefore = true;
          }
        } else {
          commentSep += '\n';
        }
        atNewline = true;
      }
    }
    return (spaceBefore, comment);
  }

  int lastLine(YamlNode node) {
    final start = node.span.start;
    final end = node.span.end;
    if (end.column == 0 && end.line > start.line) return end.line - 1;
    return end.line;
  }

  String? _trailingComment(YamlNode node) {
    final end = node.span.end;
    if (end.line >= lines.length) return null;
    final line = lines[end.line];
    if (end.column > line.length) return null;
    final match = _trailing.firstMatch(line.substring(end.column));
    if (match == null) return null;
    final text = match.group(1)!;
    return text.isEmpty ? ' ' : text;
  }

  YScalar scalar(YamlScalar node) {
    final source = node.span.text;
    final type = switch (node.style) {
      ScalarStyle.SINGLE_QUOTED => ScalarType.quoteSingle,
      ScalarStyle.DOUBLE_QUOTED => ScalarType.quoteDouble,
      ScalarStyle.LITERAL => ScalarType.blockLiteral,
      ScalarStyle.FOLDED => ScalarType.blockFolded,
      _ => ScalarType.plain,
    };
    String? format;
    int? minFractionDigits;
    final value = node.value;
    if (type == ScalarType.plain && value is num) {
      if (source.startsWith('0x')) {
        format = 'HEX';
      } else if (source.startsWith('0o')) {
        format = 'OCT';
      } else if (RegExp(
        r'^[-+]?(?:\.[0-9]+|[0-9]+(?:\.[0-9]*)?)[eE][-+]?[0-9]+$',
      ).hasMatch(source)) {
        format = 'EXP';
      } else {
        final dot = source.indexOf('.');
        if (dot != -1 && source.endsWith('0')) {
          minFractionDigits = source.length - dot - 1;
        }
      }
    }
    return YScalar(
      value,
      type: type,
      format: format,
      minFractionDigits: minFractionDigits,
      source: source,
    );
  }

  YNode node(YamlNode node) {
    if (node is YamlScalar) {
      final result = scalar(node);
      result.comment = _trailingComment(node);
      return result;
    }
    if (node is YamlList) {
      final flow = node.style == CollectionStyle.FLOW;
      final items = <YNode>[];
      var previousEnd = node.span.start.line - 1;
      for (final item in node.nodes) {
        final child = this.node(item);
        if (!flow) {
          final itemLine = item.span.start.line;
          final (space, comment) = gap(previousEnd + 1, itemLine - 1);
          child.spaceBefore = space;
          if (comment.isNotEmpty) child.commentBefore = comment;
          previousEnd = lastLine(item);
        }
        items.add(child);
      }
      final result = YSeq(items, flow: flow);
      if (flow) result.comment = _trailingComment(node);
      return result;
    }
    final map = node as YamlMap;
    final flow = map.style == CollectionStyle.FLOW;
    final pairs = <YPair>[];
    var previousEnd = -1;
    var first = true;
    for (final entry in map.nodes.entries) {
      final keyNode = entry.key as YamlNode;
      final key = keyNode is YamlScalar
          ? scalar(keyNode)
          : YScalar(keyNode.value.toString());
      final value = this.node(entry.value);
      if (!flow) {
        final keyLine = keyNode.span.start.line;
        if (!first) {
          final (space, comment) = gap(previousEnd + 1, keyLine - 1);
          key.spaceBefore = space;
          if (comment.isNotEmpty) key.commentBefore = comment;
        }
        previousEnd = lastLine(entry.value);
        if (previousEnd < keyLine) previousEnd = keyLine;
      }
      first = false;
      pairs.add(YPair(key, value));
    }
    final result = YMap(pairs, flow: flow);
    if (flow) result.comment = _trailingComment(node);
    return result;
  }
}

// ---------------------------------------------------------------------------
// Writing: a port of yaml/dist/stringify (yaml 2.9.1) with
// flowCollectionPadding: false and the other options at their defaults.

const _lineWidth = 80;
const _minContentWidth = 20;
const _doubleQuotedMinMultiLineLength = 40;
const _indentStep = '  ';

class _Ctx {
  _Ctx({
    this.indent = '',
    this.inFlow,
    this.implicitKey = false,
    this.indentAtStart,
    this.actualString = false,
    this.forceBlockIndent = false,
  });

  String indent;
  bool? inFlow;
  bool implicitKey;
  int? indentAtStart;
  bool actualString;
  bool forceBlockIndent;

  _Ctx copy({
    String? indent,
    bool? inFlow,
    bool? implicitKey,
    bool clearInFlow = false,
  }) => _Ctx(
    indent: indent ?? this.indent,
    inFlow: clearInFlow ? null : (inFlow ?? this.inFlow),
    implicitKey: implicitKey ?? this.implicitKey,
    indentAtStart: indentAtStart,
    actualString: actualString,
    forceBlockIndent: forceBlockIndent,
  );
}

typedef _Callback = void Function();

/// `text[i]` as JavaScript reads it: "" past the end.
String _at(String text, int i) => i >= 0 && i < text.length ? text[i] : '';

String _stringifyComment(String text) => text.replaceAllMapped(
  RegExp(r'^(?!$)(?: $)?', multiLine: true),
  (_) => '#',
);

String _indentComment(String comment, String indent) {
  if (RegExp(r'^\n+$').hasMatch(comment)) return comment.substring(1);
  return indent.isNotEmpty
      ? comment.replaceAllMapped(
          RegExp(r'^(?! *$)', multiLine: true),
          (_) => indent,
        )
      : comment;
}

String _lineComment(String str, String indent, String comment) =>
    str.endsWith('\n')
    ? _indentComment(comment, indent)
    : comment.contains('\n')
    ? '\n${_indentComment(comment, indent)}'
    : (str.endsWith(' ') ? '' : ' ') + comment;

String _stringifyDocument(YDocument doc) {
  final lines = <String>[];
  final ctx = _Ctx();
  if (doc.commentBefore != null && doc.commentBefore!.isNotEmpty) {
    if (lines.length != 1) lines.insert(0, '');
    lines.insert(0, _indentComment(_stringifyComment(doc.commentBefore!), ''));
  }
  var chompKeep = false;
  String? contentComment;
  final contents = doc.contents;
  if (contents != null) {
    if (contents.commentBefore != null && contents.commentBefore!.isNotEmpty) {
      lines.add(_indentComment(_stringifyComment(contents.commentBefore!), ''));
    }
    ctx.forceBlockIndent = doc.comment != null && doc.comment!.isNotEmpty;
    contentComment = contents.comment;
    var body = _stringify(
      contents,
      ctx,
      () => contentComment = null,
      contentComment != null ? null : () => chompKeep = true,
    );
    if (contentComment != null && contentComment!.isNotEmpty) {
      body += _lineComment(body, '', _stringifyComment(contentComment!));
    }
    lines.add(body);
  } else {
    lines.add(_stringifyScalarValue(YScalar(null), ctx, null, null));
  }
  var dc = doc.comment;
  if (dc != null && chompKeep) dc = dc.replaceFirst(RegExp(r'^\n+'), '');
  if (dc != null && dc.isNotEmpty) {
    if ((!chompKeep || contentComment != null) && lines.last != '') {
      lines.add('');
    }
    lines.add(_indentComment(_stringifyComment(dc), ''));
  }
  return '${lines.join('\n')}\n';
}

String _stringify(
  Object? item,
  _Ctx ctx,
  _Callback? onComment,
  _Callback? onChompKeep,
) {
  if (item is YPair) return _stringifyPair(item, ctx, onComment, onChompKeep);
  final node = createNode(item);
  if (node is YScalar) {
    return _stringifyScalarValue(node, ctx, onComment, onChompKeep);
  }
  if (node is YSeq) {
    return _stringifyCollection(
      node.items,
      node.comment,
      node.flow,
      ctx,
      blockItemPrefix: '- ',
      flowStart: '[',
      flowEnd: ']',
      itemIndent: '${ctx.indent}  ',
      onChompKeep: onChompKeep,
      onComment: onComment,
    );
  }
  final map = node as YMap;
  return _stringifyCollection(
    map.items,
    map.comment,
    map.flow,
    ctx,
    blockItemPrefix: '',
    flowStart: '{',
    flowEnd: '}',
    itemIndent: ctx.indent,
    onChompKeep: onChompKeep,
    onComment: onComment,
  );
}

String _stringifyScalarValue(
  YScalar node,
  _Ctx ctx,
  _Callback? onComment,
  _Callback? onChompKeep,
) {
  final value = node.value;
  if (value == null) {
    final source = node.source;
    return source != null && RegExp(r'^(?:~|[Nn]ull|NULL)?$').hasMatch(source)
        ? source
        : 'null';
  }
  if (value is bool) {
    final source = node.source;
    if (source != null &&
        RegExp(r'^(?:[Tt]rue|TRUE|[Ff]alse|FALSE)$').hasMatch(source)) {
      final sourceValue = source[0] == 't' || source[0] == 'T';
      if (value == sourceValue) return source;
    }
    return value ? 'true' : 'false';
  }
  if (value is num) return _stringifyNumber(node);
  final stringCtx = ctx.copy()..actualString = true;
  return _stringifyString(node, stringCtx, onComment, onChompKeep);
}

String _stringifyNumber(YScalar node) {
  final value = node.value as num;
  final isInt = isInteger(value);
  if (node.format == 'HEX' && isInt && value >= 0) {
    return '0x${value.toInt().toRadixString(16)}';
  }
  if (node.format == 'OCT' && isInt && value >= 0) {
    return '0o${value.toInt().toRadixString(8)}';
  }
  if (node.format == 'EXP' && value.isFinite) {
    return value.toDouble().toStringAsExponential();
  }
  if (!value.isFinite) {
    return value.isNaN ? '.nan' : (value < 0 ? '-.inf' : '.inf');
  }
  var n = (value is double && value == 0 && value.isNegative)
      ? '-0'
      : jsNumber(value);
  final minFractionDigits = node.minFractionDigits;
  if (node.format == null &&
      minFractionDigits != null &&
      minFractionDigits > 0 &&
      RegExp(r'^-?\d').hasMatch(n) &&
      !n.contains('e')) {
    var i = n.indexOf('.');
    if (i < 0) {
      i = n.length;
      n += '.';
    }
    var d = minFractionDigits - (n.length - i - 1);
    while (d-- > 0) {
      n += '0';
    }
  }
  return n;
}

String _stringifyPair(
  YPair pair,
  _Ctx ctx,
  _Callback? onComment,
  _Callback? onChompKeep,
) {
  final key = pair.key;
  var value = pair.value;
  String? keyComment = key.comment;
  var explicitKey =
      key.type == ScalarType.blockFolded || key.type == ScalarType.blockLiteral;
  final indent = ctx.indent;
  ctx = ctx.copy(implicitKey: !explicitKey, indent: indent + _indentStep);
  var keyCommentDone = false;
  var chompKeep = false;
  var str = _stringify(
    key,
    ctx,
    () => keyCommentDone = true,
    () => chompKeep = true,
  );
  if (!explicitKey && ctx.inFlow != true && str.length > 1024) {
    explicitKey = true;
  }
  if (keyCommentDone) keyComment = null;
  if (explicitKey) {
    if (keyComment != null) {
      str += _lineComment(str, ctx.indent, _stringifyComment(keyComment));
    }
    str = '? $str\n$indent:';
  } else {
    str = '$str:';
    if (keyComment != null) {
      str += _lineComment(str, ctx.indent, _stringifyComment(keyComment));
    }
  }
  final vsb = value.spaceBefore;
  final vcb = value.commentBefore;
  final valueComment = value.comment;
  ctx.implicitKey = false;
  if (!explicitKey && keyComment == null && value is YScalar) {
    ctx.indentAtStart = str.length + 1;
  }
  chompKeep = false;
  var valueCommentDone = false;
  final valueStr = _stringify(
    value,
    ctx,
    () => valueCommentDone = true,
    () => chompKeep = true,
  );
  var ws = ' ';
  if (keyComment != null || vsb || vcb != null) {
    ws = vsb ? '\n' : '';
    if (vcb != null) {
      ws += '\n${_indentComment(_stringifyComment(vcb), ctx.indent)}';
    }
    if (valueStr == '' && ctx.inFlow != true) {
      if (ws == '\n' && valueComment != null) ws = '\n\n';
    } else {
      ws += '\n${ctx.indent}';
    }
  } else if (!explicitKey && (value is YSeq || value is YMap)) {
    final items = value is YSeq
        ? value.items.length
        : (value as YMap).items.length;
    final valueFlow = value is YSeq ? value.flow : (value as YMap).flow;
    final hasNewline = valueStr.contains('\n');
    final flow = ctx.inFlow ?? (valueFlow || items == 0);
    if (hasNewline || !flow) ws = '\n${ctx.indent}';
  } else if (valueStr == '' || valueStr.startsWith('\n')) {
    ws = '';
  }
  str += ws + valueStr;
  if (ctx.inFlow == true) {
    if (valueCommentDone && onComment != null) onComment();
  } else if (valueComment != null && !valueCommentDone) {
    str += _lineComment(str, ctx.indent, _stringifyComment(valueComment));
  } else if (chompKeep && onChompKeep != null) {
    onChompKeep();
  }
  return str;
}

String _stringifyCollection(
  List<Object> items,
  String? comment,
  bool collectionFlow,
  _Ctx ctx, {
  required String blockItemPrefix,
  required String flowStart,
  required String flowEnd,
  required String itemIndent,
  _Callback? onChompKeep,
  _Callback? onComment,
}) {
  final flow = ctx.inFlow ?? collectionFlow;
  if (flow) {
    return _stringifyFlowCollection(items, ctx, flowStart, flowEnd, itemIndent);
  }
  final indent = ctx.indent;
  final itemCtx = ctx.copy(indent: itemIndent);
  var chompKeep = false;
  final lines = <String>[];
  for (final item in items) {
    String? itemComment;
    if (item is YNode) {
      if (!chompKeep && item.spaceBefore) lines.add('');
      _addCommentBefore(indent, lines, item.commentBefore, chompKeep);
      if (item.comment != null) itemComment = item.comment;
    } else if (item is YPair) {
      if (!chompKeep && item.key.spaceBefore) lines.add('');
      _addCommentBefore(indent, lines, item.key.commentBefore, chompKeep);
    }
    chompKeep = false;
    var str = _stringify(
      item,
      itemCtx,
      () => itemComment = null,
      () => chompKeep = true,
    );
    if (itemComment != null) {
      str += _lineComment(str, itemIndent, _stringifyComment(itemComment!));
    }
    if (chompKeep && itemComment != null) chompKeep = false;
    lines.add(blockItemPrefix + str);
  }
  String str;
  if (lines.isEmpty) {
    str = flowStart + flowEnd;
  } else {
    str = lines.first;
    for (final line in lines.skip(1)) {
      str += line.isNotEmpty ? '\n$indent$line' : '\n';
    }
  }
  if (comment != null && comment.isNotEmpty) {
    str += '\n${_indentComment(_stringifyComment(comment), indent)}';
    if (onComment != null) onComment();
  } else if (chompKeep && onChompKeep != null) {
    onChompKeep();
  }
  return str;
}

String _stringifyFlowCollection(
  List<Object> items,
  _Ctx ctx,
  String start,
  String end,
  String itemIndent,
) {
  final indent = ctx.indent;
  itemIndent += _indentStep;
  final itemCtx = ctx.copy(indent: itemIndent, inFlow: true);
  var reqNewline = false;
  var linesAtValue = 0;
  final lines = <String>[];
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    String? comment;
    if (item is YNode) {
      if (item.spaceBefore) lines.add('');
      _addCommentBefore(indent, lines, item.commentBefore, false);
      if (item.comment != null) comment = item.comment;
    } else if (item is YPair) {
      if (item.key.spaceBefore) lines.add('');
      _addCommentBefore(indent, lines, item.key.commentBefore, false);
      if (item.key.comment != null) reqNewline = true;
      if (item.value.comment != null) comment = item.value.comment;
      if (item.value.commentBefore != null) reqNewline = true;
    }
    if (comment != null) reqNewline = true;
    var str = _stringify(item, itemCtx, () => comment = null, null);
    reqNewline =
        reqNewline || lines.length > linesAtValue || str.contains('\n');
    if (i < items.length - 1) str += ',';
    if (comment != null) {
      str += _lineComment(str, itemIndent, _stringifyComment(comment!));
    }
    lines.add(str);
    linesAtValue = lines.length;
  }
  if (lines.isEmpty) return start + end;
  if (!reqNewline) {
    final length = lines.fold<int>(2, (sum, line) => sum + line.length + 2);
    reqNewline = length > _lineWidth;
  }
  if (reqNewline) {
    var str = start;
    for (final line in lines) {
      str += line.isNotEmpty ? '\n$_indentStep$indent$line' : '\n';
    }
    return '$str\n$indent$end';
  }
  return '$start${lines.join(' ')}$end';
}

void _addCommentBefore(
  String indent,
  List<String> lines,
  String? comment,
  bool chompKeep,
) {
  if (comment != null && chompKeep) {
    comment = comment.replaceFirst(RegExp(r'^\n+'), '');
  }
  if (comment != null && comment.isNotEmpty) {
    final ic = _indentComment(_stringifyComment(comment), indent);
    lines.add(ic.trimLeft());
  }
}

// --- Strings -----------------------------------------------------------------

const _foldFlow = 'flow';
const _foldBlock = 'block';
const _foldQuoted = 'quoted';

String _foldFlowLines(
  String text,
  String indent,
  String mode, {
  int? indentAtStart,
  int lineWidth = _lineWidth,
  int minContentWidth = _minContentWidth,
  _Callback? onOverflow,
}) {
  if (lineWidth <= 0) return text;
  if (lineWidth < minContentWidth) minContentWidth = 0;
  final endStep = (1 + minContentWidth) > (1 + lineWidth - indent.length)
      ? 1 + minContentWidth
      : 1 + lineWidth - indent.length;
  if (text.length <= endStep) return text;
  final folds = <int>[];
  final escapedFolds = <int>{};
  var end = lineWidth - indent.length;
  if (indentAtStart != null) {
    if (indentAtStart >
        lineWidth - (minContentWidth > 2 ? minContentWidth : 2)) {
      folds.add(0);
    } else {
      end = lineWidth - indentAtStart;
    }
  }
  int? split;
  String? prev;
  var overflow = false;
  var i = -1;
  var escStart = -1;
  var escEnd = -1;
  if (mode == _foldBlock) {
    i = _consumeMoreIndentedLines(text, i, indent.length);
    if (i != -1) end = i + endStep;
  }
  for (var ch = _at(text, i += 1); ch.isNotEmpty; ch = _at(text, i += 1)) {
    if (mode == _foldQuoted && ch == r'\') {
      escStart = i;
      switch (_at(text, i + 1)) {
        case 'x':
          i += 3;
        case 'u':
          i += 5;
        case 'U':
          i += 9;
        default:
          i += 1;
      }
      escEnd = i;
    }
    if (ch == '\n') {
      if (mode == _foldBlock) {
        i = _consumeMoreIndentedLines(text, i, indent.length);
      }
      end = i + indent.length + endStep;
      split = null;
    } else {
      if (ch == ' ' &&
          prev != null &&
          prev != ' ' &&
          prev != '\n' &&
          prev != '\t') {
        final next = _at(text, i + 1);
        if (next.isNotEmpty && next != ' ' && next != '\n' && next != '\t') {
          split = i;
        }
      }
      if (i >= end) {
        if (split != null && split != 0) {
          folds.add(split);
          end = split + endStep;
          split = null;
        } else if (mode == _foldQuoted) {
          while (prev == ' ' || prev == '\t') {
            prev = ch;
            ch = _at(text, i += 1);
            overflow = true;
          }
          final j = i > escEnd + 1 ? i - 2 : escStart - 1;
          if (escapedFolds.contains(j)) return text;
          folds.add(j);
          escapedFolds.add(j);
          end = j + endStep;
          split = null;
        } else {
          overflow = true;
        }
      }
    }
    prev = ch;
  }
  if (overflow && onOverflow != null) onOverflow();
  if (folds.isEmpty) return text;
  var res = text.substring(0, folds.first);
  for (var k = 0; k < folds.length; k++) {
    final fold = folds[k];
    final foldEnd = k + 1 < folds.length && folds[k + 1] != 0
        ? folds[k + 1]
        : text.length;
    if (fold == 0) {
      res = '\n$indent${text.substring(0, foldEnd)}';
    } else {
      if (mode == _foldQuoted && escapedFolds.contains(fold)) {
        res += '${text[fold]}\\';
      }
      res += '\n$indent${text.substring(fold + 1, foldEnd)}';
    }
  }
  return res;
}

int _consumeMoreIndentedLines(String text, int i, int indent) {
  var end = i;
  var start = i + 1;
  var ch = _at(text, start);
  while (ch == ' ' || ch == '\t') {
    if (i < start + indent) {
      ch = _at(text, ++i);
    } else {
      do {
        ch = _at(text, ++i);
      } while (ch.isNotEmpty && ch != '\n');
      end = i;
      start = i + 1;
      ch = _at(text, start);
    }
  }
  return end;
}

bool _containsDocumentMarker(String str) =>
    RegExp(r'^(%|---|\.\.\.)', multiLine: true).hasMatch(str);

bool _lineLengthOverLimit(String str, int lineWidth, int indentLength) {
  if (lineWidth <= 0) return false;
  final limit = lineWidth - indentLength;
  final strLen = str.length;
  if (strLen <= limit) return false;
  for (var i = 0, start = 0; i < strLen; ++i) {
    if (str[i] == '\n') {
      if (i - start > limit) return true;
      start = i + 1;
      if (strLen - start <= limit) return false;
    }
  }
  return true;
}

String _doubleQuotedString(String value, _Ctx ctx) {
  final json = jsonEncode(value);
  final implicitKey = ctx.implicitKey;
  final indent = ctx.indent.isNotEmpty
      ? ctx.indent
      : (_containsDocumentMarker(value) ? '  ' : '');
  var str = '';
  var start = 0;
  for (var i = 0; i < json.length; i++) {
    var ch = json[i];
    if (ch == ' ' && _at(json, i + 1) == r'\' && _at(json, i + 2) == 'n') {
      str += '${json.substring(start, i)}\\ ';
      i += 1;
      start = i;
      ch = r'\';
    }
    if (ch == r'\') {
      switch (_at(json, i + 1)) {
        case 'u':
          str += json.substring(start, i);
          final code = json.substring(i + 2, i + 6);
          switch (code) {
            case '0000':
              str += r'\0';
            case '0007':
              str += r'\a';
            case '000b':
              str += r'\v';
            case '001b':
              str += r'\e';
            case '0085':
              str += r'\N';
            case '00a0':
              str += r'\_';
            case '2028':
              str += r'\L';
            case '2029':
              str += r'\P';
            default:
              str += code.startsWith('00')
                  ? '\\x${code.substring(2)}'
                  : json.substring(i, i + 6);
          }
          i += 5;
          start = i + 1;
        case 'n':
          if (implicitKey ||
              _at(json, i + 2) == '"' ||
              json.length < _doubleQuotedMinMultiLineLength) {
            i += 1;
          } else {
            str += '${json.substring(start, i)}\n\n';
            while (_at(json, i + 2) == r'\' &&
                _at(json, i + 3) == 'n' &&
                _at(json, i + 4) != '"') {
              str += '\n';
              i += 2;
            }
            str += indent;
            if (_at(json, i + 2) == ' ') str += r'\';
            i += 1;
            start = i + 1;
          }
        default:
          i += 1;
      }
    }
  }
  str = start != 0 ? str + json.substring(start) : json;
  return implicitKey
      ? str
      : _foldFlowLines(
          str,
          indent,
          _foldQuoted,
          indentAtStart: ctx.indentAtStart,
        );
}

String _singleQuotedString(String value, _Ctx ctx) {
  if ((ctx.implicitKey && value.contains('\n')) ||
      RegExp(r'[ \t]\n|\n[ \t]').hasMatch(value)) {
    return _doubleQuotedString(value, ctx);
  }
  final indent = ctx.indent.isNotEmpty
      ? ctx.indent
      : (_containsDocumentMarker(value) ? '  ' : '');
  final res =
      "'${value.replaceAll("'", "''").replaceAllMapped(RegExp(r'\n+'), (m) => '${m[0]}\n$indent')}'";
  return ctx.implicitKey
      ? res
      : _foldFlowLines(
          res,
          indent,
          _foldFlow,
          indentAtStart: ctx.indentAtStart,
        );
}

String _quotedString(String value, _Ctx ctx) {
  final hasDouble = value.contains('"');
  final hasSingle = value.contains("'");
  if (hasDouble && !hasSingle) return _singleQuotedString(value, ctx);
  return _doubleQuotedString(value, ctx);
}

String _blockString(
  YScalar item,
  String value,
  _Ctx ctx,
  _Callback? onComment,
  _Callback? onChompKeep,
) {
  if (RegExp(r'\n[\t ]+$').hasMatch(value)) return _quotedString(value, ctx);
  final indent = ctx.indent.isNotEmpty
      ? ctx.indent
      : (ctx.forceBlockIndent || _containsDocumentMarker(value) ? '  ' : '');
  final type = item.type;
  final literal = type == ScalarType.blockFolded
      ? false
      : type == ScalarType.blockLiteral
      ? true
      : !_lineLengthOverLimit(value, _lineWidth, indent.length);
  if (value.isEmpty) return literal ? '|\n' : '>\n';
  String chomp;
  var endStart = value.length;
  for (; endStart > 0; --endStart) {
    final ch = value[endStart - 1];
    if (ch != '\n' && ch != '\t' && ch != ' ') break;
  }
  var end = value.substring(endStart);
  final endNlPos = end.indexOf('\n');
  if (endNlPos == -1) {
    chomp = '-';
  } else if (value == end || endNlPos != end.length - 1) {
    chomp = '+';
    if (onChompKeep != null) onChompKeep();
  } else {
    chomp = '';
  }
  if (end.isNotEmpty) {
    value = value.substring(0, value.length - end.length);
    if (end.endsWith('\n')) end = end.substring(0, end.length - 1);
    end = end.replaceAllMapped(
      RegExp(r'(^|(?<!\n))\n+(?!\n|$)'),
      (m) => '${m[0]}$indent',
    );
  }
  var startWithSpace = false;
  var startEnd = 0;
  var startNlPos = -1;
  for (; startEnd < value.length; ++startEnd) {
    final ch = value[startEnd];
    if (ch == ' ') {
      startWithSpace = true;
    } else if (ch == '\n') {
      startNlPos = startEnd;
    } else {
      break;
    }
  }
  var start = value.substring(
    0,
    startNlPos < startEnd ? startNlPos + 1 : startEnd,
  );
  if (start.isNotEmpty) {
    value = value.substring(start.length);
    start = start.replaceAllMapped(RegExp(r'\n+'), (m) => '${m[0]}$indent');
  }
  final indentSize = indent.isNotEmpty ? '2' : '1';
  var header = (startWithSpace ? indentSize : '') + chomp;
  final comment = item.comment;
  if (comment != null) {
    header +=
        ' ${_stringifyComment(comment.replaceAll(RegExp(r' ?[\r\n]+'), ' '))}';
    if (onComment != null) onComment();
  }
  if (!literal) {
    final foldedValue = value
        .replaceAllMapped(RegExp(r'\n+'), (m) => '\n${m[0]}')
        .replaceAllMapped(
          RegExp(r'(?:^|\n)([\t ].*)(?:([\n\t ]*)\n(?![\n\t ]))?'),
          (m) => '${m[1]}${m[2] ?? ''}',
        )
        .replaceAllMapped(RegExp(r'\n+'), (m) => '${m[0]}$indent');
    var literalFallback = false;
    final body = _foldFlowLines(
      '$start$foldedValue$end',
      indent,
      _foldBlock,
      indentAtStart: indent.length,
      onOverflow: type != ScalarType.blockFolded
          ? () => literalFallback = true
          : null,
    );
    if (!literalFallback) return '>$header\n$indent$body';
  }
  value = value.replaceAllMapped(RegExp(r'\n+'), (m) => '${m[0]}$indent');
  return '|$header\n$indent$start$value$end';
}

final _notPlain = RegExp(
  r'''^[\n\t ,[\]{}#&*!|>'"%@`]|^[?-]$|^[?-][ \t]|[\n:][ \t]|[ \t]\n|[\n\t ]#|[\n\t :]$''',
);
final _otherTypes = [
  RegExp(r'^(?:~|[Nn]ull|NULL)?$'),
  RegExp(r'^(?:[Tt]rue|TRUE|[Ff]alse|FALSE)$'),
  RegExp(r'^0o[0-7]+$'),
  RegExp(r'^[-+]?[0-9]+$'),
  RegExp(r'^0x[0-9a-fA-F]+$'),
  RegExp(r'^(?:[-+]?\.(?:inf|Inf|INF)|\.nan|\.NaN|\.NAN)$'),
  RegExp(r'^[-+]?(?:\.[0-9]+|[0-9]+(?:\.[0-9]*)?)[eE][-+]?[0-9]+$'),
  RegExp(r'^[-+]?(?:\.[0-9]+|[0-9]+\.[0-9]*)$'),
];

String _plainString(
  YScalar item,
  String value,
  _Ctx ctx,
  _Callback? onComment,
  _Callback? onChompKeep,
) {
  final implicitKey = ctx.implicitKey;
  final inFlow = ctx.inFlow == true;
  final indent = ctx.indent;
  if ((implicitKey && value.contains('\n')) ||
      (inFlow && RegExp(r'[[\]{},]').hasMatch(value))) {
    return _quotedString(value, ctx);
  }
  if (_notPlain.hasMatch(value)) {
    return implicitKey || inFlow || !value.contains('\n')
        ? _quotedString(value, ctx)
        : _blockString(item, value, ctx, onComment, onChompKeep);
  }
  if (!implicitKey &&
      !inFlow &&
      item.type != ScalarType.plain &&
      value.contains('\n')) {
    return _blockString(item, value, ctx, onComment, onChompKeep);
  }
  if (_containsDocumentMarker(value)) {
    if (indent == '') {
      ctx.forceBlockIndent = true;
      return _blockString(item, value, ctx, onComment, onChompKeep);
    } else if (implicitKey && indent == _indentStep) {
      return _quotedString(value, ctx);
    }
  }
  final str = value.replaceAllMapped(RegExp(r'\n+'), (m) => '${m[0]}\n$indent');
  if (ctx.actualString && _otherTypes.any((test) => test.hasMatch(str))) {
    return _quotedString(value, ctx);
  }
  return implicitKey
      ? str
      : _foldFlowLines(
          str,
          indent,
          _foldFlow,
          indentAtStart: ctx.indentAtStart,
        );
}

String _stringifyString(
  YScalar item,
  _Ctx ctx,
  _Callback? onComment,
  _Callback? onChompKeep,
) {
  final value = item.value is String
      ? item.value as String
      : jsString(item.value);
  var type = item.type;
  if (type != ScalarType.quoteDouble &&
      RegExp(
        r'[\x00-\x08\x0b-\x1f\x7f-\x9f\u{D800}-\u{DFFF}]',
        unicode: true,
      ).hasMatch(value)) {
    type = ScalarType.quoteDouble;
  }
  String? stringifyAs(ScalarType? as) => switch (as) {
    ScalarType.blockFolded || ScalarType.blockLiteral =>
      ctx.implicitKey || ctx.inFlow == true
          ? _quotedString(value, ctx)
          : _blockString(item, value, ctx, onComment, onChompKeep),
    ScalarType.quoteDouble => _doubleQuotedString(value, ctx),
    ScalarType.quoteSingle => _singleQuotedString(value, ctx),
    ScalarType.plain => _plainString(item, value, ctx, onComment, onChompKeep),
    null => null,
  };
  return stringifyAs(type) ?? stringifyAs(ScalarType.plain)!;
}
