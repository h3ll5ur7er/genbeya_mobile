import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/kit/kit_host.dart';
import 'package:genbeya_mobile/access/kit/kit_protocol.dart';
import 'package:genbeya_mobile/contracts/model.dart';
import 'package:genbeya_mobile/engines/checkbox_engine.dart';

const page = KitPage(
  path: 'docs/Release.md',
  title: 'Release',
  content: '---\ntitle: Release\n---\n# Release\n\n- [ ] Bump\n- [x] Notes\n',
  hash: 'h1',
);

/// Offset of the first item in the page as the kit renders it.
final firstItem = stripFrontmatter(page.content).indexOf('- [ ]');

String ready([int protocol = kitProtocol]) =>
    jsonEncode({'type': 'ready', 'protocol': protocol, 'genbeya': '0.2.0'});

String toggle({
  String area = 'wiki',
  String path = 'docs/Release.md',
  String hash = 'h1',
  required int offset,
}) => jsonEncode({
  'type': 'toggle',
  'area': area,
  'path': path,
  'hash': hash,
  'offset': offset,
});

class Files implements KitFiles {
  final images = <String, Uint8List>{};
  final texts = <String, String>{};

  @override
  Future<Uint8List> image(String path) async =>
      images[path] ?? (throw StateError('secret detail'));
  @override
  Future<String> file(String path) async =>
      texts[path] ?? (throw KitReadException('$path is not there.'));
  @override
  Future<String> fileAt(String path, String revision) => file(path);
  @override
  Future<String> planHistory(String? baseline) async => '[]';
}

class Harness {
  Harness() {
    host = KitHost(
      files: files,
      onToggle: (document, offset) async => toggles.add((document, offset)),
      onSave: (edit, text) => saves.add(text),
      onLog: log.add,
    )..attach((message) async => sent.add(jsonDecode(message) as Map));
  }

  late final KitHost host;
  final files = Files();
  final sent = <Map>[];
  final log = <String>[];
  final toggles = <(KitDocument, int)>[];
  final saves = <String>[];

  List<Object?> get types => [for (final m in sent) m['type']];
}

Map<String, KitContextPart> parts(String version) => {
  'tasks': (version: version, value: <Object>[]),
  'files': (version: 'f1', value: ['README.md']),
};

