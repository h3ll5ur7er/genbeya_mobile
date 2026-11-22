import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../access/kit/kit_host.dart';
import '../../access/kit/kit_protocol.dart';
import '../../contracts/clones.dart';
import '../../contracts/model.dart';
import '../../managers/repository_session.dart';
import '../kit/kit_view.dart';
import 'task_view_screen.dart';

/// The wiki: pages rendered by Genbeya's own renderer, the page tree in a
/// drawer, the page's place as a breadcrumb, its headings in "On this page"
/// ([[Experience#wiki]], US-5, US-6).
class WikiScreen extends StatefulWidget {
  const WikiScreen({super.key, required this.record, required this.session});

  final CloneRecord record;
  final RepositorySession session;

  @override
  State<WikiScreen> createState() => _WikiScreenState();
}

class _WikiScreenState extends State<WikiScreen> {
  late final KitHost _host;
  final _scaffold = GlobalKey<ScaffoldState>();
  KitPage? _page;
  final _history = <String>[];
  List<OutlineHeading> _outline = const [];
  String? _pendingAnchor;
  String? _problem;
  final _opened = Stopwatch();
  int? _openMs;

  RepositorySession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _host = KitHost(
      files: _session.kitFiles(),
      onFollow: _follow,
      onToggle: (document, offset) async => _say(
        'Ticking checkboxes saves the page, which comes with editing (GM-11).',
      ),
      onOutline: (headings) {
        if (_opened.isRunning) {
          _opened.stop();
          _openMs = _opened.elapsedMilliseconds;
        }
        setState(() => _outline = headings);
        final anchor = _pendingAnchor;
        _pendingAnchor = null;
        if (anchor != null) _host.reveal(anchor);
      },
    )..updateContext(_session.kitContext());
    final home = _homePage();
    if (home != null) _open(home, remember: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _host.setTheme(dark: Theme.of(context).brightness == Brightness.dark);
  }

  String? _homePage() {
    final state = _session.state!;
    final home = '${state.settings.wikiRoot}/${state.settings.wikiHome}';
    final pages = _allPages(state.wiki);
    if (pages.contains(home)) return home;
    return pages.firstOrNull;
  }

  static List<String> _allPages(List<WikiNode> nodes) => [
    for (final node in nodes) ...[?node.path, ..._allPages(node.children)],
  ];

  Future<void> _open(
    String path, {
    String? anchor,
    bool remember = true,
  }) async {
    if (remember && _page != null && _page!.path != path) {
      _history.add(_page!.path);
    }
    if (_page?.path == path) {
      if (anchor != null) _host.reveal(anchor);
      return;
    }
    _opened
      ..reset()
      ..start();
    try {
      final page = await _session.page(path);
      if (!mounted) return;
      setState(() {
        _page = page;
        _problem = null;
        _outline = const [];
        _pendingAnchor = anchor;
      });
      _host.show(page);
    } on Object catch (error) {
      if (mounted) setState(() => _problem = "Couldn't open $path: $error");
    }
  }

  void _follow(FollowedLink link) {
    switch (link) {
      case ExternalLink(:final url):
        launchUrl(url, mode: LaunchMode.externalApplication);
      case MissingPage(:final title):
        _say(
          '"$title" has no page yet. Creating pages comes with editing (GM-16).',
        );
      case PersonLink(:final handle):
        final person = _session.state!.people
            .where((p) => p.handle.toLowerCase() == handle.toLowerCase())
            .firstOrNull;
        _say(
          person == null ? '@$handle' : '${person.name} (@${person.handle})',
        );
      case FileLink(:final path, :final anchor):
        final state = _session.state!;
        final task = state.tasks.where((t) => t.path == path).firstOrNull;
        if (task != null) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TaskViewScreen(session: _session, task: task),
            ),
          );
        } else if (_allPages(state.wiki).contains(path)) {
          _open(path, anchor: anchor);
        } else {
          _say('$path: files open in Code, which comes with GM-17.');
        }
    }
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// The page's place: the titles of the pages above it in the tree.
  List<String> _breadcrumb() {
    final path = _page?.path;
    if (path == null) return const [];
    List<String>? walk(List<WikiNode> nodes, List<String> above) {
      for (final node in nodes) {
        if (node.path == path) return above;
        final found = walk(node.children, [...above, node.title]);
        if (found != null) return found;
      }
      return null;
    }

    return walk(_session.state!.wiki, const []) ?? const [];
  }

  void _showOutline() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final heading in _outline)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.only(
                  left: 16.0 + (heading.level - 1) * 16,
                  right: 16,
                ),
                title: Text(heading.text),
                onTap: () {
                  Navigator.pop(context);
                  _host.reveal(heading.id);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final crumbs = _breadcrumb();
    return PopScope(
      canPop: _history.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _history.isNotEmpty) {
          _open(_history.removeLast(), remember: false);
        }
      },
      child: Scaffold(
        key: _scaffold,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(page?.title ?? 'Wiki'),
              if (crumbs.isNotEmpty)
                Text(
                  crumbs.join(' › '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          actions: [
            if (_outline.length > 1)
              IconButton(
                tooltip: 'On this page',
                icon: const Icon(Icons.toc),
                onPressed: _showOutline,
              ),
          ],
        ),
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              children: [
                ListTile(
                  title: Text(
                    _session.state!.settings.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  subtitle: _openMs == null
                      ? null
                      : Text('Last page opened in $_openMs ms'),
                ),
                for (final node in _session.state!.wiki) _treeNode(node, 0),
              ],
            ),
          ),
        ),
        body: _problem != null
            ? Padding(padding: const EdgeInsets.all(24), child: Text(_problem!))
            : page == null && _homePage() == null
            ? const Center(child: Text('This wiki has no pages yet.'))
            : KitView(host: _host),
      ),
    );
  }

  Widget _treeNode(WikiNode node, int depth) {
    final selected = node.path != null && node.path == _page?.path;
    void openNode() {
      Navigator.pop(context);
      _open(node.path!);
    }

    if (node.children.isEmpty) {
      return ListTile(
        dense: true,
        selected: selected,
        contentPadding: EdgeInsets.only(left: 16.0 + depth * 16, right: 16),
        title: Text(node.title),
        onTap: node.path == null ? null : openNode,
      );
    }
    return ExpansionTile(
      dense: true,
      tilePadding: EdgeInsets.only(left: 16.0 + depth * 16, right: 16),
      initiallyExpanded: _contains(node, _page?.path),
      title: InkWell(
        onTap: node.path == null ? null : openNode,
        child: Text(
          node.title,
          style: selected
              ? TextStyle(color: Theme.of(context).colorScheme.primary)
              : null,
        ),
      ),
      children: [
        for (final child in node.children) _treeNode(child, depth + 1),
      ],
    );
  }

  static bool _contains(WikiNode node, String? path) =>
      path != null &&
      (node.path == path || node.children.any((c) => _contains(c, path)));
}
