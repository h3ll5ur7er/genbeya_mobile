import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../contracts/clones.dart';
import '../../engines/search_engine.dart';
import '../../managers/repository_session.dart';
import '../../managers/search.dart';
import '../../managers/task_views.dart';
import '../../managers/today.dart';
import '../repositories/format.dart';
import '../repositories/identity_dialog.dart';
import '../repositories/providers.dart';
import '../tasks/task_look.dart';
import 'changes_screen.dart';
import 'search_screen.dart';
import 'session_provider.dart';
import 'task_view_screen.dart';
import 'wiki_screen.dart';

/// **Today** ([[Experience#today]]): the user's open tasks, dated checklist
/// items and mentions, computed from the files ([[GM-14]]).
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({
    super.key,
    required this.session,
    required this.record,
    this.active = true,
  });

  final RepositorySession session;
  final CloneRecord record;

  /// Whether its tab is the one shown: Today is worked out again each time
  /// it is.
  final bool active;

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  late Future<Today> _today;
  StreamSubscription<Object>? _changes;

  @override
  void initState() {
    super.initState();
    _today = _compute();
    _changes = widget.session.changes.listen((_) {
      // setState must not return the Future: Flutter's debug build throws
      // then, after the assignment but before scheduling the rebuild.
      if (mounted) {
        setState(() {
          _today = _compute();
        });
      }
    });
  }

  @override
  void didUpdateWidget(TodayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _today = _compute();
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<Today> _compute() async {
    final state = widget.session.state!;
    final on = today();
    final handle = state.me;
    var pages = const <ContentHit>[];
    if (handle != null) {
      try {
        pages = (await widget.session.search(SearchQuery(text: '@$handle')))
            .wiki;
      } on Object {
        // Pages are a bonus; tasks come from the model.
      }
    }
    return buildToday(state, on: on, pageHits: pages);
  }

  Future<void> _refresh() async {
    try {
      final report = await syncRepository(ref, widget.record, widget.session);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeSync(report))));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  void _openTask(String path) {
    final task = widget.session.state!.tasks
        .where((t) => t.path == path)
        .firstOrNull;
    if (task == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TaskViewScreen(session: widget.session, task: task),
      ),
    );
  }

  void _open(String path) {
    if (widget.session.state!.tasks.any((t) => t.path == path)) {
      return _openTask(path);
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WikiScreen(session: widget.session, initialPage: path),
      ),
    );
  }

  Future<void> _setIdentity() async {
    final manager = await ref.read(repositoriesManagerProvider.future);
    final current = await manager.identityOf(widget.record);
    if (!mounted) return;
    final identity = await showIdentityDialog(context, current);
    if (identity == null) return;
    await manager.setIdentity(widget.record, identity);
    // The session reads who "me" is when it loads.
    ref.invalidate(sessionProvider(widget.record));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Today'),
      actions: [
        SyncBadge(record: widget.record, session: widget.session),
        IconButton(
          tooltip: 'Search',
          icon: const Icon(Icons.search),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SearchScreen(session: widget.session),
            ),
          ),
        ),
      ],
    ),
    body: FutureBuilder<Today>(
      future: _today,
      builder: (context, snapshot) {
        final today = snapshot.data;
        if (today == null) {
          return snapshot.hasError
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text("Couldn't work out Today: ${snapshot.error}"),
                )
              : const Center(child: CircularProgressIndicator());
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 32),
            children: today.me == null
                ? _whoAmI(context)
                : _sections(context, today),
          ),
        );
      },
    ),
  );

  List<Widget> _whoAmI(BuildContext context) {
    final theme = Theme.of(context);
    return [
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Who are you here?', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text(
              'Today shows your tasks, the checklist items due for you and where you are mentioned. '
              "It knows you by the Git name and email this clone signs commits with: they have to match "
              'someone among the people of the repository, listed in .genbeya.yml or found as commit authors, '
              'by name, email or alias.',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _setIdentity,
              icon: const Icon(Icons.badge_outlined),
              label: const Text('Set my name and email'),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _sections(BuildContext context, Today today) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = widget.session.state!.settings;
    Color? toneColor0(DueTone? tone) => switch (tone) {
      DueTone.overdue => toneColor('red', scheme),
      DueTone.soon => toneColor('yellow', scheme),
      null => null,
    };
    Widget header(String text, int count) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text('$text · $count', style: theme.textTheme.titleMedium),
    );
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(
          'For ${today.me!.name} (@${today.me!.handle})',
          style: theme.textTheme.bodySmall,
        ),
      ),
      if (today.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nothing needs you right now: no open tasks of yours, no dated checklist items, no mentions.',
          ),
        ),
      if (today.tasks.isNotEmpty) ...[
        header('My tasks', today.tasks.length),
        for (final item in today.tasks)
          ListTile(
            leading: Icon(
              Icons.circle,
              size: 12,
              color: statusColor(
                statusTone(
                  settings.statuses.indexOf(item.task.status),
                  settings.statuses.length,
                ),
                scheme,
              ),
            ),
            title: Text(item.task.title),
            subtitle: Text(
              [
                displayId(item.task.id),
                titleCase(item.task.status),
                if (item.task.priority != 'none') titleCase(item.task.priority),
              ].join(' · '),
            ),
            trailing: item.due == null
                ? null
                : Text(
                    item.due!,
                    style: TextStyle(color: toneColor0(item.tone)),
                  ),
            onTap: () => _openTask(item.task.path),
          ),
      ],
      if (today.checklist.isNotEmpty) ...[
        header('Checklist', today.checklist.length),
        for (final item in today.checklist)
          ListTile(
            leading: const Icon(Icons.check_box_outline_blank),
            title: Text(item.text),
            subtitle: Text(item.title),
            trailing: Text(
              item.date,
              style: TextStyle(color: toneColor0(item.tone)),
            ),
            onTap: () => _open(item.path),
          ),
      ],
      if (today.mentions.isNotEmpty) ...[
        header('Mentions', today.mentions.length),
        for (final mention in today.mentions)
          ListTile(
            leading: Icon(switch (mention.kind) {
              'comment' => Icons.chat_bubble_outline,
              'page' => Icons.article_outlined,
              _ => Icons.task_alt,
            }),
            title: Text(
              mention.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              [
                mention.title,
                if (mention.date case final date?)
                  if (DateTime.tryParse(date) case final at?)
                    formatAgo(at)
                  else
                    date,
              ].join(' · '),
            ),
            onTap: () => _open(mention.path),
          ),
      ],
    ];
  }
}
