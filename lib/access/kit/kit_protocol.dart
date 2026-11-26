/// The host's side of the kit's messages (Genbeya's `src/shells/kit/protocol.ts`
/// and docs/Architecture/Kit.md, protocol 1). Everything the kit sends is untrusted: a rendered
/// page is repository content. [parseFromKit] accepts only the protocol's
/// messages, with checked paths and bounded sizes; the builders write what
/// the host sends.
library;

import 'dart:convert';

import '../../engines/repository_path.dart';

/// The protocol this host speaks; a kit announcing another one is refused.
const kitProtocol = 1;

const _areas = ['wiki', 'tasks', 'settings', 'pulls'];
const _maxText = 1024 * 1024;
const _maxHeight = 1000000;
final _revision = RegExp(r'^(?!-)(?!.*\.\.)[A-Za-z0-9._/~^-]{1,200}$');
final _externalSchemes = RegExp(r'^(https?|mailto):', caseSensitive: false);

class KitProtocolException implements Exception {
  KitProtocolException(this.message);

  final String message;

  @override
  String toString() => message;
}

sealed class FromKit {
  const FromKit();
}

class KitReady extends FromKit {
  const KitReady(this.protocol, this.genbeya);
  final int protocol;
  final String genbeya;
}

sealed class FollowedLink {
  const FollowedLink();
}

class ExternalLink extends FollowedLink {
  const ExternalLink(this.url);
  final Uri url;
}

class MissingPage extends FollowedLink {
  const MissingPage(this.title);
  final String title;
}

class PersonLink extends FollowedLink {
  const PersonLink(this.handle);
  final String handle;
}

class FileLink extends FollowedLink {
  const FileLink(this.path, this.anchor);
  final String path;
  final String? anchor;
}

class KitFollow extends FromKit {
  const KitFollow(this.link);
  final FollowedLink link;
}

class KitToggle extends FromKit {
  const KitToggle(this.area, this.path, this.hash, this.offset);
  final String area;
  final String path;
  final String hash;
  final int offset;
}

/// A request the host answers with [replyTo].
sealed class KitRequest extends FromKit {
  const KitRequest(this.id);
  final int id;
}

class KitImageRequest extends KitRequest {
  const KitImageRequest(super.id, this.path);
  final String path;
}

class KitFileRequest extends KitRequest {
  const KitFileRequest(super.id, this.path);
  final String path;
}

class KitFileAtRequest extends KitRequest {
  const KitFileAtRequest(super.id, this.path, this.revision);
  final String path;
  final String revision;
}

class KitPlanHistoryRequest extends KitRequest {
  const KitPlanHistoryRequest(super.id, this.baseline);
  final String? baseline;
}

class KitHeight extends FromKit {
  const KitHeight(this.height);
  final double height;
}

class KitDraft extends FromKit {
  const KitDraft(this.path, this.hash, this.text);
  final String path;
  final String hash;
  final String text;
}

class KitSave extends FromKit {
  const KitSave(this.path, this.hash, this.text);
  final String path;
  final String hash;
  final String text;
}

class KitEditorState extends FromKit {
  const KitEditorState(
    this.path,
    this.dirty,
    this.from,
    this.to,
    this.completing,
  );
  final String path;
  final bool dirty;
  final int from;
  final int to;
  final bool completing;
}

/// A heading of the rendered document.
typedef OutlineHeading = ({int level, String text, String id});

/// The headings of the document just rendered.
class KitOutline extends FromKit {
  const KitOutline(this.path, this.headings);
  final String path;
  final List<OutlineHeading> headings;
}

class KitError extends FromKit {
  const KitError(this.message);
  final String message;
}

Never _refuse(String message) => throw KitProtocolException(message);

T _field<T>(Map<String, Object?> message, String name) {
  final value = message[name];
  if (value is! T) {
    _refuse('${message['type']}: $name is missing or not a ${T.toString()}.');
  }
  return value;
}

String _text(Map<String, Object?> message, String name, {int max = 4096}) {
  final value = _field<String>(message, name);
  if (value.length > max) _refuse('${message['type']}: $name is too long.');
  return value;
}

String _path(Map<String, Object?> message, String name) {
  try {
    return validateRepositoryPath(_text(message, name), false);
  } on FormatException catch (error) {
    _refuse('${message['type']}: ${error.message}');
  }
}

int _int(Map<String, Object?> message, String name, {int max = 0x7fffffff}) {
  final value = message[name];
  if (value is! num ||
      value != value.truncateToDouble() ||
      value < 0 ||
      value > max) {
    _refuse('${message['type']}: $name is not a whole number.');
  }
  return value.toInt();
}

