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
- [x] Task screen: chips, fields, rendered description, comments, activity from Git history: `changesBetween`, `task-activity.ts` and the time log split ported (208 conformance cases), `file_history` in the core (renames followed, merges skipped, a shallow end reported), changes in desktop's words
- [ ] Deepen a shallow clone when the activity needs more history
- [ ] Keep the repository model's parse cache across app starts, so the board opens from it
- [ ] Branches and pull requests of the task, listed

On the Pixel (2026-11-22, CI run 36): the list, filters, board with its strip, and the task screen with its activity work. Found there: a page linked from a task didn't open. Links are now followed in one place (`lib/features/repository/links.dart`): from a task, a page opens on a screen of its own (back arrow, no page tree); mentions and missing pages say what they are, as in the wiki.

