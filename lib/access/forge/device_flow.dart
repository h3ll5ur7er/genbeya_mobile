/// Signing in to GitHub or GitLab with OAuth's device flow (RFC 8628): a
/// code to enter in the browser, ending in a token for the forge's Git
/// host, the account's name and email for commits, and its repositories to
/// pick from ([[Experience#signing-in]], US-3). Each forge needs an OAuth
/// app of Genbeya's with the device flow enabled; its client ID, which is
/// not secret, comes in at build time.
library;

import 'forge_http.dart';

enum Forge { github, gitlab }

/// What the forges' OAuth apps are, from the build:
/// `--dart-define=GENBEYA_GITHUB_CLIENT_ID=…`, `…GITLAB_CLIENT_ID=…`.
class ForgeApps {
  const ForgeApps({this.github, this.gitlab});

  static const fromBuild = ForgeApps(
    github: bool.hasEnvironment('GENBEYA_GITHUB_CLIENT_ID')
        ? String.fromEnvironment('GENBEYA_GITHUB_CLIENT_ID')
        : null,
    gitlab: bool.hasEnvironment('GENBEYA_GITLAB_CLIENT_ID')
        ? String.fromEnvironment('GENBEYA_GITLAB_CLIENT_ID')
        : null,
  );

  final String? github;
  final String? gitlab;

  String? clientId(Forge forge) => switch (forge) {
    Forge.github => github,
    Forge.gitlab => gitlab,
  };
}

/// The code to show, and where to enter it.
class DeviceCode {
  const DeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.interval,
    required this.expiresIn,
    this.verificationUriComplete,
  });

  final String deviceCode;
  final String userCode;
  final Uri verificationUri;

  /// The page with the code filled in, where the forge offers one.
  final Uri? verificationUriComplete;
  final Duration interval;
  final Duration expiresIn;
}

/// The account signed in to.
class ForgeAccount {
  const ForgeAccount({
    required this.forge,
    required this.host,
    required this.token,
    required this.login,
    required this.name,
    required this.email,
  });

  final Forge forge;

  /// The Git host the token is for: `github.com`, `gitlab.com`.
  final String host;
  final String token;
  final String login;
  final String name;
  final String? email;
}

/// A repository of the account, to clone.
typedef ForgeRepository = ({String fullName, String cloneUrl, bool private});

class SignInFailed implements Exception {
  const SignInFailed(this.message);
  final String message;
  @override
  String toString() => message;
}

class DeviceFlow {
  DeviceFlow(this.http, {this.apps = ForgeApps.fromBuild});

  final ForgeHttp http;
  final ForgeApps apps;

  bool offers(Forge forge) => (apps.clientId(forge) ?? '').isNotEmpty;

  String _client(Forge forge) {
    final id = apps.clientId(forge);
    if (id == null || id.isEmpty) {
      throw const SignInFailed('This build has no OAuth app for signing in.');
    }
    return id;
  }

  static final _github = Uri.parse('https://github.com');
  static final _githubApi = Uri.parse('https://api.github.com');
  static final _gitlab = Uri.parse('https://gitlab.com');

  /// Asks the forge for a code to show.
  Future<DeviceCode> start(Forge forge) async {
    final response = switch (forge) {
      Forge.github => await http.postForm(
        _github.resolve('/login/device/code'),
        {'client_id': _client(forge), 'scope': 'repo read:user user:email'},
      ),
      Forge.gitlab => await http.postForm(
        _gitlab.resolve('/oauth/authorize_device'),
        {
          'client_id': _client(forge),
          'scope': 'read_user read_api read_repository write_repository',
        },
      ),
    };
    final body = response.body;
    if (response.status != 200 ||
        body is! Map ||
        body['device_code'] is! String) {
      throw SignInFailed(
        'The forge would not start signing in (${_reason(body) ?? response.status}).',
      );
    }
    return DeviceCode(
      deviceCode: body['device_code'] as String,
      userCode: '${body['user_code']}',
      verificationUri: Uri.parse('${body['verification_uri']}'),
      verificationUriComplete: body['verification_uri_complete'] is String
          ? Uri.parse(body['verification_uri_complete'] as String)
          : null,
      interval: Duration(seconds: (body['interval'] as num?)?.toInt() ?? 5),
      expiresIn: Duration(
        seconds: (body['expires_in'] as num?)?.toInt() ?? 900,
      ),
    );
  }

