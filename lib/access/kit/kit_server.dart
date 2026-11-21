/// Serves the kit to the web view from this phone's loopback interface.
///
/// Web views load ES modules and WebAssembly only from an origin, not from
/// `file://`. The server listens on 127.0.0.1 at a random port, under a random
/// path, and serves only the kit's own files plus `host.js`, the host's side
/// of the message channel. Repository content never goes through it: pages,
/// images and files travel as messages, which the host checks.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Reads one of the kit's files (a path below `kit/dist/`), or null.
typedef KitAssetLoader = Future<Uint8List?> Function(String path);

/// What `host.js` defines: posting goes to the web view's JavaScript channel.
const defaultHostScript =
    'window.genbeyaKitHost = { post: function (message) { GenbeyaKit.postMessage(message); } };\n';

/// The kit's policy as a header too, where `frame-ancestors` works.
const kitContentSecurityPolicy =
    "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; "
    "img-src 'self' data: blob:; font-src 'self' data:; worker-src 'self' blob:; connect-src 'self'; "
    "object-src 'none'; base-uri 'none'; frame-ancestors 'none'";

const _types = {
  'html': 'text/html; charset=utf-8',
  'js': 'text/javascript; charset=utf-8',
  'css': 'text/css; charset=utf-8',
  'wasm': 'application/wasm',
  'woff2': 'font/woff2',
  'woff': 'font/woff',
  'json': 'application/json',
  'txt': 'text/plain; charset=utf-8',
  'svg': 'image/svg+xml',
  'png': 'image/png',
};
final _safePath = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*$',
);

class KitServer {
  KitServer._(this._server, this.token, this._load, this._hostScript);

  final HttpServer _server;

  /// The random first path segment; requests without it get nothing.
  final String token;
  final KitAssetLoader _load;
  final String _hostScript;

  static Future<KitServer> start(
    KitAssetLoader load, {
    String hostScript = defaultHostScript,
  }) async {
    final random = Random.secure();
    final token = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final kit = KitServer._(server, token, load, hostScript);
    server.listen(kit._handle);
    return kit;
  }

  Uri get origin => Uri(scheme: 'http', host: '127.0.0.1', port: _server.port);

  /// The page the web view loads.
  Uri get kitUri => origin.replace(path: '/$token/kit.html');

  /// Whether a navigation stays inside the kit.
  bool owns(Uri uri) =>
      uri.origin == origin.origin && uri.path.startsWith('/$token/');

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final prefix = '/$token/';
      final path = request.uri.path;
      if ((request.method != 'GET' && request.method != 'HEAD') ||
          !path.startsWith(prefix)) {
        return await _notFound(response);
      }
      final relative = path.substring(prefix.length);
      if (!_safePath.hasMatch(relative) || relative.contains('..')) {
        return await _notFound(response);
      }
      Uint8List? body;
      if (relative == 'host.js') {
        body = Uint8List.fromList(utf8.encode(_hostScript));
      } else {
        body = await _load(relative);
        if (body != null && relative == 'kit.html') {
          body = _withHostScript(body);
        }
      }
      final type = _types[relative.substring(relative.lastIndexOf('.') + 1)];
      if (body == null || type == null) return await _notFound(response);
      response.headers
        ..set(HttpHeaders.contentTypeHeader, type)
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        ..set('X-Content-Type-Options', 'nosniff')
        ..set('Content-Security-Policy', kitContentSecurityPolicy);
      response.contentLength = body.length;
      if (request.method == 'GET') response.add(body);
      await response.close();
    } catch (_) {
      await _notFound(response);
    }
  }

  /// `kit.html` with `host.js` loaded before the kit, so the channel exists when the kit starts.
  Uint8List _withHostScript(Uint8List html) {
    final text = utf8.decode(html, allowMalformed: true);
    const marker = '<script type="module"';
    final at = text.indexOf(marker);
    if (at < 0) return html;
    return Uint8List.fromList(
      utf8.encode(
        '${text.substring(0, at)}<script src="host.js"></script>\n${text.substring(at)}',
      ),
    );
  }

  Future<void> _notFound(HttpResponse response) async {
    response.statusCode = HttpStatus.notFound;
    await response.close();
  }
}
