---
id: GM-7
title: "Port the read engines: settings, wiki, tasks, people"
type: feature
status: backlog
priority: high
estimate: 4d
remaining: 4d
milestone: M1
depends_on: [GM-5]
---

The Dart engines needed to show a repository, each checked by conformance cases. See [[Architecture#engines]].

- [ ] Contracts mirroring `model.ts`: `Settings`, `WikiNode`, `Task`, `Person`, field definitions
- [ ] Settings: every key, defaults and validation, `unused` and the automatic parts
- [ ] Wiki tree and titles from file names
- [ ] Tasks: parsing, epics, comments section, time log split, custom field kinds (effort, tasks, date, choice)
- [ ] People and handles, and "me"
- [ ] References: resolving `[[…]]` to tasks, pages and files
- [ ] `.genbeya-content` and the content branch layout (read only)
- [ ] Event-driven repository model instead of polled snapshots, with a parse cache by blob ID ([[Call chains#the-repository-model]])
- [ ] On resume, `status` catches changes made outside the app
