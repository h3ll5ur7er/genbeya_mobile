/// The host's side of the kit ([[Call chains#c5-render-a-page]]): keeps the
/// kit's context current in versioned parts, shows documents, answers its
/// requests read-only within Genbeya's limits, and lets through only what it
/// may ask for: a checkbox in the version it was shown, and a save or draft
/// of the file it was given to edit. No Flutter here, so it is tested headless.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../contracts/model.dart';
import '../../engines/checkbox_engine.dart';
import 'kit_protocol.dart';

/// Sends one message to the kit.
typedef KitSend = Future<void> Function(String message);

/// Genbeya's read limits (`TEXT_LIMIT`, `IMAGE_LIMIT` in src/access/files/file-store.ts).
const kitTextLimit = 2 * 1024 * 1024;
const kitImageLimit = 10 * 1024 * 1024;

/// The images Genbeya shows, by extension (src/utilities/image-types.ts).
const _imageTypes = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'svg': 'image/svg+xml',
  'avif': 'image/avif',
};

/// The media type of an image Genbeya shows, or null.
String? imageType(String path) {
  final name = path.substring(path.lastIndexOf('/') + 1);
  final dot = name.lastIndexOf('.');
  return dot > 0 ? _imageTypes[name.substring(dot + 1).toLowerCase()] : null;
}

/// What the kit may read, through paths [parseFromKit] already checked.
/// Every method reads; none writes.
abstract interface class KitFiles {
  Future<Uint8List> image(String path);
  Future<String> file(String path);
  Future<String> fileAt(String path, String revision);

  /// `content.planHistory` as JSON, for `[BURNDOWN]` and `[BASELINE]`.
  Future<String> planHistory(String? baseline);
}

/// A document shown in the kit, with the version (hash) it was read from.
sealed class KitDocument {
  const KitDocument();
  String get area;
  String get path;
  String get hash;

  /// Whether its checkboxes may be ticked.
  bool get checkboxes;
}

/// A wiki page: [content] is the whole file; the kit renders it without its
/// frontmatter, and its checkbox offsets count from there.
class KitPage extends KitDocument {
  const KitPage({
    required this.path,
    required this.title,
    required this.content,
    required this.hash,
  });

  @override
  final String path;
  final String title;
  final String content;
  @override
  final String hash;
  @override
  String get area => 'wiki';
  @override
  bool get checkboxes => true;
}

/// A task: the kit shows its description and comments, the host the rest;
/// checkbox offsets count in the description.
class KitTaskDocument extends KitDocument {
  const KitTaskDocument(this.task);
  final Task task;
  @override
  String get area => 'tasks';
  @override
  String get path => task.path;
  @override
  String get hash => task.hash;
  @override
  bool get checkboxes => true;
}

/// Other Markdown: a pull request file, a comment.
class KitMarkdown extends KitDocument {
  const KitMarkdown({
    required this.area,
    required this.path,
    required this.source,
    required this.hash,
    this.checkboxes = false,
  });

  @override
  final String area;
  @override
  final String path;
  final String source;
  @override
  final String hash;
  @override
  final bool checkboxes;
}

/// A text file opened in the kit's editor.
class KitEdit {
  const KitEdit({
    required this.area,
    required this.path,
    required this.text,
    required this.hash,
    this.readOnly = false,
  });

  final String area;
  final String path;
  final String text;
  final String hash;
  final bool readOnly;
}

/// One part of the kit's context, sent again only when [version] changes.
typedef KitContextPart = ({String version, Object? value});

class KitHost {
  KitHost({
    required this.files,
    this.onToggle,
    this.onFollow,
    this.onHeight,
    this.onDraft,
    this.onSave,
    this.onEditorState,
    this.onReady,
    this.onLog,
  });

  final KitFiles files;

  /// A checkbox ticked in [document] (the one shown, in the version shown),
  /// where a task list item starts at [offset]. The write is C4's: it reads
  /// the file again and refuses it once the hash differs.
  final Future<void> Function(KitDocument document, int offset)? onToggle;
  final void Function(FollowedLink link)? onFollow;
  final void Function(double height)? onHeight;
  final void Function(KitEdit edit, String text)? onDraft;
  final void Function(KitEdit edit, String text)? onSave;
  final void Function(KitEditorState state)? onEditorState;
  final void Function(String genbeya)? onReady;

  /// What the host refused or the kit reported, for the log.
  final void Function(String line)? onLog;

  KitSend? _send;
  bool _ready = false;
  bool _refused = false;

  /// Counts the kit's starts; replies to a kit that has since reloaded are dropped.
  int _generation = 0;
  final _context = <String, KitContextPart>{};
  final _kitHas = <String, String>{};
  String? _theme;
  KitDocument? _document;
  KitEdit? _edit;

  /// The document shown, if the kit shows one now.
  KitDocument? get document => _edit == null ? _document : null;

  /// The web view is up: messages go through [send].
  void attach(KitSend send) => _send = send;

  /// The context parts that may have changed; only those whose version the
  /// kit doesn't have yet are sent.
  void updateContext(Map<String, KitContextPart> parts) {
    _context.addAll(parts);
    _sendContext();
  }

  void setTheme({required bool dark, Map<String, String> tokens = const {}}) {
    _theme = themeMessage(dark: dark, tokens: tokens);
    _post(_theme!);
  }

  void show(KitDocument document) {
    _document = document;
    _edit = null;
    _post(_previewMessage(document));
  }

  void edit(KitEdit edit) {
    _edit = edit;
    _post(
      editMessage(
        area: edit.area,
        path: edit.path,
        text: edit.text,
        hash: edit.hash,
        readOnly: edit.readOnly,
      ),
    );
  }