/// Parses and checks one message from the kit; throws [KitProtocolException] for anything else.
FromKit parseFromKit(String text) {
  if (text.length > _maxText + 4096) _refuse('A message that is too long.');
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    _refuse("A message that isn't JSON.");
  }
  if (decoded is! Map<String, Object?>) {
    _refuse('A message that is not an object.');
  }
  final m = decoded;
  switch (m['type']) {
    case 'ready':
      return KitReady(_int(m, 'protocol'), _text(m, 'genbeya', max: 40));
    case 'follow':
      final link = m['link'];
      if (link is! Map<String, Object?>) _refuse('follow: link is missing.');
      switch (link['kind']) {
        case 'external':
          final url = _text(link..['type'] = 'follow', 'url');
          final uri = Uri.tryParse(url);
          if (uri == null || !_externalSchemes.hasMatch(url)) {
            _refuse('follow: only http, https and mailto links leave the app.');
          }
          return KitFollow(ExternalLink(uri));
        case 'missing':
          return KitFollow(
            MissingPage(_text(link..['type'] = 'follow', 'title', max: 300)),
          );
        case 'person':
          return KitFollow(
            PersonLink(_text(link..['type'] = 'follow', 'handle', max: 40)),
          );
        case 'file':
          final anchor = link['anchor'];
          if (anchor != null && (anchor is! String || anchor.length > 300)) {
            _refuse('follow: invalid anchor.');
          }
          return KitFollow(
            FileLink(
              _path(link..['type'] = 'follow', 'path'),
              anchor as String?,
            ),
          );
      }
      _refuse('follow: unknown kind of link.');
    case 'toggle':
      final area = _text(m, 'area', max: 20);
      if (!_areas.contains(area)) _refuse('toggle: unknown area.');
      return KitToggle(
        area,
        _path(m, 'path'),
        _text(m, 'hash', max: 100),
        _int(m, 'offset', max: _maxText),
      );
    case 'image':
      return KitImageRequest(_int(m, 'id'), _path(m, 'path'));
    case 'file':
      return KitFileRequest(_int(m, 'id'), _path(m, 'path'));
    case 'fileAt':
      final revision = _text(m, 'revision', max: 200);
      if (!_revision.hasMatch(revision)) _refuse('fileAt: invalid revision.');
      return KitFileAtRequest(_int(m, 'id'), _path(m, 'path'), revision);
    case 'planHistory':
      final baseline = m['baseline'];
      if (baseline != null &&
          (baseline is! String || !_revision.hasMatch(baseline))) {
        _refuse('planHistory: invalid baseline.');
      }
      return KitPlanHistoryRequest(_int(m, 'id'), baseline as String?);
    case 'height':
      final height = m['height'];
      if (height is! num || height < 0 || height > _maxHeight) {
        _refuse('height: invalid height.');
      }
      return KitHeight(height.toDouble());
    case 'draft':
      return KitDraft(
        _path(m, 'path'),
        _text(m, 'hash', max: 100),
        _text(m, 'text', max: _maxText),
      );
    case 'save':
      return KitSave(
        _path(m, 'path'),
        _text(m, 'hash', max: 100),
        _text(m, 'text', max: _maxText),
      );
    case 'editorState':
      final selection = m['selection'];
      if (selection is! Map<String, Object?>) {
        _refuse('editorState: selection is missing.');
      }
      return KitEditorState(
        _path(m, 'path'),
        _field<bool>(m, 'dirty'),
        _int(selection..['type'] = 'editorState', 'from', max: _maxText),
        _int(selection, 'to', max: _maxText),
        _field<bool>(m, 'completing'),
      );
    case 'outline':
      final headings = m['headings'];
      if (headings is! List || headings.length > 500) {
        _refuse('outline: invalid headings.');
      }
      return KitOutline(_path(m, 'path'), [
        for (final heading in headings)
          if (heading is Map<String, Object?>)
            (
              level: _int(heading..['type'] = 'outline', 'level', max: 6),
              text: _text(heading, 'text', max: 300),
              id: _text(heading, 'id', max: 300),
            )
          else
            _refuse('outline: invalid heading.'),
      ]);
    case 'error':
      return KitError(_text(m, 'message', max: 2000));
  }
  _refuse('An unknown message: ${m['type']}.');
}

// --- Host → kit ---------------------------------------------------------------

/// Context parts that changed, each with its version: `wiki`, `tasks`, `plan`,
/// `files`, `people`, `settings`, `author`.
String contextMessage(Map<String, ({String version, Object? value})> parts) =>
    jsonEncode({
      'type': 'context',
      'parts': {
        for (final e in parts.entries)
          e.key: {'version': e.value.version, 'value': e.value.value},
      },
    });

/// Light or dark, and the app's CSS variables without their `--`
/// (`bg-app`, `font-ui`); Genbeya's kit requires the tokens, if empty.
String themeMessage({
  required bool dark,
  Map<String, String> tokens = const {},
}) => jsonEncode({
  'type': 'theme',
  'mode': dark ? 'dark' : 'light',
  'tokens': {
    for (final e in tokens.entries)
      (e.key.startsWith('--') ? e.key.substring(2) : e.key): e.value,
  },
});

String previewPageMessage({
  required String path,
  required String title,
  required String source,
  required String hash,
}) => jsonEncode({
  'type': 'preview',
  'document': {
    'kind': 'page',
    'path': path,
    'title': title,
    'source': source,
    'hash': hash,
  },
});

/// A task, as Genbeya's `Task` (the model's `toJson`): the kit shows its
/// description and comments, the host its title and properties.
String previewTaskMessage(Map<String, Object?> task) => jsonEncode({
  'type': 'preview',
  'document': {'kind': 'task', 'task': task},
});

String previewMarkdownMessage({
  required String area,
  required String path,
  required String source,
  required String hash,
  bool checkboxes = false,
}) => jsonEncode({
  'type': 'preview',
  'document': {
    'kind': 'markdown',
    'area': area,
    'path': path,
    'source': source,
    'hash': hash,
    'checkboxes': checkboxes,
  },
});

String editMessage({
  required String area,
  required String path,
  required String text,
  required String hash,
  bool readOnly = false,
}) => jsonEncode({
  'type': 'edit',
  'area': area,
  'path': path,
  'text': text,
  'hash': hash,
  'readOnly': readOnly,
});

String editorCommandMessage(String command, {String? text}) =>
    jsonEncode({'type': 'editorCommand', 'command': command, 'text': ?text});

/// Scrolls the document shown to the heading with [id] (from [KitOutline]).
String revealMessage(String id) => jsonEncode({'type': 'reveal', 'id': id});

String replyTo(KitRequest request, {String? value, String? error}) =>
    jsonEncode({
      'type': 'reply',
      'id': request.id,
      'value': ?value,
      'error': ?error,
    });
