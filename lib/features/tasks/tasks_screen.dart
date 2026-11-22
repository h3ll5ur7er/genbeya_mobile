import 'package:material_ui/material_ui.dart';

import '../../contracts/model.dart';
import '../../managers/repository_model.dart';
import '../../managers/repository_session.dart';
import '../../managers/task_views.dart';
import '../repository/task_view_screen.dart';
import 'task_card.dart';
import 'task_look.dart';

/// The tasks as phones show them best: the list grouped by state (the
/// default), or the board one column per screen with a strip of states;
/// on tablets the whole board. Filters as desktop's **Filter by**
/// ([[Experience#tasks]]).
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, required this.session});

  final RepositorySession session;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  var _filters = const TaskFilters();
  var _board = false;
  var _searching = false;
  final _collapsed = <String>{};
  final _pages = PageController();
  var _column = 0;

  RepositoryState get _state => widget.session.state!;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _open(Task task) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TaskViewScreen(session: widget.session, task: task),
    ),
  );

  String _nameOf(
    String assignee,
    Map<String, Person> byHandle,
    Identify identify,
  ) => byHandle[identify(assignee)]?.name ?? assignee;

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final settings = state.settings;
    final identify = identifyBy(state.people);
    final byHandle = {for (final p in state.people) p.handle: p};
    final shown = visibleTasks(state.tasks, _filters, identify: identify);
    final allColumns = columnsOf(settings.statuses, state.tasks);
    final columns = _board
        ? [
            for (final c in allColumns)
              if (!settings.hiddenColumns.contains(c)) c,
          ]
        : allColumns;
    Widget card(Task task, {bool showEpic = true}) => TaskCard(
      task: task,
      settings: settings,
      assigneeName: _nameOf(task.assignee, byHandle, identify),
      onTap: () => _open(task),
      showEpic: showEpic,
    );

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'ID, title, assignee or label',
                  border: InputBorder.none,
                ),
                onChanged: (text) =>
                    setState(() => _filters = _filters.copyWith(query: text)),
              )
            : const Text('Tasks'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Stop searching' : 'Search tasks',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _filters = _filters.copyWith(query: '');
            }),
          ),
          IconButton(
            tooltip: _board ? 'List' : 'Board',
            icon: Icon(
              _board ? Icons.view_list_outlined : Icons.view_kanban_outlined,
            ),
            onPressed: () => setState(() => _board = !_board),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _FilterBar(
            state: state,
            filters: _filters,
            identify: identify,
            byHandle: byHandle,
            onChanged: (filters) => setState(() => _filters = filters),
          ),
        ),
      ),
      body: state.tasks.isEmpty
          ? Center(child: Text('No tasks in ${settings.taskRoot}/ yet.'))
          : _board
          ? _boardView(context, columns, shown, settings, card)
          : _listView(context, columns, shown, settings, card),
    );
  }

  Widget _listView(
    BuildContext context,
    List<String> columns,
    List<Task> shown,
    Settings settings,
    Widget Function(Task, {bool showEpic}) card,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final (index, column) in columns.indexed) ...[
          ListTile(
            dense: true,
            leading: Icon(
              Icons.circle,
              size: 12,
              color: statusColor(
                statusTone(
                  settings.statuses.indexOf(column),
                  settings.statuses.length,
                ),
                scheme,
              ),
            ),
            title: Text(
              '${titleCase(column)} · ${shown.where((t) => t.status == column).length}',
            ),
            trailing: Icon(
              _collapsed.contains(column)
                  ? Icons.expand_more
                  : Icons.expand_less,
            ),
            onTap: () => setState(
              () => _collapsed.contains(column)
                  ? _collapsed.remove(column)
                  : _collapsed.add(column),
            ),
            key: ValueKey('status-$index'),
          ),
          if (!_collapsed.contains(column))
            for (final task in shown.where((t) => t.status == column))
              card(task),
        ],
      ],
    );
  }

  Widget _boardView(
    BuildContext context,
    List<String> columns,
    List<Task> shown,
    Settings settings,
    Widget Function(Task, {bool showEpic}) card,
  ) {
    final scheme = Theme.of(context).colorScheme;
    Widget columnOf(String status) {
      final tasks = shown.where((t) => t.status == status).toList();
      return tasks.isEmpty
          ? Center(
              child: Text(
                'Nothing ${titleCase(status).toLowerCase()}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [for (final task in tasks) card(task)],
            );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 840) {
          // Tablets: the whole board, columns side by side.
          return ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final status in columns)
                SizedBox(
                  width: 300,
                  child: Column(
                    children: [
                      ListTile(
                        dense: true,
                        title: Text(
                          '${titleCase(status)} · ${shown.where((t) => t.status == status).length}',
                        ),
                      ),
                      Expanded(child: columnOf(status)),
                    ],
                  ),
                ),
            ],
          );
        }
        final current = _column.clamp(0, columns.length - 1);
        return Column(
          children: [
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final (index, status) in columns.indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: ChoiceChip(
                        label: Text(
                          '${titleCase(status)} ${shown.where((t) => t.status == status).length}',
                        ),
                        avatar: Icon(
                          Icons.circle,
                          size: 10,
                          color: statusColor(
                            statusTone(
                              settings.statuses.indexOf(status),
                              settings.statuses.length,
                            ),
                            scheme,
                          ),
                        ),
                        selected: index == current,
                        onSelected: (_) => _pages.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (page) => setState(() => _column = page),
                children: [for (final status in columns) columnOf(status)],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Desktop's **Filter by**: type, epic, assignee, priority, label, milestone.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.state,
    required this.filters,
    required this.identify,
    required this.byHandle,
    required this.onChanged,
  });

  final RepositoryState state;
  final TaskFilters filters;
  final Identify identify;
  final Map<String, Person> byHandle;
  final ValueChanged<TaskFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    final tasks = state.tasks;
    final settings = state.settings;
    final milestones = milestonesOf(tasks);
    Future<void> pick(
      String title,
      List<(String?, String)> options,
      String? current,
      TaskFilters Function(String? value) apply,
    ) async {
      final chosen = await showModalBottomSheet<(String?,)>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ListTile(
                title: const Text('All'),
                selected: current == null,
                onTap: () => Navigator.pop(context, (null,)),
              ),
              for (final (value, label) in options)
                ListTile(
                  title: Text(label),
                  selected: current == value,
                  onTap: () => Navigator.pop(context, (value,)),
                ),
            ],
          ),
        ),
      );
      if (chosen != null) onChanged(apply(chosen.$1));
    }

    Widget chip(
      String label,
      String? value,
      String Function(String) name,
      VoidCallback onTap,
      VoidCallback onClear,
    ) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: value == null
          ? ActionChip(label: Text(label), onPressed: onTap)
          : InputChip(
              label: Text('$label: ${name(value)}'),
              selected: true,
              onPressed: onTap,
              onDeleted: onClear,
            ),
    );

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          chip(
            'Type',
            filters.type,
            (v) => v.isEmpty ? 'None' : titleCase(v),
            () => pick(
              'Type',
              [
                for (final type in typesOf(settings.types, tasks))
                  (type.name, titleCase(type.name)),
                ('', 'None'),
              ],
              filters.type,
              (v) => filters.copyWith(type: () => v),
            ),
            () => onChanged(filters.copyWith(type: () => null)),
          ),
          chip(
            'Epic',
            filters.epic,
            epicName,
            () => pick(
              'Epic',
              [
                for (final epic in epicsOf(tasks)) (epic, epic),
                ('', 'No epic'),
              ],
              filters.epic,
              (v) => filters.copyWith(epic: () => v),
            ),
            () => onChanged(filters.copyWith(epic: () => null)),
          ),
          chip(
            'Assignee',
            filters.assignee,
            (v) => v == unassigned ? 'Nobody' : byHandle[v]?.name ?? v,
            () => pick(
              'Assignee',
              [
                for (final person in peopleOf(tasks, identify: identify))
                  (person, byHandle[person]?.name ?? person),
                (unassigned, 'Nobody'),
              ],
              filters.assignee,
              (v) => filters.copyWith(assignee: () => v),
            ),
            () => onChanged(filters.copyWith(assignee: () => null)),
          ),
          chip(
            'Priority',
            filters.priority,
            titleCase,
            () => pick(
              'Priority',
              [for (final p in priorities) (p, titleCase(p))],
              filters.priority,
              (v) => filters.copyWith(priority: () => v),
            ),
            () => onChanged(filters.copyWith(priority: () => null)),
          ),
          if (labelsOf(tasks).isNotEmpty)
            chip(
              'Label',
              filters.label,
              (v) => v,
              () => pick(
                'Label',
                [for (final l in labelsOf(tasks)) (l, l)],
                filters.label,
                (v) => filters.copyWith(label: () => v),
              ),
              () => onChanged(filters.copyWith(label: () => null)),
            ),
          if (milestones.isNotEmpty)
            chip(
              'Milestone',
              filters.milestone,
              (v) => v.isEmpty ? 'None' : v,
              () => pick(
                'Milestone',
                [for (final m in milestones) (m, m), ('', 'None')],
                filters.milestone,
                (v) => filters.copyWith(milestone: () => v),
              ),
              () => onChanged(filters.copyWith(milestone: () => null)),
            ),
        ],
      ),
    );
  }
}
