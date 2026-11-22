import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/contracts/model.dart';
import 'package:genbeya_mobile/managers/task_views.dart';

Task task(
  String id, {
  String title = 'T',
  String status = 'todo',
  String priority = 'none',
  String assignee = '',
  List<String> labels = const [],
  String type = '',
  String epic = '',
  Map<String, FieldValue> fields = const {},
}) => Task(
  id: id,
  path: 'tasks/$id.md',
  title: title,
  status: status,
  priority: priority,
  assignee: assignee,
  labels: labels,
  type: type,
  fields: fields,
  body: '',
  epic: epic,
  hash: 'h',
  comments: const [],
);

void main() {
  test('order: priority, then the newest number, then the title', () {
    final tasks = [
      task('GM-2'),
      task('GM-10'),
      task('GM-3', priority: 'urgent'),
      task('GM-1', priority: 'high'),
      task('X', title: 'b'),
      task('Y', title: 'a'),
    ];
    expect(visibleTasks(tasks, const TaskFilters()).map((t) => t.id), [
      'GM-3',
      'GM-1',
      'GM-10',
      'GM-2',
      'Y',
      'X',
    ]);
  });

  test('filters, an assignee by person however tasks write them', () {
    final people = [
      const Person(
        handle: 'ada',
        name: 'Ada Lovelace',
        email: 'ada@example.com',
        aliases: [],
        commits: 1,
      ),
    ];
    final tasks = [
      task(
        'A-1',
        assignee: 'Ada Lovelace',
        labels: ['ui'],
        fields: {'milestone': 'M1'},
      ),
      task('A-2', assignee: 'ada@example.com', type: 'bug', epic: '1 Plan'),
      task('A-3', priority: 'high', title: 'Fix the login'),
    ];
    final identify = identifyBy(people);
    String ids(TaskFilters filters) => visibleTasks(
      tasks,
      filters,
      identify: identify,
    ).map((t) => t.id).join(',');
    expect(ids(const TaskFilters(assignee: 'ada')), 'A-2,A-1');
    expect(ids(const TaskFilters(assignee: unassigned)), 'A-3');
    expect(ids(const TaskFilters(label: 'ui')), 'A-1');
    expect(ids(const TaskFilters(type: 'bug')), 'A-2');
    expect(ids(const TaskFilters(type: '')), 'A-3,A-1');
    expect(ids(const TaskFilters(epic: '1 Plan')), 'A-2');
    expect(ids(const TaskFilters(milestone: 'M1')), 'A-1');
    expect(ids(const TaskFilters(milestone: '')), 'A-3,A-2');
    expect(ids(const TaskFilters(query: 'LOGIN')), 'A-3');
    expect(peopleOf(tasks, identify: identify), ['ada']);
  });

  test('columns, epics by phase, types and labels', () {
    final tasks = [
      task('A-1', status: 'blocked', epic: '10 Launch', type: 'spike'),
      task('A-2', epic: '2 Build', labels: ['b', 'a']),
      task('A-3', epic: 'Spikes'),
    ];
    expect(columnsOf(['todo', 'done'], tasks), ['todo', 'done', 'blocked']);
    expect(epicsOf(tasks), ['2 Build', '10 Launch', 'Spikes']);
    expect(lanesOf(tasks).last, '');
    expect(labelsOf(tasks), ['a', 'b']);
    expect(
      typesOf([
        const TaskType(name: 'bug', icon: 'bug'),
      ], tasks).map((t) => t.name),
      ['bug', 'spike'],
    );
    expect(statusTone(0, 5), StatusTone.gray);
    expect(statusTone(4, 5), StatusTone.green);
    expect(statusTone(2, 5), StatusTone.yellow);
    expect(statusTone(-1, 5), StatusTone.other);
    expect(titleCase('in-progress'), 'In progress');
    expect(displayId('0f3e9c2a-1b2c-4d5e-8f90-123456789abc'), '0f3e9c2a');
  });

  test('due dates: overdue, soon, and nothing once done', () {
    const settings = Settings(
      name: 'x',
      wikiRoot: 'docs',
      wikiHome: 'Home.md',
      taskRoot: 'tasks',
      taskPrefix: 'X',
      statuses: ['todo', 'done'],
      statusIcons: {},
      hiddenColumns: [],
      types: [],
      fields: [FieldDefinition(name: 'due', type: 'date')],
      people: [],
      pullRoot: 'pulls',
      pullPrefix: 'PR',
      requiredApprovals: 1,
      todosBlockMerge: true,
      unused: [],
      workdays: ['mon'],
      holidays: [],
      milestones: [],
    );
    DueTone? tone(String due, {String status = 'todo'}) => dueDatesOf(
      task('A', status: status, fields: {'due': due}),
      settings,
      '2026-11-22',
    ).single.tone;
    expect(tone('2026-11-21'), DueTone.overdue);
    expect(tone('2026-11-24'), DueTone.soon);
    expect(tone('2026-11-30'), isNull);
    expect(tone('2026-11-21', status: 'done'), isNull);
    expect(
      dueDatesOf(
        task('A', fields: {'due': '2026-02-30'}),
        settings,
        '2026-11-22',
      ),
      isEmpty,
    );
    expect(labelHue('ui'), isIn([250, 160, 25, 210, 320, 45, 280, 185]));
  });

  test("activity in the desktop's words", () {
    expect(describeChange({'kind': 'created'}), 'created the task');
    expect(
      describeChange({
        'kind': 'field',
        'field': 'status',
        'from': 'todo',
        'to': 'in-progress',
      }),
      'status Todo → In progress',
    );
    expect(
      describeChange({
        'kind': 'field',
        'field': 'assignee',
        'from': '',
        'to': 'ada',
      }),
      'assignee nobody → ada',
    );
    expect(
      describeChange({
        'kind': 'field',
        'field': 'title',
        'from': 'A',
        'to': 'B',
      }),
      'title “A” → “B”',
    );
    expect(
      describeChange({
        'kind': 'field',
        'field': 'epic',
        'from': '',
        'to': '1 Plan',
      }),
      'epic No epic → 1 Plan',
    );
    expect(
      describeChange({
        'kind': 'labels',
        'added': ['a'],
        'removed': ['b'],
      }),
      'labels +a −b',
    );
    expect(
      describeChange({
        'kind': 'comments',
        'added': 1,
        'edited': 2,
        'removed': 0,
      }),
      'added a comment, edited 2 comments',
    );
    expect(
      describeChange({
        'kind': 'timelog',
        'added': ['2026-11-21 — Ada — 1h'],
        'removed': 1,
      }),
      'logged 2026-11-21 — Ada — 1h, removed an entry of the time log',
    );
    expect(
      describeChange({
        'kind': 'custom',
        'field': 'estimate',
        'from': '',
        'to': '2d',
      }),
      'estimate none → 2d',
    );
    expect(
      describeChange({
        'kind': 'other',
        'fields': ['meta', 'x'],
      }),
      'changed meta, x',
    );
  });
}
