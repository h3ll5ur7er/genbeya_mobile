import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/kit/kit_server.dart';

/// The loopback server serves the kit's files under a random path, and nothing else.
void main() {
  late KitServer server;
  final requested = <String>[];

  setUp(() async {
    requested.clear();
    server = await KitServer.start((path) async {
      requested.add(path);
      return switch (path) {
        'kit.html' => Uint8List.fromList(
          utf8.encode(
            '<head>\n<script type="module" src="kit.js"></script>\n</head>',
          ),
        ),
        'kit.js' => Uint8List.fromList(utf8.encode('console.log(1)')),
        'rockuml.wasm' => Uint8List.fromList([0, 97, 115, 109]),
        _ => null,
      };
    });
  });

  tearDown(() => server.close());

  Future<HttpClientResponse> get(Uri uri) async {
    final client = HttpClient();
    final response = await (await client.getUrl(uri)).close();
    client.close();
    return response;
  }

  test(
    'serves the kit with the host script before it, and the policy as a header',
    () async {
      final response = await get(server.kitUri);
      final body = await utf8.decodeStream(response);
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'text/html');
      expect(body.indexOf('host.js'), lessThan(body.indexOf('kit.js')));
      expect(
        response.headers.value('content-security-policy'),
        contains("frame-ancestors 'none'"),
      );
      final host = await get(
        server.origin.replace(path: '/${server.token}/host.js'),
      );
      expect(await utf8.decodeStream(host), contains('GenbeyaKit.postMessage'));
    },
  );

  test('serves WebAssembly with its type', () async {
    final response = await get(
      server.origin.replace(path: '/${server.token}/rockuml.wasm'),
    );
    expect(response.headers.contentType?.mimeType, 'application/wasm');
  });

  test(
    'serves nothing without the token, outside the kit, or of unknown types',
    () async {
      for (final path in [
        '/kit.html',
        '/wrong/kit.html',
        '/${server.token}/../kit.html',
        '/${server.token}/missing.js',
        '/${server.token}/x.exe',
      ]) {
        final response = await get(server.origin.replace(path: path));
        await response.drain<void>();
        expect(response.statusCode, 404, reason: path);
      }
      expect(requested, isNot(contains(contains('..'))));
    },
  );

  test('knows which navigations stay in the kit', () {
    expect(server.owns(server.kitUri), isTrue);
    expect(
      server.owns(Uri.parse('https://example.com/${server.token}/kit.html')),
      isFalse,
    );
    expect(
      server.owns(server.origin.replace(path: '/other/kit.html')),
      isFalse,
    );
  });
}
