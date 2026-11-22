import '../../src/rust/api/git.dart' as core;
import '../../src/rust/git.dart' as core;
import '../git/git_remote.dart';
import 'transfers.dart';

/// [GitRemote] through the Rust core; its typed errors become [RemoteFailure]s.
class NativeGitRemote implements GitRemote {
  const NativeGitRemote();

  core.RemoteOptions _options(RemoteAccess access) => core.RemoteOptions(
    auth: switch (access) {
      RemoteAccess(token: final token?) => core.Auth.token(
        username: access.username,
        token: token,
      ),
      RemoteAccess(privateKey: final key?) => core.Auth.sshKey(
        username: access.username,
        publicKey: access.publicKey,
        privateKey: key,
      ),
      _ => const core.Auth.none(),
    },
    trustedHostKeys: access.trustedHostKeys,
  );

  Future<T> _mapped<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on core.CoreError catch (error) {
      throw switch (error) {
        core.CoreError_HostKeyUnknown(:final host, :final fingerprint) =>
          HostKeyUnknown(host, fingerprint),
        core.CoreError_AuthFailed(:final message) => AuthFailed(message),
        core.CoreError_Cancelled() => const Cancelled(),
        core.CoreError_InvalidPath(:final path) => GitFailure(
          'Invalid path: $path',
        ),
        core.CoreError_InvalidArgument(:final message) => GitFailure(message),
        core.CoreError_Git(:final message) => GitFailure(message),
        core.CoreError_Io(:final message) => GitFailure(message),
      };
    }
  }

  @override
  Future<({String? defaultBranch, List<String> branches})> branches(
    String url,
    RemoteAccess access,
  ) => _mapped(() async {
    final listed = await core.remoteBranches(
      url: url,
      remote: _options(access),
    );
    return (defaultBranch: listed.defaultBranch, branches: listed.branches);
  });

  @override
  Future<void> clone({
    required String url,
    required String dir,
    required String? branch,
    required List<String> extraBranches,
    required int? depth,
    required RemoteAccess access,
    required int operation,
    void Function(CloneProgress progress)? onProgress,
  }) => _mapped(
    () => runTransfer(
      core.cloneRepository(
        url: url,
        dir: dir,
        branch: branch,
        extraBranches: extraBranches,
        depth: depth,
        remote: _options(access),
        operationId: BigInt.from(operation),
      ),
      onProgress: (p) => onProgress?.call((
        receivedObjects: p.receivedObjects,
        totalObjects: p.totalObjects,
        indexedDeltas: p.indexedDeltas,
        totalDeltas: p.totalDeltas,
        receivedBytes: p.receivedBytes.toInt(),
      )),
    ),
  );

  @override
  void cancel(int operation) =>
      core.cancelOperation(operationId: BigInt.from(operation));

  @override
  Future<CloneHead> head(String dir) => _mapped(() async {
    final head = await core.head(dir: dir);
    return (
      branch: head.branch,
      commit: head.commit,
      ahead: head.ahead,
      behind: head.behind,
      dirty: head.dirty.length,
      shallow: head.shallow,
    );
  });

  @override
  Future<String?> getConfig(String dir, String key) =>
      _mapped(() => core.configValue(dir: dir, key: key));

  @override
  Future<void> setConfig(String dir, String key, String? value) =>
      _mapped(() => core.setConfigValue(dir: dir, key: key, value: value));

  @override
  Future<({String privateKey, String publicKey, String fingerprint})>
  generateSshKey(String comment) => _mapped(() async {
    final key = await core.generateSshKey(comment: comment);
    return (
      privateKey: key.privateKey,
      publicKey: key.publicKey,
      fingerprint: key.fingerprint,
    );
  });
}
