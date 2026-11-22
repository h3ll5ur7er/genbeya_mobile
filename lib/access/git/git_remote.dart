/// What the app asks of Git beyond reading objects: talking to remotes,
/// cloning, and a clone's own settings. The native core implements it
/// ([NativeGitRemote]); tests use a fake.
library;

/// How to reach a remote: nothing, a token, or the device's SSH key, and
/// the SSH host keys the user trusts.
class RemoteAccess {
  const RemoteAccess.none({this.trustedHostKeys = const []})
    : username = '',
      token = null,
      privateKey = null,
      publicKey = null;

  const RemoteAccess.token({
    required this.username,
    required String this.token,
    this.trustedHostKeys = const [],
  }) : privateKey = null,
       publicKey = null;

  const RemoteAccess.sshKey({
    required this.username,
    required String this.privateKey,
    required String this.publicKey,
    this.trustedHostKeys = const [],
  }) : token = null;

  final String username;
  final String? token;
  final String? privateKey;
  final String? publicKey;
  final List<String> trustedHostKeys;
}

/// Clone progress, as the core reports it.
typedef CloneProgress = ({
  int receivedObjects,
  int totalObjects,
  int indexedDeltas,
  int totalDeltas,
  int receivedBytes,
});

/// A clone's checked-out state.
typedef CloneHead = ({
  String? branch,
  String commit,
  int ahead,
  int behind,
  int dirty,
  bool shallow,
});

/// Why a remote operation failed.
sealed class RemoteFailure implements Exception {
  const RemoteFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The SSH server's key isn't trusted yet: ask, then retry with it trusted.
class HostKeyUnknown extends RemoteFailure {
  const HostKeyUnknown(this.host, this.fingerprint)
    : super('The server $host has a key this phone does not know yet.');
  final String host;
  final String fingerprint;
}

/// The remote refused the credentials, or wanted some.
class AuthFailed extends RemoteFailure {
  const AuthFailed(super.message);
}

class Cancelled extends RemoteFailure {
  const Cancelled() : super('Cancelled.');
}

/// Anything else: the remote's own message.
class GitFailure extends RemoteFailure {
  const GitFailure(super.message);
}

abstract interface class GitRemote {
  /// The remote's default branch and every branch, without cloning.
  Future<({String? defaultBranch, List<String> branches})> branches(
    String url,
    RemoteAccess access,
  );

  /// Clones [url] into the new folder [dir]; [extraBranches] the remote has
  /// come along. [operation] names it for [cancel].
  Future<void> clone({
    required String url,
    required String dir,
    required String? branch,
    required List<String> extraBranches,
    required int? depth,
    required RemoteAccess access,
    required int operation,
    void Function(CloneProgress progress)? onProgress,
  });

  void cancel(int operation);

  Future<CloneHead> head(String dir);

  /// A value of the clone's Git configuration, or null.
  Future<String?> getConfig(String dir, String key);

  /// Sets, or with null removes, a value of the clone's own Git configuration.
  Future<void> setConfig(String dir, String key, String? value);

  /// Makes a new Ed25519 key.
  Future<({String privateKey, String publicKey, String fingerprint})>
  generateSshKey(String comment);
}
