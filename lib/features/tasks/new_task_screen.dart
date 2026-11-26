import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../access/kit/kit_host.dart';
import '../../contracts/clones.dart';
import '../../contracts/model.dart';
import '../../managers/repository_session.dart';
import '../../managers/task_views.dart';
import '../../managers/task_writer.dart';
import '../kit/editor_toolbar.dart';
import '../kit/kit_view.dart';
import 'task_editing.dart';
import 'task_look.dart';
import 'task_pickers.dart';

/// A new task ([[Experience#tasks]]): a title, its properties, and a
/// description in the kit's editor. Choosing a type fills in its template
/// where nothing was written, as desktop does; another type takes that back.
/// Created with the next free ID; the task created is returned.
class NewTaskScreen extends ConsumerStatefulWidget {
  const NewTaskScreen({
    super.key,
    required this.record,
    required this.session,
    this.status,
    this.epic = '',
    this.text = '',
  });

  final CloneRecord record;
  final RepositorySession session;

  /// The column it was started from; the first workflow state otherwise.
  final String? status;
  final String epic;

  /// Shared text: its first line is the title, the rest the description.
  final String text;

  @override
  ConsumerState<NewTaskScreen> createState() => _NewTaskScreenState();
}

class _NewTaskScreenState extends ConsumerState<NewTaskScreen> {
  late final KitHost _host;
  late final TextEditingController _title;
  late TaskInput _draft;
  var _fromTemplate = FromTemplate.none;
  var _saving = false;

  /// The editor's document: a path no task has, so nothing else claims it.
  late final _path =
      '${widget.session.state!.settings.taskRoot}/.new-task-${DateTime.now().microsecondsSinceEpoch}.md';

  @override
  void initState() {
    super.initState();
    final settings = widget.session.state!.settings;
    final shared = widget.text.trim();
    final firstBreak = shared.indexOf('\n');
    _title = TextEditingController(
      text: firstBreak < 0 ? shared : shared.substring(0, firstBreak).trim(),
    );
    _draft =
        emptyDraft(
          widget.status ?? settings.statuses.first,
          epic: widget.epic,
        ).copyWith(
          body: firstBreak < 0 ? '' : shared.substring(firstBreak + 1).trim(),
        );
    _host = KitHost(
      files: widget.session.kitFiles(),
      onDraft: (_, text) => _draft = _draft.copyWith(body: text),
      onSave: (_, text) => _create(text),
    )..updateContext(widget.session.kitContext());
    _openEditor();
  }

  void _openEditor() => _host.edit(
    KitEdit(area: 'tasks', path: _path, text: _draft.body, hash: 'new'),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _host.setTheme(dark: Theme.of(context).brightness == Brightness.dark);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  /// A new type: what the previous template put in goes, the new one's comes.
  Future<void> _setType(String type) async {
    final tasks = await ref.read(taskWriterProvider(widget.record).future);
    final template = await tasks.template(type);
    if (!mounted) return;
    final before = _draft.body;
    final draft = withoutTemplate(_draft.copyWith(type: type), _fromTemplate);
    final next = template == null
        ? (draft: draft, applied: FromTemplate.none)
        : withTemplate(draft, template);
    setState(() {
      _draft = next.draft;
      _fromTemplate = next.applied;
    });
    if (_draft.body != before) _openEditor();
  }

  Future<void> _create(String body) async {
    if (_saving) return;
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give the task a title first.')),
      );
      return;
    }
    setState(() => _saving = true);
    final created = await changeTask(
      EditScope(context),
      widget.record,
      widget.session,
      (tasks) => tasks.create(_draft.copyWith(title: _title.text, body: body)),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (created != null) Navigator.of(context).pop(created);
  }

  void _command(String command) => command.startsWith('insert:')
      ? _host.command('insert', text: command.substring(7))
      : _host.command(command);

  @override
  Widget build(BuildContext context) {
    final state = widget.session.state!;
    final settings = state.settings;
    final scheme = Theme.of(context).colorScheme;
    final draft = _draft;
    final person = identifyBy(state.people);
    final assignee = state.people
        .where((p) => p.handle == person(draft.assignee))
        .firstOrNull;
    Widget chip(Widget avatar, String label, VoidCallback onTap) =>
        ActionChip(avatar: avatar, label: Text(label), onPressed: onTap);
    return Scaffold(
      appBar: AppBar(
        title: const Text('New task'),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton(
                  onPressed: () => _host.command('save'),
                  child: const Text('Create'),
                ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _title,
                autofocus: _title.text.isEmpty,
                textCapitalization: TextCapitalization.sentences,
                style: Theme.of(context).textTheme.titleLarge,
                decoration: const InputDecoration(
                  hintText: 'Title',
                  border: InputBorder.none,
                ),
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final c in [
                    chip(
                      Icon(
                        Icons.circle,
                        size: 12,
                        color: statusColor(
                          statusTone(
                            settings.statuses.indexOf(draft.status),
                            settings.statuses.length,
                          ),
                          scheme,
                        ),
                      ),
                      titleCase(draft.status),
                      () async {
                        final status = await pickStatus(
                          context,
                          settings,
                          draft.status,
                        );
                        if (status != null) {
                          setState(
                            () => _draft = _draft.copyWith(status: status),
                          );
                        }
                      },
                    ),
                    chip(
                      (draft.type ?? '').isEmpty
                          ? const Icon(Icons.category_outlined, size: 16)
                          : TypeIcon(type: draft.type!, types: settings.types),
                      (draft.type ?? '').isEmpty
                          ? 'Type'
                          : titleCase(draft.type!),
                      () async {
                        final type = await pickType(
                          context,
                          state,
                          draft.type ?? '',
                        );
                        if (type != null) await _setType(type);
                      },
                    ),
                    chip(
                      PriorityIcon(priority: draft.priority),
                      draft.priority == 'none'
                          ? 'Priority'
                          : titleCase(draft.priority),
                      () async {
                        final priority = await pickPriority(
                          context,
                          draft.priority,
                        );
                        if (priority != null) {
                          setState(
                            () => _draft = _draft.copyWith(priority: priority),
                          );
                        }
                      },
                    ),
                    chip(
                      draft.assignee.isEmpty
                          ? const Icon(Icons.person_outline, size: 16)
                          : PersonAvatar(
                              name: assignee?.name ?? draft.assignee,
                            ),
                      draft.assignee.isEmpty
                          ? 'Unassigned'
                          : assignee?.name ?? draft.assignee,
                      () async {
                        final chosen = await pickAssignee(
                          context,
                          state,
                          draft.assignee,
                        );
                        if (chosen != null) {
                          setState(
                            () => _draft = _draft.copyWith(assignee: chosen),
                          );
                        }
                      },
                    ),
                    chip(
                      const Icon(Icons.folder_outlined, size: 16),
                      epicName(draft.epic),
                      () async {
                        final epic = await pickEpic(
                          context,
                          state.tasks,
                          draft.epic,
                        );
                        if (epic != null) {
                          setState(() => _draft = _draft.copyWith(epic: epic));
                        }
                      },
                    ),
                    chip(
                      const Icon(Icons.label_outline, size: 16),
                      draft.labels.isEmpty ? 'Labels' : draft.labels.join(', '),
                      () async {
                        final labels = await pickLabels(
                          context,
                          state.tasks,
                          draft.labels,
                        );
                        if (labels != null) {
                          setState(
                            () => _draft = _draft.copyWith(labels: labels),
                          );
                        }
                      },
                    ),
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: c,
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: KitView(host: _host)),
            EditorToolbar(onCommand: _command),
          ],
        ),
      ),
    );
  }
}