void main() {
  group('starting', () {
    test('sends nothing before ready, then theme, context and the page', () {
      final h = Harness();
      h.host
        ..setTheme(dark: true)
        ..updateContext(parts('t1'))
        ..show(page);
      expect(h.sent, isEmpty);
      h.host.receive(ready());
      expect(h.types, ['theme', 'context', 'preview']);
      expect((h.sent[1]['parts'] as Map).keys, ['tasks', 'files']);
      final document = h.sent[2]['document'] as Map;
      expect(document['source'], '# Release\n\n- [ ] Bump\n- [x] Notes\n');
      expect(document['hash'], 'h1');
    });

    test('sends only the parts whose version changed', () {
      final h = Harness();
      h.host
        ..updateContext(parts('t1'))
        ..receive(ready());
      h.sent.clear();
      h.host.updateContext(parts('t1'));
      expect(h.sent, isEmpty);
      h.host.updateContext(parts('t2'));
      expect(h.types, ['context']);
      expect((h.sent.single['parts'] as Map).keys, ['tasks']);
    });

    test('a kit that starts again gets everything again', () {
      final h = Harness();
      h.host
        ..updateContext(parts('t1'))
        ..show(page)
        ..receive(ready());
      h.sent.clear();
      h.host.receive(ready());
      expect(h.types, ['context', 'preview']);
      expect((h.sent.first['parts'] as Map).keys, ['tasks', 'files']);
    });

    test('refuses a kit speaking another protocol, and everything after', () {
      final h = Harness();
      h.host
        ..show(page)
        ..receive(ready(kitProtocol + 1))
        ..receive(toggle(offset: firstItem));
      expect(h.sent, isEmpty);
      expect(h.toggles, isEmpty);
      expect(h.log.single, contains('protocol ${kitProtocol + 1}'));
    });

    test('refuses messages before ready', () {
      final h = Harness()..host.show(page);
      h.host.receive(toggle(offset: firstItem));
      expect(h.toggles, isEmpty);
      expect(h.log.single, contains('before ready'));
    });

    test('shows a task with its description and comments', () {
      final h = Harness();
      h.host
        ..show(KitTaskDocument(task()))
        ..receive(ready());
      final document = h.sent.single['document'] as Map;
      expect(document['kind'], 'task');
      expect((document['task'] as Map)['body'], '- [ ] Do it\n');
    });
  });

  group('checkboxes', () {
    Harness started(KitDocument document) => Harness()
      ..host.show(document)
      ..host.receive(ready());

    test('a checkbox in the version shown goes to the write', () {
      final h = started(page)..host.receive(toggle(offset: firstItem));
      expect(h.toggles.single.$1, same(page));
      expect(h.toggles.single.$2, firstItem);
      expect(
        togglePageCheckbox(page.content, firstItem),
        '---\ntitle: Release\n---\n# Release\n\n- [x] Bump\n- [x] Notes\n',
      );
    });

    test('refuses another version, another file, another area', () {
      final h = started(page)
        ..host.receive(toggle(hash: 'h0', offset: firstItem))
        ..host.receive(toggle(path: 'docs/Other.md', offset: firstItem))
        ..host.receive(toggle(area: 'tasks', offset: firstItem));
      expect(h.toggles, isEmpty);
      expect(h.log, hasLength(3));
    });

    test('refuses an offset where no item starts', () {
      final h = started(page)
        ..host.receive(toggle(offset: firstItem + 1))
        ..host.receive(toggle(offset: 0));
      expect(h.toggles, isEmpty);
      expect(h.log.last, contains('no checkbox at 0'));
    });

    test("refuses checkboxes in Markdown whose checkboxes don't tick", () {
      final h =
          started(
              const KitMarkdown(
                area: 'pulls',
                path: 'pulls/PR-1.md',
                source: '- [ ] A to-do in a comment\n',
                hash: 'c1',
              ),
            )
            ..host.receive(
              toggle(
                area: 'pulls',
                path: 'pulls/PR-1.md',
                hash: 'c1',
                offset: 0,
              ),
            );
      expect(h.toggles, isEmpty);
    });

    test('counts a task checkbox in its description', () {
      final h = started(KitTaskDocument(task()))
        ..host.receive(
          toggle(area: 'tasks', path: 'tasks/GM-1.md', hash: 't1', offset: 0),
        );
      expect(h.toggles.single.$2, 0);
    });

    test('refuses a checkbox while the editor is open', () {
      final h = started(page)
        ..host.edit(
          const KitEdit(
            area: 'wiki',
            path: 'docs/Release.md',
            text: '',
            hash: 'h1',
          ),
        )
        ..host.receive(toggle(offset: firstItem));
      expect(h.toggles, isEmpty);
    });
  });

  group('requests', () {
    Future<Map> answer(Harness h, Map<String, Object> request) async {
      h.host.receive(jsonEncode({'id': 7, ...request}));
      await pumpEventQueue();
      final reply = h.sent.last;
      expect(reply['type'], 'reply');
      expect(reply['id'], 7);
      return reply;
    }

    Harness started() => Harness()..host.receive(ready());

    test('answers an image with a data URL of its type', () async {
      final h = started();
      h.files.images['docs/images/a.PNG'] = Uint8List.fromList([1, 2, 3]);
      final reply = await answer(h, {
        'type': 'image',
        'path': 'docs/images/a.PNG',
      });
      expect(reply['value'], 'data:image/png;base64,AQID');
    });

    test('refuses files that are no image Genbeya shows', () async {
      final reply = await answer(started(), {
        'type': 'image',
        'path': 'README.md',
      });
      expect(reply['error'], 'README.md is not an image.');
    });

    test('refuses images over 10 MB', () async {
      final h = started();
      h.files.images['big.png'] = Uint8List(kitImageLimit + 1);
      final reply = await answer(h, {'type': 'image', 'path': 'big.png'});
      expect(reply['error'], 'big.png is larger than 10 MB.');
    });

    test('refuses text over 2 MB', () async {
      final h = started();
      h.files.texts['big.md'] = 'é' * (kitTextLimit ~/ 2 + 1);
      final reply = await answer(h, {'type': 'file', 'path': 'big.md'});
      expect(reply['error'], 'big.md is larger than 2 MB.');
    });

    test("doesn't pass on what went wrong inside", () async {
      final reply = await answer(started(), {
        'type': 'image',
        'path': 'gone.png',
      });
      expect(reply['error'], "Couldn't read it.");
    });

    test('drops a reply to a kit that has started again', () async {
      final h = started();
      final slow = Completer<String>();
      final host = KitHost(files: _Slow(slow.future))
        ..attach((message) async => h.sent.add(jsonDecode(message) as Map))
        ..receive(ready());
      host.receive(jsonEncode({'type': 'file', 'id': 1, 'path': 'a.md'}));
      host.receive(ready());
      h.sent.clear();
      slow.complete('late');
      await pumpEventQueue();
      expect(h.sent, isEmpty);
    });
  });

  group('editing', () {
    const edit = KitEdit(
      area: 'wiki',
      path: 'docs/A.md',
      text: 'a',
      hash: 'e1',
    );

    String save({String path = 'docs/A.md', String hash = 'e1'}) =>
        jsonEncode({'type': 'save', 'path': path, 'hash': hash, 'text': 'b'});

    test('passes on a save of the file open, in its version', () {
      final h = Harness()
        ..host.edit(edit)
        ..host.receive(ready())
        ..host.receive(save());
      expect(h.types, ['edit']);
      expect(h.saves, ['b']);
    });

    test('refuses a save of another file or version', () {
      final h = Harness()
        ..host.edit(edit)
        ..host.receive(ready())
        ..host.receive(save(path: 'docs/B.md'))
        ..host.receive(save(hash: 'e0'));
      expect(h.saves, isEmpty);
      expect(h.log, hasLength(2));
    });

    test('never saves a file opened read-only', () {
      final h = Harness()
        ..host.edit(
          const KitEdit(
            area: 'wiki',
            path: 'docs/A.md',
            text: 'a',
            hash: 'e1',
            readOnly: true,
          ),
        )
        ..host.receive(ready())
        ..host.receive(save());
      expect(h.saves, isEmpty);
    });
  });
}

Task task() => const Task(
  id: 'GM-1',
  path: 'tasks/GM-1.md',
  title: 'One',
  status: 'todo',
  priority: 'none',
  assignee: '',
  labels: [],
  type: '',
  fields: {},
  body: '- [ ] Do it\n',
  epic: '',
  hash: 't1',
  comments: [],
);

class _Slow implements KitFiles {
  _Slow(this.text);
  final Future<String> text;
  @override
  Future<Uint8List> image(String path) => throw UnimplementedError();
  @override
  Future<String> file(String path) => text;
  @override
  Future<String> fileAt(String path, String revision) => text;
  @override
  Future<String> planHistory(String? baseline) => text;
}
