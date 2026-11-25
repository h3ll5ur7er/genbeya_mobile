import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../access/kit/kit_host.dart';
import '../../contracts/clones.dart';
import '../../contracts/model.dart';
import '../../managers/repository_session.dart';
import '../../managers/task_views.dart';
import '../../engines/js.dart';
import '../../managers/task_writer.dart';
import '../kit/kit_view.dart';
import '../../engines/task_engine.dart';
import '../tasks/comment_composer.dart';
import '../tasks/task_edit_screen.dart';
import '../tasks/task_editing.dart';
import '../tasks/task_pickers.dart';
import 'links.dart';
import 'share_menu.dart';
import '../repositories/format.dart';
import '../tasks/task_look.dart';

/// A task, full screen ([[Experience#tasks]]): its title and properties as
/// chips, its custom fields, its description and comments rendered by the
/// kit, and its activity from Git history. With the session's clone, each
/// property changes from a bottom sheet and is saved at once, checkboxes
/// tick, and **Edit** opens the title and description ([[GM-12]]).
class TaskViewScreen extends ConsumerStatefulWidget {
  const TaskViewScreen({super.key, required this.session, required this.task});

  final RepositorySession session;
  final Task task;

  @override
  ConsumerState<TaskViewScreen> createState() => _TaskViewScreenState();
}

class _TaskViewScreenState extends ConsumerState<TaskViewScreen> {
  late final KitHost _host;
  late Future<TaskActivity> _activity;
  late Task _task = widget.task;
  double _height = 120;
  StreamSubscription<Object>? _changes;

  /// Changes run one after the other, each on the newest version.
  Future<void> _queue = Future.value();
  var _saving = 0;

  /// The clone to change the task in; read-only without one.
  CloneRecord? get _record => widget.session.record;

  bool get _editable => _record != null;

  /// The name the user's comments are signed with, as desktop compares it.
  String get _me => TaskEngine().commentAuthor(widget.session.author ?? '');

  final _composer = GlobalKey<CommentComposerState>();

  /// The comment of the user's being edited in the composer.
  int? _editingComment;

