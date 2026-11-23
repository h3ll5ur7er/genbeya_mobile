/// The clones on this phone: adding one from a URL, how the app reaches its
/// remote, its Git identity, its state on the start screen, and removing it
/// ([[Experience#navigation]], [[Experience#signing-in]], US-1, US-3).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../access/git/git_remote.dart';
import '../access/storage/json_store.dart';
import '../access/storage/secret_store.dart';
import '../contracts/clones.dart';
import '../engines/content_layout.dart';
import '../engines/remote_url.dart';

/// Commits a new clone fetches unless full history is asked for.
const defaultDepth = 50;

/// A remote checked before cloning: where it is, how to reach it, what it has.
class RemotePlan {
  const RemotePlan({
    required this.url,
    required this.repository,
    required this.credential,
    required this.defaultBranch,
    required this.branches,
  });

  /// The URL to clone, without credentials.
  final String url;
  final RemoteRepository repository;
  final CredentialKind credential;
  final String? defaultBranch;
  final List<String> branches;

  /// Whether the remote has Genbeya's content branch, which comes along.
  bool get hasContentBranch => branches.contains(defaultContentBranch);
}

/// A clone and how it stands now.
class CloneStatus {
  const CloneStatus(this.record, {this.head, this.bytes, this.problem});
  final CloneRecord record;
  final CloneHead? head;

  /// Its size on disk.
  final int? bytes;

  /// Why its state couldn't be read (a folder gone, a broken clone).
  final String? problem;
}

class RepositoriesManager {
  RepositoriesManager({
    required this.root,
    required this.git,
    required this.secrets,
    this.deviceName = 'Genbeya Mobile',
  }) : _registry = JsonStore(File('${root.path}/repositories.json')),
       _settings = JsonStore(File('${root.path}/remote-settings.json'));

  /// The app's own storage folder.
  final Directory root;
  final GitRemote git;
  final SecretStore secrets;

  /// Labels the SSH key made on this device.
  final String deviceName;

  final JsonStore _registry;

  /// Not secret: trusted host keys, the public SSH key, the last identity.
  final JsonStore _settings;
  int _operation = 0;
  final _random = Random.secure();

  String folderOf(CloneRecord record) => '${root.path}/clones/${record.id}';

  Future<List<CloneRecord>> clones() async {
    final data = await _registry.read();
    if (data is! List) return [];
    return [
      for (final entry in data)
        if (entry is Map<String, Object?>) CloneRecord.fromJson(entry),
    ];
  }

  Future<void> _saveClones(List<CloneRecord> records) =>
      _registry.write([for (final record in records) record.toJson()]);

  Future<Map<String, Object?>> _readSettings() async {
    final data = await _settings.read();
    return data is Map<String, Object?> ? data : <String, Object?>{};
  }

  Future<void> _updateSettings(
    void Function(Map<String, Object?> settings) change,
  ) async {
    final settings = await _readSettings();
    change(settings);
    await _settings.write(settings);
  }

  // ---------- Credentials ----------

  /// How a URL is reached: SSH URLs with the device's key, others with a
  /// token when one is kept for the host, else without.
  Future<CredentialKind> credentialFor(String url) async {
    if (_isSsh(url)) return CredentialKind.sshKey;
    final repository = parseRemote(url);
    if (repository != null && await tokenFor(repository.host) != null) {
      return CredentialKind.token;
    }
    return CredentialKind.none;
  }

  Future<void> saveToken(String host, String username, String token) =>
      secrets.write(
        'token:${host.toLowerCase()}',
        jsonEncode({'username': username, 'token': token}),
      );

  Future<({String username, String token})?> tokenFor(String host) async {
    final text = await secrets.read('token:${host.toLowerCase()}');
    if (text == null) return null;
    final data = jsonDecode(text) as Map<String, Object?>;
    return (
      username: data['username']! as String,
      token: data['token']! as String,
    );
  }

  Future<void> forgetToken(String host) =>
      secrets.delete('token:${host.toLowerCase()}');

