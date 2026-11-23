import 'package:material_ui/material_ui.dart';

import '../../contracts/model.dart';
import '../../engines/collation.dart';
import '../../engines/time_log.dart';
import '../../managers/repository_model.dart';
import '../../managers/task_views.dart';
import 'task_look.dart';

/// The bottom sheets a task's properties are changed with, as desktop's
/// property menus offer them (task-properties.ts): each returns the change,
/// or null when the sheet was closed.

/// One of [options] (value, label, leading); `(value,)` so that "" and a
/// closed sheet differ.
Future<(String,)?> pickOne(
  BuildContext context, {
  required String title,
  required List<(String value, String label, Widget? leading)> options,
  required String current,
}) => showModalBottomSheet<(String,)>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final (value, label, leading) in options)
            ListTile(
              leading: leading,
              title: Text(label),
              selected: value == current,
              trailing: value == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, (value,)),
            ),
        ],
      ),
    ),
  ),
);

Future<String?> pickStatus(
  BuildContext context,
  Settings settings,
  String current,
) async {
  final scheme = Theme.of(context).colorScheme;
  final picked = await pickOne(
    context,
    title: 'Status',
    current: current,
    options: [
      for (final (index, status) in settings.statuses.indexed)
        (
          status,
          titleCase(status),
          Icon(
            Icons.circle,
            size: 14,
            color: statusColor(
              statusTone(index, settings.statuses.length),
              scheme,
            ),
          ),
        ),
    ],
  );
  return picked?.$1;
}

Future<String?> pickType(
  BuildContext context,
  RepositoryState state,
  String current,
) async {
  final types = typesOf(state.settings.types, [
    ...state.tasks,
  ]).where((t) => t.name.isNotEmpty).toList();
  if (current.isNotEmpty && !types.any((t) => t.name == current)) {
    types.add(TaskType.named(current));
  }
  final picked = await pickOne(
    context,
    title: 'Type',
    current: current,
    options: [
      ('', 'No type', const Icon(Icons.remove)),
      for (final type in types)
        (
          type.name,
          titleCase(type.name),
          TypeIcon(type: type.name, types: state.settings.types),
        ),
    ],
  );
  return picked?.$1;
}

Future<String?> pickPriority(BuildContext context, String current) async {
  final picked = await pickOne(
    context,
    title: 'Priority',
    current: current,
    options: [
      for (final priority in priorities)
        (
          priority,
          priority == 'none' ? 'No priority' : titleCase(priority),
          PriorityIcon(priority: priority),
        ),
      if (!priorities.contains(current))
        (current, titleCase(current), PriorityIcon(priority: current)),
    ],
  );
  return picked?.$1;
}

/// Someone to assign: the repository's people by handle, then assignees who
/// are none of them; "" unassigns. A search field narrows the list, and
/// what it holds can be assigned as typed.
Future<String?> pickAssignee(
  BuildContext context,
  RepositoryState state,
  String current,
) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => _AssigneeSheet(state: state, current: current),
);

class _AssigneeSheet extends StatefulWidget {
  const _AssigneeSheet({required this.state, required this.current});

  final RepositoryState state;
  final String current;

  @override
  State<_AssigneeSheet> createState() => _AssigneeSheetState();
}

class _AssigneeSheetState extends State<_AssigneeSheet> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final identify = identifyBy(state.people);
    final assigned = identify(widget.current);
    final known = {for (final p in state.people) p.handle};
    final people = [
      for (final p in state.people)
        (value: p.handle, name: p.name, handle: p.handle),
      for (final assignee in peopleOf(state.tasks, identify: identify))
        if (!known.contains(assignee))
          (value: assignee, name: assignee, handle: null),
    ];
    final query = _query.trim().toLowerCase();
    final shown = [
      for (final p in people)
        if (query.isEmpty ||
            p.name.toLowerCase().contains(query) ||
            (p.handle?.toLowerCase().contains(query) ?? false))
          p,
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'A handle, a name or an email',
                  ),
                  onChanged: (text) => setState(() => _query = text),
                  onSubmitted: (text) {
                    if (text.trim().isNotEmpty) {
                      Navigator.pop(context, text.trim());
                    }
                  },
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (query.isEmpty)
                      ListTile(
                        leading: const Icon(Icons.person_off_outlined),
                        title: const Text('Unassigned'),
                        selected: widget.current.isEmpty,
                        onTap: () => Navigator.pop(context, ''),
                      ),
                    for (final p in shown)
                      ListTile(
                        leading: PersonAvatar(name: p.name, size: 28),
                        title: Text(p.name),
                        subtitle: p.handle == null
                            ? null
                            : Text('@${p.handle}'),
                        selected: p.value == assigned,
                        trailing: p.value == assigned
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.pop(context, p.value),
                      ),
                    if (query.isNotEmpty)
                      ListTile(
                        leading: const Icon(Icons.person_add_alt),
                        title: Text('Assign "${_query.trim()}"'),
                        onTap: () => Navigator.pop(context, _query.trim()),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An epic: the epics of other tasks and [current], "" for none, or a new
/// one ("/" nests them).
Future<String?> pickEpic(
  BuildContext context,
  List<Task> tasks,
  String current,
) async {
  final epics = stableSorted({
    ...epicsOf(tasks),
    if (current.isNotEmpty) current,
  }, compareEpics);
  const newEpic = '\u0000new';
  final picked = await pickOne(
    context,
    title: 'Epic',
    current: current,
    options: [
      ('', 'No epic', const Icon(Icons.folder_off_outlined)),
      for (final epic in epics) (epic, epic, const Icon(Icons.folder_outlined)),
      (newEpic, 'New epic…', const Icon(Icons.create_new_folder_outlined)),
    ],
  );
  if (picked == null || !context.mounted) return null;
  if (picked.$1 != newEpic) return picked.$1;
  return askText(
    context,
    title: 'New epic',
    label: 'Epic name',
    hint: 'A folder below the tasks; "/" nests it, as in Auth/Tokens.',
    confirm: 'Move',
  );
}

/// Labels: each of the repository's labels toggled, and new ones added.
Future<List<String>?> pickLabels(
  BuildContext context,
  List<Task> tasks,
  List<String> current,
) => showModalBottomSheet<List<String>>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => _LabelSheet(
    known: ({...labelsOf(tasks), ...current}.toList()..sort()),
    current: current,
  ),
);

