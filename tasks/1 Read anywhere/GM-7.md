---
id: GM-7
title: "Port the read engines: settings, wiki, tasks, people"
type: feature
status: in-progress
priority: high
estimate: 4d
remaining: 4d
milestone: M1
depends_on: [GM-5]
---

The Dart engines needed to show a repository, each checked by conformance cases. See [[Architecture#engines]].

- [ ] Contracts mirroring `model.ts`: `Settings`, `WikiNode`, `Task`, `Person`, field definitions
- [ ] Settings: every key, defaults and validation, `unused` and the automatic parts
- [x] Wiki tree and titles from file names (`wiki_engine.dart`, `file_tree.dart`; sorted by `collation.dart`, ICU's order without ICU)
- [ ] Tasks: parsing, epics, comments section, time log split, custom field kinds (effort, tasks, date, choice)
- [ ] People and handles, and "me"
- [ ] References: resolving `[[…]]` to tasks, pages and files
- [ ] `.genbeya-content` and the content branch layout (read only)
- [ ] Event-driven repository model instead of polled snapshots, with a parse cache by blob ID ([[Call chains#the-repository-model]])
- [ ] On resume, `status` catches changes made outside the app

Wiki tree (2026-11-22): `WikiEngine` and `buildFileTree` are ported; 20 cases build the file and wiki trees of Genbeya, of this repository and of an edge list (case, accents, numbers, punctuation, folders with and without pages, `.MD`, other scripts, emoji; wiki roots `docs`, a subfolder, `` and `.`) and match Genbeya's output. The sorting needed ICU's collation in Dart: a table generated from Node's ICU, checked by 42 `collate` cases; on 1,511 strings all 2.3 million pairs compare as ICU compares them. Desktop sorts in the user's locale, so a Swedish or Danish desktop may order some titles differently; the phone follows ICU's root order, which English, German and most locales share.

