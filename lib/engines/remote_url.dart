/// Remote URLs: which repository they name, whatever form they take (https,
/// ssh, `git@host:owner/repo.git`, Azure DevOps' own forms). Port of the
/// parsing half of Genbeya's `src/utilities/remote-url.ts`; web links per
/// forge come with sharing ([[GM-10]]).
library;

/// A repository on a Git server, independent of how a remote URL spells it.
class RemoteRepository {
  const RemoteRepository({
    required this.host,
    required this.path,
    required this.scheme,
  });

  /// Lower-case host name without user or port; `dev.azure.com` for every
  /// Azure DevOps form.
  final String host;

  /// The path on the host without `.git` or outer slashes: `acme/demo`.
  final String path;

  /// How the host's website is reached: `http` only for plain-http remotes.
  final String scheme;

  /// The repository's own name: the path's last part.
  String get name => path.substring(path.lastIndexOf('/') + 1);

  Map<String, Object?> toJson() => {
    'host': host,
    'path': path,
    'scheme': scheme,
  };
}

const _maxLength = 2048;
const _schemes = {'https', 'http', 'ssh', 'git', 'git+ssh', 'ssh+git'};

/// `[user@]host:path`, Git's scp-like syntax.
final _scpLike = RegExp(r'^(?:[^@/\s]+@)?([^:/\s]+):(?!//)(.+)$');
final _schemePrefix = RegExp(r'^([a-z][a-z0-9+.-]*)://', caseSensitive: false);

/// True for Git's `<transport>::<address>`, which runs the program
/// `git-remote-<transport>` (`ext::` runs any command). No network remote is
/// spelled like that.
bool namesRemoteHelper(String url) =>
    RegExp(r'^[a-z][a-z0-9+.-]*::', caseSensitive: false).hasMatch(url.trim());

/// The repository a remote URL names, or null for local paths and anything
/// else no other machine can reach.
RemoteRepository? parseRemote(String url) {
  final text = url.trim();
  if (text.isEmpty ||
      text.length > _maxLength ||
      RegExp(r'[\s\x00-\x1f]').hasMatch(text) ||
      text.startsWith('-') ||
      namesRemoteHelper(text)) {
    return null;
  }
  final scheme = _schemePrefix.firstMatch(text)?.group(1)?.toLowerCase();
  String host;
  String path;
  if (scheme != null) {
    if (!_schemes.contains(scheme)) return null;
    final parsed = _parseUrl(text);
    if (parsed == null) return null;
    host = parsed.hostname;
    try {
      path = Uri.decodeComponent(parsed.pathname);
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  } else {
    final match = _scpLike.firstMatch(text);
    // A single letter before the colon is a Windows drive.
    if (match == null || match[1]!.length < 2) return null;
    host = match[1]!;
    path = match[2]!;
  }
  host = host.toLowerCase();
  path = path
      .replaceAll(RegExp(r'^/+|/+$'), '')
      .replaceFirst(RegExp(r'\.git$'), '');
  // A host that starts with "-" would reach ssh as an option.
  if (host.isEmpty || host.startsWith('-') || path.isEmpty) return null;
  final (azureHost, azurePath) = _azure(host, path);
  return RemoteRepository(
    host: azureHost,
    path: azurePath,
    scheme: scheme == 'http' ? 'http' : 'https',
  );
}

/// Azure DevOps spells one repository four ways; all become
/// `dev.azure.com/org/project/_git/repo`.
(String, String) _azure(String host, String path) {
  final ssh = RegExp(r'^v3/([^/]+)/([^/]+)/([^/]+)$').firstMatch(path);
  if (ssh != null &&
      (host == 'ssh.dev.azure.com' || host == 'vs-ssh.visualstudio.com')) {
    return ('dev.azure.com', '${ssh[1]}/${ssh[2]}/_git/${ssh[3]}');
  }
  final organisation = RegExp(r'^([^.]+)\.visualstudio\.com$')
      .firstMatch(host)
      ?.group(1);
  if (organisation != null) {
    return (
      'dev.azure.com',
      '$organisation/${path.replaceFirst(RegExp(r'^DefaultCollection/', caseSensitive: false), '')}',
    );
  }
  return (host, path);
}

/// [url] without anything that may be secret: URLs lose their user name,
/// password, query and fragment, whatever the scheme. Git's scp-like form
/// keeps a plain user such as `git@`, which names the account on the server
/// rather than a person, but loses a `user:password@`.
String withoutCredentials(String url) {
  final text = url.trim();
  if (!RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(text)) {
    return text.replaceFirst(RegExp(r'^[^@/\\\s]*:[^@/\\\s]*@'), '');
  }
  final parsed = _parseUrl(text);
  if (parsed == null) {
    // Not a URL: drop everything up to the last @ of the authority, and the query.
    return text
        .replaceFirstMapped(
          RegExp(r'^([a-z][a-z0-9+.-]*://)[^/?#]*@', caseSensitive: false),
          (m) => m[1]!,
        )
        .replaceFirst(RegExp(r'[?#].*$'), '');
  }
  return '${parsed.protocol}//${parsed.host}${parsed.pathname}';
}

/// True when both URLs name the same repository; hosts and paths compare
/// without case, as Git hosts do.
bool sameRepository(String a, String b) {
  final first = parseRemote(a);
  final second = parseRemote(b);
  return first != null &&
      second != null &&
      first.host == second.host &&
      first.path.toLowerCase() == second.path.toLowerCase();
}

/// The parts of a URL as the WHATWG URL parser (`new URL`) gives them, for
/// the absolute URLs remotes use; null where it would throw.
class _Url {
  const _Url(this.protocol, this.hostname, this.port, this.pathname);
  final String protocol;
  final String hostname;
  final String port;
  final String pathname;
  String get host => port.isEmpty ? hostname : '$hostname:$port';
}

const _special = {
  'http': '80',
  'https': '443',
  'ws': '80',
  'wss': '443',
  'ftp': '21',
};

_Url? _parseUrl(String text) {
  final match = RegExp(
    r'^([a-z][a-z0-9+.-]*):\/\/([^/?#]*)([^?#]*)',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;
  final scheme = match[1]!.toLowerCase();
  var authority = match[2]!;
  final at = authority.lastIndexOf('@');
  if (at >= 0) authority = authority.substring(at + 1);
  String hostname;
  var port = '';
  if (authority.startsWith('[')) {
    final close = authority.indexOf(']');
    if (close < 0) return null;
    hostname = authority.substring(0, close + 1).toLowerCase();
    final rest = authority.substring(close + 1);
    if (rest.isNotEmpty) {
      if (!rest.startsWith(':')) return null;
      port = rest.substring(1);
    }
  } else {
    final colon = authority.lastIndexOf(':');
    hostname = colon >= 0 ? authority.substring(0, colon) : authority;
    if (colon >= 0) port = authority.substring(colon + 1);
  }
  if (port.isNotEmpty) {
    if (!RegExp(r'^\d+$').hasMatch(port)) return null;
    final number = int.parse(port);
    if (number > 65535) return null;
    port = '$number';
  }
  final defaultPort = _special[scheme];
  if (defaultPort != null) {
    // Special schemes: a host is required and compared in lower case.
    if (hostname.isEmpty) return null;
    hostname = hostname.toLowerCase();
    if (port == defaultPort) port = '';
  }
  var path = match[3]!;
  if (defaultPort != null && path.isEmpty) path = '/';
  return _Url('$scheme:', hostname, port, path);
}
