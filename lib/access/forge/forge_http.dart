import 'dart:convert';
import 'dart:io';

/// A JSON response: its status and decoded body.
typedef JsonResponse = ({int status, Object? body});

/// The few HTTP calls signing in makes; a fake stands in for tests.
abstract interface class ForgeHttp {
  Future<JsonResponse> postForm(Uri url, Map<String, String> form);
  Future<JsonResponse> getJson(Uri url, {String? bearer});
}

class IoForgeHttp implements ForgeHttp {
  IoForgeHttp()
    : _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  final HttpClient _client;

  Future<JsonResponse> _send(HttpClientRequest request, [String? body]) async {
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'genbeya-mobile');
    if (body != null) {
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(body);
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    final text = await response.transform(utf8.decoder).join();
    Object? decoded;
    try {
      decoded = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      decoded = null;
    }
    return (status: response.statusCode, body: decoded);
  }

  @override
  Future<JsonResponse> postForm(Uri url, Map<String, String> form) async =>
      _send(await _client.postUrl(url), Uri(queryParameters: form).query);

  @override
  Future<JsonResponse> getJson(Uri url, {String? bearer}) async {
    final request = await _client.getUrl(url);
    if (bearer != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    }
    return _send(request);
  }
}
