import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../access/kit/kit_protocol.dart';
import '../../contracts/model.dart';
import '../../managers/repository_model.dart';
import '../../managers/repository_session.dart';
import 'task_view_screen.dart';
import 'wiki_screen.dart';

/// Every page path of a wiki tree.
List<String> wikiPages(List<WikiNode> nodes) => [
  for (final node in nodes) ...[?node.path, ...wikiPages(node.children)],
];

/// Where a link to a repository file leads.
enum FileTarget { task, page, file }

FileTarget fileTarget(RepositoryState state, String path) =>
    state.tasks.any((t) => t.path == path)
    ? FileTarget.task
    : wikiPages(state.wiki).contains(path)
    ? FileTarget.page
    : FileTarget.file;

/// Follows a link the kit reports, from any screen that shows rendered
/// Markdown: tasks open their screen, pages [openPage] (the wiki in place)
/// or a page screen of their own, web links the browser.
void followLink(
  BuildContext context,
  RepositorySession session,
  FollowedLink link, {
  void Function(String path, String? anchor)? openPage,
}) {
  void say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  final state = session.state!;
  switch (link) {
    case ExternalLink(:final url):
      launchUrl(url, mode: LaunchMode.externalApplication);
    case MissingPage(:final title):
      say(
        '"$title" has no page yet. Creating pages comes with editing (GM-16).',
      );
    case PersonLink(:final handle):
      final person = state.people
          .where((p) => p.handle.toLowerCase() == handle.toLowerCase())
          .firstOrNull;
      say(person == null ? '@$handle' : '${person.name} (@${person.handle})');
    case FileLink(:final path, :final anchor):
      switch (fileTarget(state, path)) {
        case FileTarget.task:
          final task = state.tasks.firstWhere((t) => t.path == path);
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TaskViewScreen(session: session, task: task),
            ),
          );
        case FileTarget.page when openPage != null:
          openPage(path, anchor);
        case FileTarget.page:
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => WikiScreen(
                session: session,
                initialPage: path,
                initialAnchor: anchor,
              ),
            ),
          );
        case FileTarget.file:
          say('$path: files open in Code, which comes with GM-17.');
      }
  }
}
