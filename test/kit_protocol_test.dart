import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/kit/kit_protocol.dart';

/// The kit renders repository content, so everything it sends is untrusted:
/// only the protocol's messages pass, with checked paths and bounded sizes.
void main() {
  FromKit parse(Map<String, Object?> message) =>
      parseFromKit(jsonEncode(message));
  Matcher refused() => throwsA(isA<KitProtocolException>());

  test('reads the messages of the protocol', () {
    expect(
      parse({'type': 'ready', 'protocol': 1, 'genbeya': '0.1.0'}),
      isA<KitReady>(),
    );
    final toggle = parse({
      'type': 'toggle',
      'area': 'wiki',
      'path': 'docs/Plan.md',
      'hash': 'h',
      'offset': 114,
    }) as KitToggle;
    expect(
      (toggle.path, toggle.offset, toggle.hash),
      ('docs/Plan.md', 114, 'h'),
    );
    final follow = parse({
      'type': 'follow',
      'link': {'kind': 'file', 'path': 'tasks/GM-2.md', 'anchor': null},
    }) as KitFollow;
    expect((follow.link as FileLink).path, 'tasks/GM-2.md');
    expect(
      parse({'type': 'image', 'id': 3, 'path': 'docs/images/board.png'}),
      isA<KitImageRequest>(),
    );
    expect(
      parse({
        'type': 'fileAt',
        'id': 4,
        'path': 'README.md',
        'revision': 'v0.1.0',
      }),
      isA<KitFileAtRequest>(),
    );
    expect(
      parse({'type': 'planHistory', 'id': 5, 'baseline': null}),
      isA<KitPlanHistoryRequest>(),
    );
    expect(
      (parse({'type': 'height', 'height': 2189}) as KitHeight).height,
      2189,
    );
    expect(
      parse({
        'type': 'save',
        'path': 'docs/Notes.md',
        'hash': 'h',
        'text': '# Notes',
      }),
      isA<KitSave>(),
    );
    expect(
      parse({
        'type': 'editorState',
        'path': 'docs/Notes.md',
        'dirty': true,
        'selection': {'from': 1, 'to': 2},
        'completing': false,
      }),
      isA<KitEditorState>(),
    );
  });

  test('refuses paths out of the repository', () {
    for (final path in [
      '../secrets',
      '/etc/passwd',
      '.git/config',
      'docs/../../x',
      r'docs\x',
    ]) {
      expect(
        () => parse({'type': 'image', 'id': 1, 'path': path}),
        refused(),
        reason: path,
      );
      expect(
        () => parse({
          'type': 'toggle',
          'area': 'wiki',
          'path': path,
          'hash': 'h',
          'offset': 0,
        }),
        refused(),
      );
    }
  });

  test('lets only http, https and mailto links leave the app', () {
    expect(
      parse({
        'type': 'follow',
        'link': {'kind': 'external', 'url': 'https://genbeya.fyi'},
      }),
      isA<KitFollow>(),
    );
    expect(
      parse({
        'type': 'follow',
        'link': {'kind': 'external', 'url': 'mailto:ada@example.com'},
      }),
      isA<KitFollow>(),
    );
    for (final url in [
      'javascript:alert(1)',
      'file:///etc/passwd',
      'intent://x',
      'genbeya://open?task=X-1',
    ]) {
      expect(
        () => parse({
          'type': 'follow',
          'link': {'kind': 'external', 'url': url},
        }),
        refused(),
        reason: url,
      );
    }
  });

  test('refuses unknown messages, wrong shapes and bad revisions', () {
    expect(() => parseFromKit('not json'), refused());
    expect(() => parseFromKit('[1]'), refused());
    expect(() => parse({'type': 'write', 'path': 'docs/x.md'}), refused());
    expect(
      () => parse({
        'type': 'toggle',
        'area': 'code',
        'path': 'a.md',
        'hash': 'h',
        'offset': 0,
      }),
      refused(),
    );
    expect(
      () => parse({
        'type': 'toggle',
        'area': 'wiki',
        'path': 'a.md',
        'hash': 'h',
        'offset': -1,
      }),
      refused(),
    );
    expect(
      () => parse({'type': 'image', 'id': 1.5, 'path': 'a.png'}),
      refused(),
    );
    expect(
      () => parse({
        'type': 'fileAt',
        'id': 1,
        'path': 'a',
        'revision': '--output=/tmp/x',
      }),
      refused(),
    );
    expect(
      () => parse({
        'type': 'fileAt',
        'id': 1,
        'path': 'a',
        'revision': 'main..evil',
      }),
      refused(),
    );
    expect(() => parse({'type': 'height', 'height': 1e9}), refused());
  });

  test('writes the host messages the kit reads', () {
    final preview = jsonDecode(
      previewPageMessage(
        path: 'docs/A.md',
        title: 'A',
        source: '# A',
        hash: 'h',
      ),
    ) as Map;
    expect(preview['document'], {
      'kind': 'page',
      'path': 'docs/A.md',
      'title': 'A',
      'source': '# A',
      'hash': 'h',
    });
    final context = jsonDecode(
      contextMessage({'author': (version: 'a1', value: 'Alex')}),
    ) as Map;
    expect(context['parts'], {
      'author': {'version': 'a1', 'value': 'Alex'},
    });
    final reply = jsonDecode(
      replyTo(const KitImageRequest(7, 'a.png'), error: 'No.'),
    ) as Map;
    expect(reply, {'type': 'reply', 'id': 7, 'error': 'No.'});
  });

  test('outline: headings with level, text and id, bounded', () {
    final outline = parseFromKit(
      jsonEncode({
        'type': 'outline',
        'path': 'docs/Home.md',
        'headings': [
          {'level': 1, 'text': 'Home', 'id': 'home'},
          {'level': 2, 'text': 'Next', 'id': 'next'},
        ],
      }),
    ) as KitOutline;
    expect(outline.headings.map((h) => h.id), ['home', 'next']);
    expect(
      () => parseFromKit(
        jsonEncode({
          'type': 'outline',
          'path': 'docs/Home.md',
          'headings': [
            {'level': 7, 'text': 'x', 'id': 'x'},
          ],
        }),
      ),
      throwsA(isA<KitProtocolException>()),
    );
    expect(jsonDecode(revealMessage('next')), {'type': 'reveal', 'id': 'next'});
  });
}
