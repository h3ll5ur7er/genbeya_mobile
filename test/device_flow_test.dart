import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/access/forge/device_flow.dart';
import 'package:genbeya_mobile/access/forge/forge_http.dart';

class FakeHttp implements ForgeHttp {
  final posts = <String, List<JsonResponse>>{};
  final gets = <String, JsonResponse>{};
  final sent = <String>[];

  @override
  Future<JsonResponse> postForm(Uri url, Map<String, String> form) async {
    sent.add('POST ${url.path} ${form['grant_type'] ?? form['scope']}');
    final queue = posts[url.path]!;
    return queue.length > 1 ? queue.removeAt(0) : queue.first;
  }

  @override
  Future<JsonResponse> getJson(Uri url, {String? bearer}) async {
    sent.add('GET ${url.path} $bearer');
    return gets[url.path] ?? (status: 404, body: null);
  }
}

void main() {
  const apps = ForgeApps(github: 'gh-client', gitlab: 'gl-client');
  final waits = <Duration>[];
  Future<void> sleep(Duration wait) async => waits.add(wait);

  setUp(waits.clear);

  test('GitHub: a code, polling until approved, then the account', () async {
    final http = FakeHttp()
      ..posts['/login/device/code'] = [
        (
          status: 200,
          body: {
            'device_code': 'dev',
            'user_code': 'ABCD-1234',
            'verification_uri': 'https://github.com/login/device',
            'interval': 5,
            'expires_in': 900,
          },
        ),
      ]
      ..posts['/login/oauth/access_token'] = [
        (status: 200, body: {'error': 'authorization_pending'}),
        (status: 200, body: {'error': 'slow_down'}),
        (
          status: 200,
          body: {'access_token': 'gho_token', 'token_type': 'bearer'},
        ),
      ]
      ..gets['/user'] = (
        status: 200,
        body: {'login': 'ada', 'name': 'Ada Lovelace', 'email': null},
      )
      ..gets['/user/emails'] = (
        status: 200,
        body: [
          {'email': 'old@example.com', 'primary': false, 'verified': true},
          {'email': 'ada@example.com', 'primary': true, 'verified': true},
        ],
      )
      ..gets['/user/repos'] = (
        status: 200,
        body: [
          {
            'full_name': 'ada/engine',
            'clone_url': 'https://github.com/ada/engine.git',
            'private': true,
          },
        ],
      );
    final flow = DeviceFlow(http, apps: apps);
    expect(flow.offers(Forge.github), isTrue);
    final code = await flow.start(Forge.github);
    expect(code.userCode, 'ABCD-1234');
    final account = await flow.finish(Forge.github, code, sleep: sleep);
    expect(waits, [
      const Duration(seconds: 5),
      const Duration(seconds: 5),
      const Duration(seconds: 10),
    ], reason: 'slow_down adds five seconds');
    expect(account.host, 'github.com');
    expect(account.token, 'gho_token');
    expect(account.name, 'Ada Lovelace');
    expect(account.email, 'ada@example.com');
    final repositories = await flow.repositories(account);
    expect(repositories.single.cloneUrl, 'https://github.com/ada/engine.git');
    expect(repositories.single.private, isTrue);
    expect(http.sent, contains('GET /user gho_token'));
  });

  test('GitLab: its endpoints, commit email and projects', () async {
    final http = FakeHttp()
      ..posts['/oauth/authorize_device'] = [
        (
          status: 200,
          body: {
            'device_code': 'dev',
            'user_code': 'WXYZ',
            'verification_uri': 'https://gitlab.com/oauth/device',
            'verification_uri_complete':
                'https://gitlab.com/oauth/device?user_code=WXYZ',
          },
        ),
      ]
      ..posts['/oauth/token'] = [
        (status: 200, body: {'access_token': 'glo_token'}),
      ]
      ..gets['/api/v4/user'] = (
        status: 200,
        body: {
          'username': 'sam',
          'name': 'Sam Rivera',
          'commit_email': 'sam@example.org',
        },
      )
      ..gets['/api/v4/projects'] = (
        status: 200,
        body: [
          {
            'path_with_namespace': 'team/app',
            'http_url_to_repo': 'https://gitlab.com/team/app.git',
            'visibility': 'private',
          },
        ],
      );
    final flow = DeviceFlow(http, apps: apps);
    final code = await flow.start(Forge.gitlab);
    expect(code.verificationUriComplete.toString(), contains('user_code=WXYZ'));
    final account = await flow.finish(Forge.gitlab, code, sleep: sleep);
    expect(account.host, 'gitlab.com');
    expect(account.email, 'sam@example.org');
    expect((await flow.repositories(account)).single.fullName, 'team/app');
  });

  test('a declined sign-in, and a build without OAuth apps', () async {
    final http = FakeHttp()
      ..posts['/login/oauth/access_token'] = [
        (status: 200, body: {'error': 'access_denied'}),
      ];
    final flow = DeviceFlow(http, apps: apps);
    final code = DeviceCode(
      deviceCode: 'dev',
      userCode: 'X',
      verificationUri: Uri.parse('https://github.com/login/device'),
      interval: const Duration(seconds: 1),
      expiresIn: const Duration(minutes: 5),
    );
    await expectLater(
      flow.finish(Forge.github, code, sleep: sleep),
      throwsA(
        isA<SignInFailed>().having(
          (e) => e.message,
          'message',
          contains('declined'),
        ),
      ),
    );
    await expectLater(
      flow.finish(Forge.github, code, sleep: sleep, cancelled: () => true),
      throwsA(isA<SignInFailed>()),
    );
    final none = DeviceFlow(http, apps: const ForgeApps());
    expect(none.offers(Forge.github), isFalse);
    await expectLater(none.start(Forge.github), throwsA(isA<SignInFailed>()));
  });
}
