/// Wiki structure: pages are Markdown files below the wiki folder, and
/// `Architecture.md` is the parent page of the folder `Architecture/`. File
/// names use dashes for spaces: `Getting-started.md` is "Getting started".
/// Port of Genbeya's `src/engines/wiki-engine.ts`.
library;

import '../contracts/model.dart';
import 'collation.dart';
import 'file_tree.dart';
import 'repository_path.dart';

bool _isMarkdown(String name) => name.toLowerCase().endsWith('.md');
String _titleOfName(String name) => name.replaceAll('-', ' ');
int _byTitle(WikiNode a, WikiNode b) => collate(a.title, b.title);
String _baseName(String path) => path.substring(path.lastIndexOf('/') + 1);

List<WikiNode> _nodes(List<FileNode> level) {
  final folders = level.where((node) => node.children != null).toList();
  final pages = level
      .where((node) => node.children == null && _isMarkdown(node.name))
      .toList();
  String pageName(FileNode page) =>
      page.name.substring(0, page.name.length - 3);
  final result = <WikiNode>[
    for (final folder in folders)
      WikiNode(
        title: _titleOfName(folder.name),
        path: pages
            .where((page) => pageName(page) == folder.name)
            .firstOrNull
            ?.path,
        folder: folder.path,
        children: _nodes(folder.children!),
      ),
  ]..removeWhere((node) => node.path == null && node.children.isEmpty);
  for (final page in pages) {
    if (!folders.any((folder) => folder.name == pageName(page))) {
      result.add(
        WikiNode(
          title: _titleOfName(pageName(page)),
          path: page.path,
          folder: null,
          children: const [],
        ),
      );
    }
  }
  stableSort(result, _byTitle);
  return result;
}

/// A page references can name.
typedef ReferencePage = ({String title, String path});

class WikiEngine {
  /// The page tree of the wiki folder; the home page comes first.
  List<WikiNode> tree(
    Iterable<String> files, {
    required String wikiRoot,
    required String wikiHome,
  }) {
    final root = findNode(
      buildFileTree(files.where((file) => within(file, wikiRoot))),
      wikiRoot,
    );
    final home = '$wikiRoot/$wikiHome';
    final nodes = _nodes(root?.children ?? const []);
    stableSort(
      nodes,
      (a, b) => (b.path == home ? 1 : 0) - (a.path == home ? 1 : 0),
    );
    return nodes;
  }

  /// Every page of the tree, parents before their subpages: what references can name.
  List<ReferencePage> pages(
    Iterable<String> files, {
    required String wikiRoot,
    required String wikiHome,
  }) {
    List<ReferencePage> walk(List<WikiNode> level) => [
      for (final node in level) ...[
        if (node.path != null) (title: node.title, path: node.path!),
        ...walk(node.children),
      ],
    ];
    return walk(tree(files, wikiRoot: wikiRoot, wikiHome: wikiHome));
  }

  bool isPage(String path, {required String wikiRoot}) =>
      within(path, wikiRoot) && _isMarkdown(path);

  String titleOf(String path) => _titleOfName(
    _baseName(path).replaceFirst(RegExp(r'\.md$', caseSensitive: false), ''),
  );

  /// The content of a new page: its title as the heading.
  String newPage(String path) => '# ${titleOf(path)}\n\n';

  String subpageFolder(String page) =>
      page.replaceFirst(RegExp(r'\.md$', caseSensitive: false), '');

  /// The renames that move a page, and its subpages when it has them.
  List<(String, String)> planMove(String from, String to, bool hasSubpages) {
    if (from == to) return const [];
    final folder = subpageFolder(from);
    // Ignoring case, as Windows and macOS see one folder in both spellings.
    if (hasSubpages && within(to.toLowerCase(), folder.toLowerCase())) {
      throw ArgumentError('A page cannot move below itself.');
    }
    return hasSubpages
        ? [(from, to), (folder, subpageFolder(to))]
        : [(from, to)];
  }
}