  void command(String command, {String? text}) =>
      _post(editorCommandMessage(command, text: text));

  /// One message from the kit, as the web view delivered it.
  void receive(String text) {
    if (_refused) return;
    final FromKit message;
    try {
      message = parseFromKit(text);
    } on KitProtocolException catch (error) {
      onLog?.call('Refused: ${error.message}');
      return;
    }
    if (message is KitReady) return _start(message);
    if (!_ready) {
      onLog?.call('Refused: ${message.runtimeType} before ready.');
      return;
    }
    switch (message) {
      case KitReady():
        break;
      case KitFollow(:final link):
        onFollow?.call(link);
      case KitToggle():
        _toggle(message);
      case KitRequest():
        unawaited(_answer(message, _generation));
      case KitHeight(:final height):
        onHeight?.call(height);
      case KitDraft(:final path, :final hash, :final text):
        final edit = _editing(path, hash, 'draft');
        if (edit != null) onDraft?.call(edit, text);
      case KitSave(:final path, :final hash, :final text):
        final edit = _editing(path, hash, 'save');
        if (edit != null && !edit.readOnly) onSave?.call(edit, text);
      case KitEditorState():
        if (_edit?.path == message.path) onEditorState?.call(message);
      case KitError(:final message):
        onLog?.call('Kit: $message');
    }
  }

  void _start(KitReady ready) {
    if (ready.protocol != kitProtocol) {
      _refused = true;
      onLog?.call(
        'Refused a kit speaking protocol ${ready.protocol}; this app speaks $kitProtocol.',
      );
      return;
    }
    // A (re)started kit has nothing: send it everything again.
    _ready = true;
    _generation++;
    _kitHas.clear();
    if (_theme != null) _post(_theme!);
    _sendContext();
    if (_edit case final edit?) {
      this.edit(edit);
    } else if (_document case final document?) {
      show(document);
    }
    onReady?.call(ready.genbeya);
  }

  void _sendContext() {
    if (!_ready) return;
    final changed = {
      for (final e in _context.entries)
        if (_kitHas[e.key] != e.value.version) e.key: e.value,
    };
    if (changed.isEmpty) return;
    _post(contextMessage(changed));
    for (final e in changed.entries) {
      _kitHas[e.key] = e.value.version;
    }
  }

  /// The kit may tick a checkbox only in the document it was shown, in the
  /// version it was shown, where a task list item starts.
  void _toggle(KitToggle toggle) {
    final shown = document;
    if (shown == null ||
        !shown.checkboxes ||
        shown.area != toggle.area ||
        shown.path != toggle.path ||
        shown.hash != toggle.hash) {
      onLog?.call(
        'Refused: a checkbox in ${toggle.path} that is not the version shown.',
      );
      return;
    }
    final source = switch (shown) {
      KitPage(:final content) => stripFrontmatter(content),
      KitTaskDocument(:final task) => task.body,
      KitMarkdown(:final source) => source,
    };
    if (!isCheckboxItemAt(source, toggle.offset)) {
      onLog?.call(
        'Refused: no checkbox at ${toggle.offset} in ${toggle.path}.',
      );
      return;
    }
    final write = onToggle;
    if (write != null) unawaited(write(shown, toggle.offset));
  }

  KitEdit? _editing(String path, String hash, String what) {
    final edit = _edit;
    if (edit == null || edit.path != path || edit.hash != hash) {
      onLog?.call('Refused: a $what of $path, which is not the file open.');
      return null;
    }
    return edit;
  }

  Future<void> _answer(KitRequest request, int generation) async {
    String? value;
    String? error;
    try {
      value = switch (request) {
        KitImageRequest(:final path) => await _image(path),
        KitFileRequest(:final path) => _text(path, await files.file(path)),
        KitFileAtRequest(:final path, :final revision) => _text(
          path,
          await files.fileAt(path, revision),
        ),
        KitPlanHistoryRequest(:final baseline) => await files.planHistory(
          baseline,
        ),
      };
    } on KitReadException catch (problem) {
      error = problem.message;
    } catch (_) {
      error = "Couldn't read it.";
    }
    if (generation != _generation) return;
    await _post(replyTo(request, value: value, error: error));
  }

  Future<String> _image(String path) async {
    final type = imageType(path);
    if (type == null) throw KitReadException('$path is not an image.');
    final bytes = await files.image(path);
    if (bytes.length > kitImageLimit) {
      throw KitReadException('$path is larger than 10 MB.');
    }
    return 'data:$type;base64,${base64Encode(bytes)}';
  }

  String _text(String path, String text) {
    // UTF-8 takes at most three bytes per UTF-16 unit; count exactly only near the limit.
    if (text.length * 3 > kitTextLimit &&
        utf8.encode(text).length > kitTextLimit) {
      throw KitReadException('$path is larger than 2 MB.');
    }
    return text;
  }

  Future<void> _post(String message) async {
    if (!_ready || _refused) return;
    await _send?.call(message);
  }
}

/// A read refused with a reason the kit may show.
class KitReadException implements Exception {
  KitReadException(this.message);
  final String message;
  @override
  String toString() => message;
}

String _previewMessage(KitDocument document) => switch (document) {
  KitPage(:final path, :final title, :final content, :final hash) =>
    previewPageMessage(
      path: path,
      title: title,
      source: stripFrontmatter(content),
      hash: hash,
    ),
  KitTaskDocument(:final task) => previewTaskMessage(task.toJson()),
  KitMarkdown(
    :final area,
    :final path,
    :final source,
    :final hash,
    :final checkboxes,
  ) =>
    previewMarkdownMessage(
      area: area,
      path: path,
      source: source,
      hash: hash,
      checkboxes: checkboxes,
    ),
};
