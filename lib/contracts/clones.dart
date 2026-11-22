/// The clones on this phone, as the app keeps them in its own storage.
library;

/// How the app authenticates to a clone's remote. Secrets live in the
/// system keychain; this only says which.
enum CredentialKind {
  /// A public repository, or one the remote serves without signing in.
  none,

  /// HTTPS with a token kept for the remote's host.
  token,

  /// SSH with the key made on this device.
  sshKey,
}

/// A clone on this phone.
class CloneRecord {
  const CloneRecord({
    required this.id,
    required this.url,
    required this.name,
    required this.branch,
    required this.credential,
    required this.added,
    this.lastSync,
    this.contentBranch,
  });

  /// Its folder's name under the app's clone folder.
  final String id;

  /// The remote, without credentials.
  final String url;

  /// What the start screen calls it: the repository's name.
  final String name;

  /// The branch checked out when it was cloned.
  final String branch;
  final CredentialKind credential;
  final DateTime added;

  /// When it last synced, if ever.
  final DateTime? lastSync;

  /// The content branch fetched along, if the remote has one.
  final String? contentBranch;

  CloneRecord copyWith({DateTime? lastSync, CredentialKind? credential}) =>
      CloneRecord(
        id: id,
        url: url,
        name: name,
        branch: branch,
        credential: credential ?? this.credential,
        added: added,
        lastSync: lastSync ?? this.lastSync,
        contentBranch: contentBranch,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'url': url,
    'name': name,
    'branch': branch,
    'credential': credential.name,
    'added': added.toUtc().toIso8601String(),
    if (lastSync != null) 'lastSync': lastSync!.toUtc().toIso8601String(),
    if (contentBranch != null) 'contentBranch': contentBranch,
  };

  static CloneRecord fromJson(Map<String, Object?> json) => CloneRecord(
    id: json['id']! as String,
    url: json['url']! as String,
    name: json['name']! as String,
    branch: json['branch']! as String,
    credential: CredentialKind.values.firstWhere(
      (kind) => kind.name == json['credential'],
      orElse: () => CredentialKind.none,
    ),
    added: DateTime.parse(json['added']! as String),
    lastSync: json['lastSync'] == null
        ? null
        : DateTime.parse(json['lastSync']! as String),
    contentBranch: json['contentBranch'] as String?,
  );
}

/// The name and email a clone's commits are signed with.
typedef GitIdentity = ({String name, String email});
