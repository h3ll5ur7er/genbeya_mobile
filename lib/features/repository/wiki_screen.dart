import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../access/kit/kit_host.dart';
import '../../access/kit/kit_protocol.dart';
import '../../contracts/model.dart';
import '../../managers/repository_session.dart';
import '../kit/kit_view.dart';
import '../../contracts/clones.dart';
import '../tasks/task_editing.dart';
import 'changes_screen.dart';
import 'links.dart';
import 'search_screen.dart';
import 'share_menu.dart';

/// The wiki: pages rendered by Genbeya's own renderer, the page tree in a
/// drawer, the page's place as a breadcrumb, its headings in "On this page"
/// ([[Experience#wiki]], US-5, US-6).
class WikiScreen extends ConsumerStatefulWidget {
  const WikiScreen({
    super.key,
    required this.session,
    this.record,
    this.initialPage,
    this.initialAnchor,
  });

  final RepositorySession session;

  /// The clone, in the repository's tab: then the bar shows the sync badge.
  final CloneRecord? record;

  /// A page to open instead of the home page: then the screen stands on its
  /// own (opened from a task), with a back arrow and no page tree.
  final String? initialPage;
  final String? initialAnchor;

  @override
  ConsumerState<WikiScreen> createState() => _WikiScreenState();
}

class _WikiScreenState extends ConsumerState<WikiScreen> {
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
  StreamSubscription<Object>? _changes;

  @override
  void initState() {
    super.initState();
    _host = KitHost(
      files: _session.kitFiles(),
      onFollow: (link) => followLink(
        context,
        _session,
        link,
        openPage: (path, anchor) => _open(path, anchor: anchor),
      ),
      onToggle: (document, offset) async {
        final record = _session.record;
        if (record == null || document is! KitPage) return;
        final page = await changeContent(
          context,
          ref,
          record,
          _session,
          'wiki',
          () async {
            final pages = await ref.read(pageWriterProvider(record).future);
            return pages.toggle(document, offset);
          },
        );
        if (page == null) {
          if (mounted && _page?.path == document.path) _host.show(_page!);
          return;
        }
        if (mounted && _page?.path == page.path) {
          setState(() => _page = page);
          _host.show(page);
        }
      },
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
    // After a sync or an edit: the context, and the page if it changed.
    _changes = _session.changes.listen((_) async {
      _host.updateContext(_session.kitContext());
      final path = _page?.path;
      if (path == null) return;
      try {
        final page = await _session.page(path);
        if (mounted && page.hash != _page?.hash) {
          setState(() => _page = page);
          _host.show(page);
        }
      } on Object {
        // The page went away; the tree still shows the rest.
      }
    });
    final first = widget.initialPage ?? _homePage();
    if (first != null) {
      _open(first, anchor: widget.initialAnchor, remember: false);
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _host.setTheme(dark: Theme.of(context).brightness == Brightness.dark);
  }

  String? _homePage() {
    final state = _session.state!;
    final home = '${state.settings.wikiRoot}/${state.settings.wikiHome}';
    final pages = wikiPages(state.wiki);
    if (pages.contains(home)) return home;
    return pages.firstOrNull;
  }

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
            if (widget.record != null)
              SyncBadge(record: widget.record!, session: _session),
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SearchScreen(session: _session),
                ),
              ),
            ),
            if (page != null)
              ShareMenu(
                session: _session,
                item: (kind: 'page', value: page.path),
                path: page.path,
              ),
            if (_outline.length > 1)
              IconButton(
                tooltip: 'On this page',
                icon: const Icon(Icons.toc),
                onPressed: _showOutline,
              ),
          ],
        ),
        drawer: widget.initialPage != null
            ? null
            : Drawer(
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
                      for (final node in _session.state!.wiki)
                        _treeNode(node, 0),
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