  @override
  void initState() {
    super.initState();
    _activity = widget.session.taskActivity(_task);
    _host =
        KitHost(
            files: widget.session.kitFiles(),
            onHeight: (height) {
              if (mounted) setState(() => _height = height.clamp(60, 50000));
            },
            onFollow: (link) => followLink(context, widget.session, link),
            onToggle: (document, offset) async {
              if (!_editable) return;
              _change((tasks, task) async {
                final ticked = await tasks.toggle(task, offset);
                if (ticked == null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('That checkbox moved. Try again.'),
                    ),
                  );
                }
                return ticked;
              });
            },
          )
          ..updateContext(widget.session.kitContext())
          ..show(KitTaskDocument(_task));
    // After a sync or another screen's edit: the newest version of this task.
    _changes = widget.session.changes.listen((state) {
      _host.updateContext(widget.session.kitContext());
      final newer = state.tasks.where((t) => t.id == _task.id).firstOrNull;
      if (newer != null && newer.hash != _task.hash) _show(newer);
    });
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

  void _show(Task task) {
    if (!mounted) return;
    setState(() {
      _task = task;
      _activity = widget.session.taskActivity(task);
    });
    _host.show(KitTaskDocument(task));
  }

  /// Saves a change made from the task as it is when its turn comes.
  Future<void> _change(
    Future<Task?> Function(TaskWriter tasks, Task task) change,
  ) {
    setState(() => _saving++);
    return _queue = _queue
        .then((_) async {
          if (!mounted) return;
          final saved = await changeTask(
            context,
            ref,
            _record!,
            widget.session,
            (tasks) => change(tasks, _task),
          );
          if (saved != null) _show(saved);
        })
        .whenComplete(() {
          if (mounted) setState(() => _saving--);
        });
  }

  /// A property change: the whole task with [patch] applied, as desktop sends it.
  void _patch(TaskInput Function(TaskInput input) patch) =>
      _change((tasks, task) => tasks.update(task, patch(task.toInput())));

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<Task>(
      MaterialPageRoute(
        builder: (_) => TaskEditScreen(
          record: _record!,
          session: widget.session,
          task: _task,
        ),
      ),
    );
    if (saved != null) _show(saved);
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
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
    final editable = _editable;

    /// A property as a chip: tapping it changes it, when the task can change.
    Widget property({
      required Widget avatar,
      required String label,
      required String tooltip,
      Future<void> Function()? onTap,
      bool empty = false,
    }) => Tooltip(
      message: tooltip,
      child: ActionChip(
        avatar: avatar,
        label: Text(
          label,
          style: empty ? TextStyle(color: scheme.onSurfaceVariant) : null,
        ),
        onPressed: editable && onTap != null ? onTap : null,
      ),
    );

    final configured = {for (final f in settings.fields) f.name};
    return Scaffold(
      appBar: AppBar(
        title: Text(displayId(task.id)),
        bottom: _saving > 0
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
        actions: [
          if (editable)
            IconButton(
              tooltip: 'Edit title and description',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit,
            ),
          ShareMenu(
            session: widget.session,
            item: (kind: 'task', value: task.id),
            path: task.path,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: GestureDetector(
                    onLongPress: editable ? _edit : null,
                    child: Text(task.title, style: theme.textTheme.titleLarge),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      property(
                        tooltip: 'Status',
                        avatar: Icon(
                          Icons.circle,
                          size: 12,
                          color: statusColor(
                            statusTone(statusIndex, settings.statuses.length),
                            scheme,
                          ),
                        ),
                        label: titleCase(task.status),
                        onTap: () async {
                          final status = await pickStatus(
                            context,
                            settings,
                            task.status,
                          );
                          if (status != null && status != task.status) {
                            _patch((i) => i.copyWith(status: status));
                          }
                        },
                      ),
                      if (task.type.isNotEmpty || editable)
                        property(
                          tooltip: 'Type',
                          avatar: task.type.isEmpty
                              ? const Icon(Icons.category_outlined, size: 16)
                              : TypeIcon(
                                  type: task.type,
                                  types: settings.types,
                                ),
                          label: task.type.isEmpty
                              ? 'Type'
                              : titleCase(task.type),
                          empty: task.type.isEmpty,
                          onTap: () async {
                            final type = await pickType(
                              context,
                              state,
                              task.type,
                            );
                            if (type != null && type != task.type) {
                              _patch((i) => i.copyWith(type: type));
                            }
                          },
                        ),
                      if (task.priority != 'none' || editable)
                        property(
                          tooltip: 'Priority',
                          avatar: PriorityIcon(priority: task.priority),
                          label: task.priority == 'none'
                              ? 'Priority'
                              : titleCase(task.priority),
                          empty: task.priority == 'none',
                          onTap: () async {
                            final priority = await pickPriority(
                              context,
                              task.priority,
                            );
                            if (priority != null && priority != task.priority) {
                              _patch((i) => i.copyWith(priority: priority));
                            }
                          },
                        ),
                      if (task.assignee.isNotEmpty || editable)
                        property(
                          tooltip: 'Assignee',
                          avatar: task.assignee.isEmpty
                              ? const Icon(Icons.person_outline, size: 16)
                              : PersonAvatar(
                                  name: assignee?.name ?? task.assignee,
                                ),
                          label: task.assignee.isEmpty
                              ? 'Unassigned'
                              : assignee?.name ?? task.assignee,
                          empty: task.assignee.isEmpty,
                          onTap: () async {
                            final chosen = await pickAssignee(
                              context,
                              state,
                              task.assignee,
                            );
                            if (chosen != null &&
                                person(chosen) != person(task.assignee)) {
                              _patch((i) => i.copyWith(assignee: chosen));
                            }
                          },
                        ),
                      if (task.epic.isNotEmpty || editable)
                        property(
                          tooltip: 'Epic',
                          avatar: const Icon(Icons.folder_outlined, size: 16),
                          label: epicName(task.epic),
                          empty: task.epic.isEmpty,
                          onTap: () async {
                            final epic = await pickEpic(
                              context,
                              state.tasks,
                              task.epic,
                            );
                            if (epic != null && epic != task.epic) {
                              _patch((i) => i.copyWith(epic: epic));
                            }
                          },
                        ),
                      for (final label in task.labels)
                        editable
                            ? ActionChip(
                                label: LabelChip(label),
                                onPressed: _labels,
                              )
                            : Chip(label: LabelChip(label)),
                      if (editable)
                        ActionChip(
                          avatar: const Icon(Icons.label_outline, size: 16),
                          label: Text(
                            task.labels.isEmpty ? 'Labels' : 'Labels…',
                          ),
                          onPressed: _labels,
                        ),
                    ],
                  ),
                ),
                for (final field in settings.fields)
                  if (task.fields[field.name] != null || editable)
                    ListTile(
                      dense: true,
                      title: Text(titleCase(field.name)),
                      onTap: editable
                          ? () async {
                              final value = await editField(
                                context,
                                field,
                                task.fields[field.name],
                              );
                              if (value == null ||
                                  _same(
                                    value.$1,
                                    task.fields[field.name] ?? '',
                                  )) {
                                return;
                              }
                              _change(
                                (tasks, current) => tasks.update(
                                  current,
                                  current.toInput().copyWith(
                                    fields: {
                                      ...current.fields,
                                      field.name: value.$1,
                                    },
                                  ),
                                ),
                              );
                            }
                          : null,
                      trailing: Text(
                        switch (task.fields[field.name]) {
                          null => '—',
                          final List<Object?> list => list.join(', '),
                          final value => jsText(value),
                        },
                        style: TextStyle(
                          color: switch (dates[field.name]?.tone) {
                            DueTone.overdue => toneColor('red', scheme),
                            DueTone.soon => toneColor('yellow', scheme),
                            null =>
                              task.fields[field.name] == null
                                  ? scheme.onSurfaceVariant
                                  : null,
                          },
                        ),
                      ),
                    ),
                // Fields the settings don't configure: shown, edited on desktop.
                for (final entry in task.fields.entries)
                  if (!configured.contains(entry.key))
                    ListTile(
                      dense: true,
                      title: Text(entry.key),
                      trailing: Text(switch (entry.value) {
                        final List<Object?> list => list.join(', '),
                        final value => jsText(value),
                      }),
                    ),
                const Divider(height: 1),
                SizedBox(
                  height: _height,
                  child: KitView(host: _host),
                ),
                // The kit shows every comment; one's own are changed from here.
                for (final (index, comment) in task.comments.indexed)
                  if (editable && comment.author == _me)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.chat_bubble_outline, size: 20),
                      title: Text(
                        comment.body.split('\n').first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        'Your comment · ${comment.date.replaceFirst('T', ' ')}',
                      ),
                      selected: _editingComment == index,
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Edit or delete',
                        onSelected: (action) => action == 'edit'
                            ? setState(() => _editingComment = index)
                            : _deleteComment(index),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
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
                        child: Text(
                          "Couldn't read the history: ${snapshot.error}",
                        ),
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
                                  : entry.changes
                                        .map(describeChange)
                                        .join('; '),
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
          ),
          if (editable)
            CommentComposer(
              key: _composer,
              state: state,
              editing:
                  _editingComment == null ||
                      _editingComment! >= task.comments.length
                  ? null
                  : task.comments[_editingComment!].body,
              onCancelEdit: () => setState(() => _editingComment = null),
              onSend: _sendComment,
            ),
        ],
      ),
    );
  }

  /// Writes the composer's text: a new comment, or the one being edited.
  Future<bool> _sendComment(String text) async {
    final editing = _editingComment;
    var sent = false;
    await _change((tasks, task) async {
      final saved = editing == null
          ? await tasks.addComment(task, text)
          : await tasks.editComment(task, editing, text);
      sent = true;
      if (mounted) setState(() => _editingComment = null);
      return saved;
    });
    return sent;
  }

  Future<void> _deleteComment(int index) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your comment?'),
        content: const Text(
          'It is removed from the task with a commit, which history keeps.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    _change((tasks, task) => tasks.deleteComment(task, index));
  }

  Future<void> _labels() async {
    final labels = await pickLabels(
      context,
      widget.session.state!.tasks,
      _task.labels,
    );
    if (labels == null || _same(labels, _task.labels)) return;
    _patch((i) => i.copyWith(labels: labels));
  }

  static bool _same(Object? a, Object? b) => jsJson(a) == jsJson(b);
}
