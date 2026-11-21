## Tasks and wiki (Genbeya)

This project plans its work as Genbeya tasks and documents itself in a Genbeya wiki, both plain Markdown files in this repository.

- Use tasks instead of an internal todo list. Tasks are files in `tasks/` named after their ID (`GM-12.md`), in epic folders. Keep a task's `status` current as you go, and tick its checklist.
- Use the wiki instead of private memory files. Pages are Markdown files in `docs/`, starting at `docs/Home.md`. Read the relevant pages before you change an area, and record durable project knowledge there.
- `.genbeya.yml` holds the workflow states, the task prefix, the planning fields and the milestones.
- Android first: a task is done when it works on Android. If iOS matters for it and nobody tried it on an iPhone, set `ios: to-check` (see [[Roadmap]]).
- Reference tasks, pages and files as `[[GM-12]]`, `[[Page title]]` or `[[lib/app.dart#L10-L20]]`, and name the task in commit messages and pull requests.

## Staying in step with Genbeya

This app reads and writes Genbeya's file formats. What it writes must be byte for byte what Genbeya desktop writes: change an engine in `lib/engines/` only together with conformance cases in `tool/conformance/` (see [[Architecture#conformance]]).
