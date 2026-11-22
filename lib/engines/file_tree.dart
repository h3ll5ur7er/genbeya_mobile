/// Folder trees from repository paths. Port of Genbeya's
/// `src/utilities/file-tree.ts`.
library;

import '../contracts/model.dart';
import 'collation.dart';

class _Node {
  _Node(this.name, this.path, {this.children});
  final String name;
  final String path;
  final List<_Node>? children;

  FileNode freeze() => FileNode(
    name: name,
    path: path,
    children: children?.map((c) => c.freeze()).toList(),
  );
}

int _compare(_Node a, _Node b) =>
    (b.children != null ? 1 : 0) - (a.children != null ? 1 : 0) != 0
    ? (b.children != null ? 1 : 0) - (a.children != null ? 1 : 0)
    : collate(a.name, b.name);

/// A sorted folder tree (folders first, natural order) from repository-relative file paths.
List<FileNode> buildFileTree(Iterable<String> paths) {
  final root = _Node('', '', children: []);
  final folders = <String, _Node>{'': root};
  _Node folder(String path) {
    final known = folders[path];
    if (known != null) return known;
    final cut = path.lastIndexOf('/');
    final node = _Node(path.substring(cut + 1), path, children: []);
    folder(cut < 0 ? '' : path.substring(0, cut)).children!.add(node);
    folders[path] = node;
    return node;
  }

  for (final path in paths) {
    final cut = path.lastIndexOf('/');
    folder(cut < 0 ? '' : path.substring(0, cut)).children!
        .add(_Node(path.substring(cut + 1), path));
  }
  void sort(List<_Node> nodes) {
    stableSort(nodes, _compare);
    for (final node in nodes) {
      if (node.children != null) sort(node.children!);
    }
  }

  sort(root.children!);
  return [for (final node in root.children!) node.freeze()];
}

/// The paths of every file in [nodes], depth first.
List<String> filePaths(List<FileNode> nodes) => [
  for (final node in nodes)
    ...(node.children != null ? filePaths(node.children!) : [node.path]),
];

FileNode? findNode(List<FileNode> nodes, String path) {
  var level = nodes;
  FileNode? found;
  for (final part in path.split('/')) {
    found = level.where((node) => node.name == part).firstOrNull;
    level = found?.children ?? const [];
  }
  return found;
}
