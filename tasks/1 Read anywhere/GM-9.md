---
id: GM-9
title: Task list, board and task screen (reading)
type: feature
status: in-progress
priority: high
estimate: 4d
remaining: 4d
milestone: M1
depends_on: [GM-6, GM-7]
---

The tasks as phones and tablets show them best. See [[Experience#tasks]].

- [x] List grouped by state, with the desktop's filters, milestone included (search by ID, title, assignee or label too)
- [x] Board: one column per screen with a position strip on phones, the whole board on tablets; hidden columns left out
- [ ] Swimlanes by epic on tablets
- [x] Cards with type, ID, title, assignee, priority, dates (overdue in red, soon in yellow)
- [ ] Task screen: chips, fields, rendered description, comments, activity from Git history (deepening a shallow clone when needed): port `changesBetween`, `task-activity.ts` and the time log split (`splitTimeLog` in planning.ts), with conformance cases
- [ ] Keep the repository model's parse cache across app starts, so the board opens from it
- [ ] Branches and pull requests of the task, listed
