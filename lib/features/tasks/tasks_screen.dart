import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../contracts/model.dart';
import '../../managers/repository_model.dart';
import '../../managers/repository_session.dart';
import '../../managers/task_views.dart';
import '../../contracts/clones.dart';
import '../../access/git/git_remote.dart';
import '../repository/changes_screen.dart';
import '../repository/push_sign_in.dart';
import '../repository/search_screen.dart';
import '../repository/task_view_screen.dart';
import 'new_task_screen.dart';
import 'task_card.dart';
import 'task_editing.dart';
import 'task_look.dart';
import 'task_pickers.dart';

/// The tasks as phones show them best: the list grouped by state (the
/// default), or the board one column per screen with a strip of states;
/// on tablets the whole board. Filters as desktop's **Filter by**
/// ([[Experience#tasks]]).
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key, required this.session, this.record});

  final RepositorySession session;

  /// The clone, in the repository's tab: the sync badge and pull to refresh.
  final CloneRecord? record;

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  StreamSubscription<Object>? _changes;

  @override
  void initState() {
    super.initState();
    _changes = widget.session.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  /// Pull to refresh: a sync, and what it did.
  Future<void> _refresh() async {
    final record = widget.record;
    if (record == null) return;
    try {
      final report = await syncRepository(ref, record, widget.session);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeSync(report))));
      }
    } on AuthFailed catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          action: record.credential == CredentialKind.sshKey
              ? null
              : SnackBarAction(
                  label: 'Sign in',
                  onPressed: () async {
                    if (await signInToPush(context, ref, record) && mounted) {
                      await _refresh();
                    }
                  },
                ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  var _filters = const TaskFilters();
  var _board = false;
  var _searching = false;
  final _collapsed = <String>{};
  final _pages = PageController();
  var _column = 0;

  RepositoryState get _state => widget.session.state!;

  @override
  void dispose() {
    _changes?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _open(Task task) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TaskViewScreen(session: widget.session, task: task),
    ),
  );

  /// A new task, from the button or a state's "+"; the created task opens.
  Future<void> _newTask({String? status}) async {
    final record = widget.record;
    if (record == null) return;
    final created = await Navigator.of(context).push<Task>(
      MaterialPageRoute(
        builder: (_) => NewTaskScreen(
          record: record,
          session: widget.session,
          status: status,
        ),
      ),
    );
    if (created != null && mounted) _open(created);
  }

  /// **Move to…**: another workflow state.
  Future<void> _moveTo(Task task) async {
    final status = await pickStatus(context, _state.settings, task.status);
    if (status != null) await _move(task, status);
  }

  Future<void> _move(Task task, String status) async {
    final record = widget.record;
    if (record == null || status == task.status) return;
    await changeTask(
      context,
      ref,
      record,
      widget.session,
      (tasks) => tasks.update(task, task.toInput().copyWith(status: status)),
    );
  }

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
    final editable = widget.record != null;
    Widget card(Task task, {bool showEpic = true}) {
      final shownCard = TaskCard(
        task: task,
        settings: settings,
        assigneeName: _nameOf(task.assignee, byHandle, identify),
        onTap: () => _open(task),
        onLongPress: editable && !_board ? () => _moveTo(task) : null,
        showEpic: showEpic,
      );
      return editable && _board ? _draggable(task, shownCard) : shownCard;
    }

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
          if (widget.record != null)
            SyncBadge(record: widget.record!, session: widget.session),
          IconButton(
            tooltip: _searching ? 'Stop filtering' : 'Filter tasks by text',
            icon: Icon(_searching ? Icons.close : Icons.filter_list),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _filters = _filters.copyWith(query: '');
            }),
          ),
          IconButton(
            tooltip: 'Search everything',
            icon: const Icon(Icons.manage_search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SearchScreen(session: widget.session),
              ),
            ),
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
      floatingActionButton: editable
          ? FloatingActionButton(
              tooltip: 'New task',
              onPressed: () => _newTask(
                status: _board && columns.isNotEmpty
                    ? columns[_column.clamp(0, columns.length - 1)]
                    : null,
              ),
              child: const Icon(Icons.add),
            )
          : null,
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
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.record != null)
                  IconButton(
                    tooltip: 'New ${titleCase(column).toLowerCase()} task',
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: () => _newTask(status: column),
                  ),
                Icon(
                  _collapsed.contains(column)
                      ? Icons.expand_more
                      : Icons.expand_less,
                ),
              ],
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
    return widget.record == null
        ? list
        : RefreshIndicator(onRefresh: _refresh, child: list);
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
      final content = tasks.isEmpty
          ? Center(
              child: Text(
                'Nothing ${titleCase(status).toLowerCase()}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [for (final task in tasks) card(task)],
            );
      return _dropOn(
        status,
        (active) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: active
              ? scheme.primaryContainer.withValues(alpha: 0.35)
              : null,
          child: content,
        ),
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
                      // A card dragged onto a state's chip moves there.
                      child: _dropOn(
                        status,
                        (active) => ChoiceChip(
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
                          selected: index == current || active,
                          onSelected: (_) => _pages.animateToPage(
                            index,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          ),
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

  /// Whether a card is being dragged, for the drop targets to show.
  var _dragging = false;

  /// A card that a long press drags to another state; released where it
  /// started, it offers **Move to…** instead.
  Widget _draggable(Task task, Widget card) {
    var travelled = 0.0;
    final width = MediaQuery.sizeOf(context).width;
    return LongPressDraggable<Task>(
      data: task,
      feedback: SizedBox(
        width: width >= 840 ? 300 : width - 24,
        child: Material(
          type: MaterialType.transparency,
          elevation: 8,
          child: card,
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      onDragStarted: () => setState(() => _dragging = true),
      onDragUpdate: (details) => travelled += details.delta.distance,
      onDragEnd: (_) => setState(() => _dragging = false),
      onDraggableCanceled: (_, _) {
        if (travelled < 24) _moveTo(task);
      },
      child: card,
    );
  }

  /// [status] as a place to drop a card on.
  Widget _dropOn(String status, Widget Function(bool active) builder) =>
      DragTarget<Task>(
        onWillAcceptWithDetails: (details) => details.data.status != status,
        onAcceptWithDetails: (details) => _move(details.data, status),
        builder: (context, candidates, _) =>
            builder(_dragging && candidates.isNotEmpty),
      );
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
