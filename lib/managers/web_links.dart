/// Links to a repository's pages on its forge's website, as chats show
/// them (they linkify only http and https): which repository, and the
/// branch and path after it, for opening the file in a clone.
library;

/// A forge web link: the repository's address, and what followed it:
/// `<branch>/<path>` of a file or folder, or null for the repository itself.
typedef WebLink = ({String remote, String? rest});

/// A link to a GitHub, GitLab (also self-hosted, with "gitlab" in its name)
/// or Bitbucket page of a repository; null for anything else.
WebLink? parseWebLink(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty) {
    return null;
  }
  final host = uri.host.toLowerCase();
  final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
  String remote(List<String> repository) =>
      '${uri.scheme}://$host/${repository.join('/')}';
  String? after(int from) =>
      from >= parts.length ? null : parts.sublist(from).join('/');

  if (host == 'github.com' || host == 'bitbucket.org') {
    if (parts.length < 2) return null;
    final repository = [parts[0], parts[1].replaceFirst(RegExp(r'\.git$'), '')];
    if (parts.length == 2) return (remote: remote(repository), rest: null);
    final kind = parts[2];
    final files = host == 'github.com'
        ? const {'blob', 'tree', 'raw'}
        : const {'src'};
    if (!files.contains(kind)) return (remote: remote(repository), rest: null);
    return (remote: remote(repository), rest: after(3));
  }
  if (host.contains('gitlab')) {
    final dash = parts.indexOf('-');
    final repository = dash < 0 ? parts : parts.sublist(0, dash);
    if (repository.length < 2) return null;
    repository[repository.length - 1] = repository.last.replaceFirst(
      RegExp(r'\.git$'),
      '',
    );
    if (dash < 0 || dash + 1 >= parts.length) {
      return (remote: remote(repository), rest: null);
    }
    final kind = parts[dash + 1];
    if (!const {'blob', 'tree', 'raw'}.contains(kind)) {
      return (remote: remote(repository), rest: null);
    }
    return (remote: remote(repository), rest: after(dash + 2));
  }
  return null;
}

/// The path in [rest] (`<branch>/<path>`) for one of [branches], trying the
/// longest branch names first, since they may hold slashes; null when no
/// branch fits, '' for the branch's root.
String? pathOnBranch(String rest, Iterable<String> branches) {
  final sorted = branches.toSet().toList()..sort((a, b) => b.length - a.length);
  for (final branch in sorted) {
    if (rest == branch) return '';
    if (rest.startsWith('$branch/')) return rest.substring(branch.length + 1);
  }
  return null;
}
