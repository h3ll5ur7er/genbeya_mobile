import 'package:material_ui/material_ui.dart';

import '../../contracts/model.dart';
import '../../managers/task_views.dart';
import 'task_look.dart';

/// A task as desktop cards show it: type, ID, assignee, title, epic,
/// priority, labels and date fields (overdue in red, soon in yellow).
class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.settings,
    required this.assigneeName,
    required this.onTap,
    this.showEpic = true,
  });

  final Task task;
  final Settings settings;
  final String assigneeName;
  final VoidCallback onTap;
  final bool showEpic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dates = dueDatesOf(task, settings, today());
    final hasMeta =
        task.priority != 'none' ||
        task.labels.isNotEmpty ||
        (showEpic && task.epic.isNotEmpty) ||
        dates.isNotEmpty;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (task.type.isNotEmpty) ...[
                    TypeIcon(type: task.type, types: settings.types),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    displayId(task.id),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (task.assignee.isNotEmpty)
                    PersonAvatar(name: assigneeName),
                ],
              ),
              const SizedBox(height: 4),
              Text(task.title, style: theme.textTheme.bodyMedium),
              if (hasMeta) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (showEpic && task.epic.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.folder_outlined,
                            size: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 2),
                          Text(task.epic, style: theme.textTheme.labelSmall),
                        ],
                      ),
                    if (task.priority != 'none')
                      PriorityIcon(priority: task.priority),
                    for (final label in task.labels) LabelChip(label),
                    for (final date in dates)
                      Text(
                        date.date,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: switch (date.tone) {
                            DueTone.overdue => toneColor('red', scheme),
                            DueTone.soon => toneColor('yellow', scheme),
                            null => scheme.onSurfaceVariant,
                          },
                          fontWeight: date.tone == DueTone.overdue
                              ? FontWeight.w600
                              : null,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