  /// Waits until the user entered the code, then reads the account. Stops
  /// when [cancelled] says so, or when the code expires.
  Future<ForgeAccount> finish(
    Forge forge,
    DeviceCode code, {
    bool Function()? cancelled,
    Future<void> Function(Duration wait) sleep = _sleep,
  }) async {
    final tokenUrl = switch (forge) {
      Forge.github => _github.resolve('/login/oauth/access_token'),
      Forge.gitlab => _gitlab.resolve('/oauth/token'),
    };
    var interval = code.interval;
    final deadline = DateTime.now().add(code.expiresIn);
    while (true) {
      if (cancelled?.call() ?? false) {
        throw const SignInFailed('Signing in was cancelled.');
      }
      if (DateTime.now().isAfter(deadline)) {
        throw const SignInFailed('The code expired. Start again.');
      }
      await sleep(interval);
      final response = await http.postForm(tokenUrl, {
        'client_id': _client(forge),
        'device_code': code.deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      });
      final body = response.body;
      final token = body is Map ? body['access_token'] : null;
      if (token is String && token.isNotEmpty) return _account(forge, token);
      switch (body is Map ? body['error'] : null) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          interval += const Duration(seconds: 5);
          continue;
        case 'access_denied':
          throw const SignInFailed('Signing in was declined in the browser.');
        case 'expired_token':
          throw const SignInFailed('The code expired. Start again.');
        default:
          throw SignInFailed(
            'Signing in failed (${_reason(body) ?? response.status}).',
          );
      }
    }
  }

  Future<ForgeAccount> _account(Forge forge, String token) async {
    switch (forge) {
      case Forge.github:
        final user = await http.getJson(
          _githubApi.resolve('/user'),
          bearer: token,
        );
        final body = user.body;
        if (user.status != 200 || body is! Map) {
          throw const SignInFailed('GitHub did not say who signed in.');
        }
        var email = body['email'] as String?;
        if (email == null) {
          final emails = await http.getJson(
            _githubApi.resolve('/user/emails'),
            bearer: token,
          );
          final list = emails.body;
          if (list is List) {
            final primary = list.whereType<Map>().where(
              (e) => e['primary'] == true && e['verified'] == true,
            );
            email = primary.isEmpty ? null : primary.first['email'] as String?;
          }
        }
        final login = '${body['login']}';
        return ForgeAccount(
          forge: forge,
          host: 'github.com',
          token: token,
          login: login,
          name: (body['name'] as String?)?.trim().isNotEmpty == true
              ? (body['name'] as String).trim()
              : login,
          email: email,
        );
      case Forge.gitlab:
        final user = await http.getJson(
          _gitlab.resolve('/api/v4/user'),
          bearer: token,
        );
        final body = user.body;
        if (user.status != 200 || body is! Map) {
          throw const SignInFailed('GitLab did not say who signed in.');
        }
        final login = '${body['username']}';
        return ForgeAccount(
          forge: forge,
          host: 'gitlab.com',
          token: token,
          login: login,
          name: '${body['name'] ?? login}',
          email:
              (body['commit_email'] ?? body['public_email'] ?? body['email'])
                  as String?,
        );
    }
  }

  /// The account's repositories, most recently changed first.
  Future<List<ForgeRepository>> repositories(ForgeAccount account) async {
    final response = switch (account.forge) {
      Forge.github => await http.getJson(
        _githubApi.resolve('/user/repos?sort=pushed&per_page=100'),
        bearer: account.token,
      ),
      Forge.gitlab => await http.getJson(
        _gitlab.resolve(
          '/api/v4/projects?membership=true&order_by=last_activity_at&per_page=100&simple=true',
        ),
        bearer: account.token,
      ),
    };
    final list = response.body;
    if (response.status != 200 || list is! List) {
      throw const SignInFailed('The forge would not list the repositories.');
    }
    return [
      for (final item in list.whereType<Map>())
        switch (account.forge) {
          Forge.github => (
            fullName: '${item['full_name']}',
            cloneUrl: '${item['clone_url']}',
            private: item['private'] == true,
          ),
          Forge.gitlab => (
            fullName: '${item['path_with_namespace']}',
            cloneUrl: '${item['http_url_to_repo']}',
            private: item['visibility'] != 'public',
          ),
        },
    ];
  }

  static String? _reason(Object? body) => body is Map
      ? (body['error_description'] ?? body['error'] ?? body['message'])
            ?.toString()
      : null;

  static Future<void> _sleep(Duration wait) => Future<void>.delayed(wait);
}
