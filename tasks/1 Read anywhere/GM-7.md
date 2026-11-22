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
- [x] People and handles, and "me" (`people_engine.dart`, `people.dart`)
- [ ] References: resolving `[[…]]` to tasks, pages and files
- [ ] `.genbeya-content` and the content branch layout (read only)
- [ ] Event-driven repository model instead of polled snapshots, with a parse cache by blob ID ([[Call chains#the-repository-model]])
- [ ] On resume, `status` catches changes made outside the app

Wiki tree (2026-11-22): `WikiEngine` and `buildFileTree` are ported; 20 cases build the file and wiki trees of Genbeya, of this repository and of an edge list (case, accents, numbers, punctuation, folders with and without pages, `.MD`, other scripts, emoji; wiki roots `docs`, a subfolder, `` and `.`) and match Genbeya's output. The sorting needed ICU's collation in Dart: a table generated from Node's ICU, checked by 42 `collate` cases; on 1,511 strings all 2.3 million pairs compare as ICU compares them. Desktop sorts in the user's locale, so a Swedish or Danish desktop may order some titles differently; the phone follows ICU's root order, which English, German and most locales share.

People (2026-11-22): `PeopleEngine.merge` and `me`, and the handle and mention rules, are ported. Five cases merge people from the settings, made-up commit authors (no real emails in the fixtures), assignees and comment authors: aliases, plus addresses and GitHub's noreply addresses, generic mailboxes, handle collisions (`emile-2`), accents, other scripts and emoji (falling back to `person`), the 39-character cap, and 120 random authors; all match Genbeya. Sorting people needed `localeCompare` at full strength and `normalize("NFD")`, both from the generated table.