  /// The user name a token goes with: GitLab wants `oauth2`, GitHub any.
  static String tokenUser(String host) =>
      host.contains('gitlab') ? 'oauth2' : 'x-access-token';

  /// The public half of this device's SSH key, made on first use; the
  /// private half stays in the keychain.
  Future<({String publicKey, String fingerprint})> deviceKey() async {
    final settings = await _readSettings();
    final public = settings['sshPublicKey'];
    final fingerprint = settings['sshFingerprint'];
    if (public is String &&
        fingerprint is String &&
        await secrets.read('ssh-key') != null) {
      return (publicKey: public, fingerprint: fingerprint);
    }
    final key = await git.generateSshKey(deviceName);
    await secrets.write('ssh-key', key.privateKey);
    await _updateSettings((settings) {
      settings['sshPublicKey'] = key.publicKey;
      settings['sshFingerprint'] = key.fingerprint;
    });
    return (publicKey: key.publicKey, fingerprint: key.fingerprint);
  }

  Future<List<String>> trustedHostKeys() async {
    final keys = (await _readSettings())['trustedHostKeys'];
    return keys is List ? keys.whereType<String>().toList() : [];
  }

  /// Trusts an SSH server's key, after the user compared its fingerprint.
  Future<void> trustHostKey(String fingerprint) => _updateSettings((settings) {
    final keys = (settings['trustedHostKeys'] as List?)?.cast<String>() ?? [];
    if (!keys.contains(fingerprint)) keys.add(fingerprint);
    settings['trustedHostKeys'] = keys;
  });

  Future<RemoteAccess> accessFor(String url, CredentialKind kind) async {
    final trusted = await trustedHostKeys();
    switch (kind) {
      case CredentialKind.none:
        return RemoteAccess.none(trustedHostKeys: trusted);
      case CredentialKind.token:
        final host = parseRemote(url)?.host ?? '';
        final token = await tokenFor(host);
        if (token == null) {
          throw AuthFailed('No token is kept for $host.');
        }
        return RemoteAccess.token(
          username: token.username,
          token: token.token,
          trustedHostKeys: trusted,
        );
      case CredentialKind.sshKey:
        final key = await deviceKey();
        return RemoteAccess.sshKey(
          username: _sshUser(url),
          privateKey: (await secrets.read('ssh-key'))!,
          publicKey: key.publicKey,
          trustedHostKeys: trusted,
        );
    }
  }

  // ---------- Identity ----------

  Future<GitIdentity?> identityOf(CloneRecord record) async {
    final dir = folderOf(record);
    final name = await git.getConfig(dir, 'user.name');
    final email = await git.getConfig(dir, 'user.email');
    if (name == null && email == null) return null;
    return (name: name ?? '', email: email ?? '');
  }

  Future<void> setIdentity(CloneRecord record, GitIdentity identity) async {
    final dir = folderOf(record);
    await git.setConfig(dir, 'user.name', identity.name.trim());
    await git.setConfig(dir, 'user.email', identity.email.trim());
    await _updateSettings((settings) {
      settings['lastIdentity'] = {
        'name': identity.name.trim(),
        'email': identity.email.trim(),
      };
    });
  }

  /// The identity used last, to fill in for a new clone.
  Future<GitIdentity?> lastIdentity() async {
    final last = (await _readSettings())['lastIdentity'];
    if (last is! Map) return null;
    return (name: '${last['name'] ?? ''}', email: '${last['email'] ?? ''}');
  }

  // ---------- Cloning ----------

  /// Checks a URL before cloning: that it names a remote repository, and
  /// what branches it has. Throws [HostKeyUnknown] the first time an SSH
  /// server answers, [AuthFailed] without the access it wants.
  Future<RemotePlan> prepare(String url, {CredentialKind? credential}) async {
    final text = url.trim();
    final repository = parseRemote(text);
    if (repository == null) {
      throw const FormatException(
        'That is not the address of a repository on a server.',
      );
    }
    final clean = withoutCredentials(text);
    final kind = credential ?? await credentialFor(clean);
    final listed = await git.branches(clean, await accessFor(clean, kind));
    if (listed.branches.isEmpty) {
      throw const GitFailure('The repository is empty: it has no branches.');
    }
    return RemotePlan(
      url: clean,
      repository: repository,
      credential: kind,
      defaultBranch: listed.defaultBranch,
      branches: listed.branches,
    );
  }