class _LabelSheet extends StatefulWidget {
  const _LabelSheet({required this.known, required this.current});

  final List<String> known;
  final List<String> current;

  @override
  State<_LabelSheet> createState() => _LabelSheetState();
}

class _LabelSheetState extends State<_LabelSheet> {
  late final _chosen = [...widget.current];
  late final _known = [...widget.known];
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _add() {
    final label = _text.text.trim();
    if (label.isEmpty) return;
    setState(() {
      if (!_known.contains(label)) _known.add(label);
      if (!_chosen.contains(label)) _chosen.add(label);
      _text.clear();
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Labels', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final label in _known)
                      FilterChip(
                        label: Text(label),
                        selected: _chosen.contains(label),
                        onSelected: (on) => setState(
                          () => on ? _chosen.add(label) : _chosen.remove(label),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            TextField(
              controller: _text,
              decoration: InputDecoration(
                hintText: 'New label',
                suffixIcon: IconButton(
                  tooltip: 'Add',
                  icon: const Icon(Icons.add),
                  onPressed: _add,
                ),
              ),
              onSubmitted: (_) => _add(),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _chosen),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A line of text in a dialog; null when cancelled.
Future<String?> askText(
  BuildContext context, {
  required String title,
  String label = '',
  String initial = '',
  String? hint,
  String confirm = 'Save',
  TextInputType? keyboard,
}) => showDialog<String>(
  context: context,
  builder: (context) {
    final text = TextEditingController(text: initial);
    return AlertDialog(
      title: Text(title),
      content: TextField(
        controller: text,
        autofocus: true,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label.isEmpty ? null : label,
          helperText: hint,
          helperMaxLines: 3,
        ),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, text.text),
          child: Text(confirm),
        ),
      ],
    );
  },
);

/// A custom field's new value as desktop's field editors make it
/// (task-fields.ts): a choice, a number, a whole date, effort that reads as
/// hours or days, task IDs as a list; "" clears it. Null when cancelled.
Future<(FieldValue,)?> editField(
  BuildContext context,
  FieldDefinition field,
  FieldValue? current,
) async {
  final text = switch (current) {
    null => '',
    final List<String> list => list.join(', '),
    final value => jsText(value),
  };
  switch (field.type) {
    case 'choice':
      final options = [...?field.options];
      if (text.isNotEmpty && !options.contains(text)) options.add(text);
      final picked = await pickOne(
        context,
        title: titleCase(field.name),
        current: text,
        options: [('', '—', null), for (final o in options) (o, o, null)],
      );
      return picked == null ? null : (picked.$1,);
    case 'date':
      final initial = DateTime.tryParse(text);
      final picked = await showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: DateTime(1000),
        lastDate: DateTime(9999, 12, 31),
        helpText: titleCase(field.name),
        cancelText: text.isEmpty ? 'Cancel' : 'Clear',
      );
      if (picked == null) return text.isEmpty ? null : ('',);
      return (dateText(picked),);
    default:
      final typed = await askText(
        context,
        title: titleCase(field.name),
        initial: text,
        hint: switch (field.type) {
          'effort' => 'Hours or days of work, such as 16h or 2d.',
          'tasks' => 'Task IDs, separated by commas.',
          _ => null,
        },
        keyboard: field.type == 'number'
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : null,
      );
      if (typed == null) return null;
      final value = typed.trim();
      switch (field.type) {
        case 'number':
          if (value.isEmpty) return ('',);
          final number = num.tryParse(value);
          return number == null || !number.isFinite ? null : (number,);
        case 'effort':
          if (value.isNotEmpty && parseEffort(value) == null) return null;
          return (value,);
        case 'tasks':
          final ids = {
            for (final id in value.split(RegExp(r'[\s,]+')))
              if (id.trim().isNotEmpty) id.trim().toUpperCase(),
          }.toList();
          return ids.isEmpty ? ('',) : (ids,);
        default:
          return (typed,);
      }
  }
}

/// A value as JavaScript's `String()` writes it.
String jsText(Object value) => switch (value) {
  final double d when d == d.truncateToDouble() && d.abs() < 1e21 =>
    d.toInt().toString(),
  _ => '$value',
};

/// `YYYY-MM-DD`.
String dateText(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
