import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../access/kit/kit_host.dart';
import '../../access/kit/kit_protocol.dart';
import '../../contracts/model.dart';
import '../../managers/repository_session.dart';
import '../../managers/task_views.dart';
import '../kit/kit_view.dart';
import '../repositories/format.dart';
import '../tasks/task_look.dart';

/// A task, full screen ([[Experience#tasks]]): its title and properties as
/// chips, its custom fields, its description and comments rendered by the
/// kit, and its activity from Git history. Changing them comes with
/// [[GM-12]] and [[GM-13]].
class TaskViewScreen extends StatefulWidget {
  const TaskViewScreen({super.key, required this.session, required this.task});

  final RepositorySession session;
  final Task task;

  @override
  State<TaskViewScreen> createState() => _TaskViewScreenState();
}

class _TaskViewScreenState extends State<TaskViewScreen> {
  late final KitHost _host;
  late final Future<TaskActivity> _activity;
  double _height = 120;

  @override
  void initState() {
    super.initState();
    _activity = widget.session.taskActivity(widget.task);
    _host =
        KitHost(
            files: widget.session.kitFiles(),
            onHeight: (height) {
              if (mounted) setState(() => _height = height.clamp(60, 50000));
            },
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
    final state = widget.session.state!;
    final settings = state.settings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final person = identifyBy(state.people);
    final assignee = state.people
        .where((p) => p.handle == person(task.assignee))
        .firstOrNull;
    final statusIndex = settings.statuses.indexOf(task.status);
    final dates = {
      for (final d in dueDatesOf(task, settings, today())) d.field: d,
    };
    return Scaffold(
      appBar: AppBar(title: Text(displayId(task.id))),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(task.title, style: theme.textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                  avatar: Icon(
                    Icons.circle,
                    size: 12,
                    color: statusColor(
                      statusTone(statusIndex, settings.statuses.length),
                      scheme,
                    ),
                  ),
                  label: Text(titleCase(task.status)),
                ),
                if (task.type.isNotEmpty)
                  Chip(
                    avatar: TypeIcon(type: task.type, types: settings.types),
                    label: Text(titleCase(task.type)),
                  ),
                if (task.priority != 'none')
                  Chip(
                    avatar: PriorityIcon(priority: task.priority),
                    label: Text(titleCase(task.priority)),
                  ),
                if (task.assignee.isNotEmpty)
                  Chip(
                    avatar: PersonAvatar(name: assignee?.name ?? task.assignee),
                    label: Text(assignee?.name ?? task.assignee),
                  ),
                if (task.epic.isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.folder_outlined, size: 16),
                    label: Text(task.epic),
                  ),
                for (final label in task.labels) Chip(label: LabelChip(label)),
              ],
            ),
          ),
          for (final field in settings.fields)
            if (task.fields[field.name] != null)
              ListTile(
                dense: true,
                title: Text(field.name),
                trailing: Text(
                  switch (task.fields[field.name]) {
                    final List<Object?> list => list.join(', '),
                    final value => '$value',
                  },
                  style: TextStyle(
                    color: switch (dates[field.name]?.tone) {
                      DueTone.overdue => toneColor('red', scheme),
                      DueTone.soon => toneColor('yellow', scheme),
                      null => null,
                    },
                  ),
                ),
              ),
          const Divider(height: 1),
          SizedBox(
            height: _height,
            child: KitView(host: _host),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Activity', style: theme.textTheme.titleMedium),
          ),
          FutureBuilder<TaskActivity>(
            future: _activity,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text("Couldn't read the history: ${snapshot.error}"),
                );
              }
              final activity = snapshot.data;
              if (activity == null) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in activity.entries)
                    ListTile(
                      dense: true,
                      leading: PersonAvatar(name: entry.author, size: 28),
                      title: Text(
                        entry.changes.isEmpty
                            ? entry.subject
                            : entry.changes.map(describeChange).join('; '),
                      ),
                      subtitle: Text(
                        '${entry.author} · ${formatAgo(entry.date)}',
                      ),
                    ),
                  if (activity.truncated)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Older history isn\'t on this phone: the clone is shallow.',
                      ),
                    ),
                  if (activity.entries.isEmpty && !activity.truncated)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No commits changed this task yet.'),
                    ),
                  const SizedBox(height: 24),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