  /// Clones a prepared remote: [branch] (its default when null), [depth]
  /// commits deep (all with null), the content branch along when the remote
  /// has it. A failed or cancelled clone leaves nothing behind.
  Future<CloneRecord> add(
    RemotePlan plan, {
    String? branch,
    int? depth = defaultDepth,
    GitIdentity? identity,
    void Function(int operation)? onStart,
    void Function(CloneProgress progress)? onProgress,
  }) async {
    final chosen = branch ?? plan.defaultBranch ?? plan.branches.first;
    final id = _newId(plan.repository.name);
    final record = CloneRecord(
      id: id,
      url: plan.url,
      name: plan.repository.name,
      branch: chosen,
      credential: plan.credential,
      added: DateTime.now(),
      contentBranch: plan.hasContentBranch && chosen != defaultContentBranch
          ? defaultContentBranch
          : null,
    );
    final dir = folderOf(record);
    await Directory('${root.path}/clones').create(recursive: true);
    final operation = ++_operation;
    onStart?.call(operation);
    try {
      await git.clone(
        url: plan.url,
        dir: dir,
        branch: chosen,
        extraBranches: [?record.contentBranch],
        depth: depth,
        access: await accessFor(plan.url, plan.credential),
        operation: operation,
        onProgress: onProgress,
      );
      if (identity != null) await setIdentity(record, identity);
    } catch (_) {
      final folder = Directory(dir);
      if (folder.existsSync()) await folder.delete(recursive: true);
      rethrow;
    }
    await _saveClones([...await clones(), record]);
    return record;
  }

  void cancel(int operation) => git.cancel(operation);

  /// How a clone stands: its head and its size on disk.
  Future<CloneStatus> status(CloneRecord record) async {
    final dir = Directory(folderOf(record));
    if (!dir.existsSync()) {
      return CloneStatus(record, problem: 'Its folder is gone.');
    }
    try {
      return CloneStatus(
        record,
        head: await git.head(dir.path),
        bytes: await _sizeOf(dir),
      );
    } on RemoteFailure catch (error) {
      return CloneStatus(record, problem: error.message);
    }
  }

  /// Notes that [id] synced now.
  Future<void> markSynced(String id) async {
    final records = await clones();
    await _saveClones([
      for (final r in records)
        r.id == id ? r.copyWith(lastSync: DateTime.now()) : r,
    ]);
  }

  /// Removes a clone and its folder. Commits not pushed yet go with it, so
  /// the screen asks first. Tokens stay, for other clones of the host.
  Future<void> remove(String id) async {
    final records = await clones();
    final record = records.where((r) => r.id == id).firstOrNull;
    if (record == null) return;
    final dir = Directory(folderOf(record));
    if (dir.existsSync()) await dir.delete(recursive: true);
    await _saveClones([
      for (final r in records)
        if (r.id != id) r,
    ]);
  }

  String _newId(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final suffix = List.generate(
      3,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '${slug.isEmpty ? 'repository' : slug}-$suffix';
  }

  static Future<int> _sizeOf(Directory dir) async {
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }
}

bool _isSsh(String url) {
  final text = url.trim().toLowerCase();
  if (RegExp(r'^(ssh|git\+ssh|ssh\+git)://').hasMatch(text)) return true;
  return !text.contains('://') && parseRemote(text) != null;
}

/// The account on the SSH server: the URL's user, `git` when it names none.
String _sshUser(String url) {
  final text = url.trim();
  final scheme = RegExp(r'^[a-z+]+://([^@/]+)@').firstMatch(text);
  if (scheme != null) return Uri.decodeComponent(scheme[1]!.split(':').first);
  final scp = RegExp(r'^([^@/\s:]+)@[^:/\s]+:').firstMatch(text);
  return scp?.group(1) ?? 'git';
}
