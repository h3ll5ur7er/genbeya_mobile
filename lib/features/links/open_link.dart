import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../contracts/clones.dart';
import '../../engines/genbeya_link.dart';
import '../../engines/remote_url.dart';
import '../../managers/web_links.dart';
import '../repositories/add_repository_screen.dart';
import '../repositories/providers.dart';
import '../repository/links.dart';
import '../repository/repository_shell.dart';
import '../repository/session_provider.dart';
import '../repository/task_view_screen.dart';
import '../repository/wiki_screen.dart';

/// Opens what [text] holds: a Genbeya link, or a forge web link (which
/// chats linkify where they leave `genbeya://` as plain text).
Future<void> openLinkText(
  NavigatorState navigator,
  WidgetRef ref,
  String text,
) async {
  // Anything spelled as a Genbeya link is judged as one, with its reason.
  if (text.trim().toLowerCase().startsWith('genbeya:')) {
    return openGenbeyaLink(navigator, ref, text);
  }
  final web = parseWebLink(text);
  if (web == null) {
    ScaffoldMessenger.maybeOf(navigator.context)?.showSnackBar(
      const SnackBar(
        content: Text(
          'Paste a Genbeya link, or a link to a file on GitHub, GitLab or Bitbucket.',
        ),
      ),
    );
    return;
  }
  final manager = await ref.read(repositoriesManagerProvider.future);
  final clones = await manager.clones();
  var clone = clones
      .where((c) => sameRepository(c.url, web.remote))
      .firstOrNull;
  clone ??= await navigator.push<CloneRecord>(
    MaterialPageRoute(
      builder: (_) => AddRepositoryScreen(
        initialUrl: web.remote,
        note: 'To open this link, clone its repository first.',
      ),
    ),
  );
  if (clone == null) return;
  ref.invalidate(clonesProvider);
  final path = web.rest == null
      ? null
      : pathOnBranch(web.rest!, [clone.branch, ?clone.contentBranch]);
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => path == null || path.isEmpty
          ? RepositoryShell(record: clone!)
          : LinkTargetScreen(record: clone!, item: (kind: 'file', value: path)),
    ),
  );
}

/// Opens a Genbeya link (US-2): the item in the clone whose remote names
/// the same repository, or, without one, an offer to clone it, and the item
/// afterwards. A link that isn't one is refused with a reason.
Future<void> openGenbeyaLink(
  NavigatorState navigator,
  WidgetRef ref,
  String text,
) async {
  final messenger = ScaffoldMessenger.maybeOf(navigator.context);
  final link = parseGenbeyaLink(text);
  if (link == null) {
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('That is not a Genbeya link this app opens.'),
      ),
    );
    return;
  }
  final manager = await ref.read(repositoriesManagerProvider.future);
  final clones = await manager.clones();
  var clone = clones
      .where((c) => sameRepository(c.url, link.remote))
      .firstOrNull;
  clone ??= await navigator.push<CloneRecord>(
    MaterialPageRoute(
      builder: (_) => AddRepositoryScreen(
        initialUrl: withoutCredentials(link.remote),
        note:
            'To open ${describeLinkItem(link.item)}, clone its repository first.',
      ),
    ),
  );
  if (clone == null) return;
  ref.invalidate(clonesProvider);
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => LinkTargetScreen(record: clone!, item: link.item),
    ),
  );
}

/// The item a link names, once its clone is read.
class LinkTargetScreen extends ConsumerWidget {
  const LinkTargetScreen({super.key, required this.record, required this.item});

  final CloneRecord record;
  final LinkItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider(record));
    Widget message(String text) => Scaffold(
      appBar: AppBar(title: Text(record.name)),
      body: Padding(padding: const EdgeInsets.all(24), child: Text(text)),
    );
    return session.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(record.name)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => message("Couldn't read ${record.name}: $error"),
      data: (session) {
        final state = session.state!;
        switch (item.kind) {
          case 'task':
            final task = state.tasks
                .where((t) => t.id.toLowerCase() == item.value.toLowerCase())
                .firstOrNull;
            return task == null
                ? message(
                    '${record.name} has no task ${item.value} on this phone. It may be on another branch, or not synced yet.',
                  )
                : TaskViewScreen(session: session, task: task);
          case 'page' || 'file':
            // A link to a file opens it as what it is: a task, a page.
            final task = state.tasks
                .where((t) => t.path == item.value)
                .firstOrNull;
            if (task != null) {
              return TaskViewScreen(session: session, task: task);
            }
            if (wikiPages(state.wiki).contains(item.value)) {
              return WikiScreen(session: session, initialPage: item.value);
            }
            return message(
              item.kind == 'page'
                  ? '${record.name} has no page ${item.value} on this phone.'
                  : '${item.value}: files open in Code, which comes with GM-17.',
            );
          default:
            return message(
              '${describeLinkItem(item)}: files and commits open in Code, which comes with GM-17.',
            );
        }
      },
    );
  }
}
