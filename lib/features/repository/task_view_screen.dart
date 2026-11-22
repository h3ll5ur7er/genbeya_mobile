import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../access/kit/kit_host.dart';
import '../../access/kit/kit_protocol.dart';
import '../../contracts/model.dart';
import '../../managers/repository_session.dart';
import '../kit/kit_view.dart';

/// A task as references open it: its title and properties drawn natively,
/// its description and comments by the kit. The full task screen, with
/// fields and activity, is [[GM-9]].
class TaskViewScreen extends StatefulWidget {
  const TaskViewScreen({super.key, required this.session, required this.task});

  final RepositorySession session;
  final Task task;

  @override
  State<TaskViewScreen> createState() => _TaskViewScreenState();
}

class _TaskViewScreenState extends State<TaskViewScreen> {
  late final KitHost _host;

  @override
  void initState() {
    super.initState();
    _host =
        KitHost(
            files: widget.session.kitFiles(),
            onFollow: (link) {
              if (link case ExternalLink(:final url)) {
                launchUrl(url, mode: LaunchMode.externalApplication);
              } else if (link case FileLink(:final path)) {
                final task = widget.session.state!.tasks
                    .where((t) => t.path == path)
                    .firstOrNull;
                if (task != null) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          TaskViewScreen(session: widget.session, task: task),
                    ),
                  );
                }
              }
            },
          )
          ..updateContext(widget.session.kitContext())
          ..show(KitTaskDocument(widget.task));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _host.setTheme(dark: Theme.of(context).brightness == Brightness.dark);
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(task.id)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Chip(label: Text(task.status)),
                    if (task.type.isNotEmpty) Chip(label: Text(task.type)),
                    if (task.priority != 'none')
                      Chip(label: Text(task.priority)),
                    if (task.assignee.isNotEmpty)
                      Chip(label: Text(task.assignee)),
                    if (task.epic.isNotEmpty) Chip(label: Text(task.epic)),
                    for (final label in task.labels) Chip(label: Text(label)),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: KitView(host: _host)),
        ],
      ),
    );
  }
}
