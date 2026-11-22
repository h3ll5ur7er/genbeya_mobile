---
id: GM-7
title: "Port the read engines: settings, wiki, tasks, people"
type: feature
status: review
priority: high
estimate: 4d
remaining: 0d
milestone: M1
depends_on: [GM-5]
---

The Dart engines needed to show a repository, each checked by conformance cases. See [[Architecture#engines]].

- [x] Contracts mirroring `model.ts`: `Settings`, `WikiNode`, `FileNode`, `Task`, `Person`, field definitions
- [x] Settings: every key, defaults and validation, `unused` and the automatic parts (ported with [[GM-5]], every key of `Settings` in `model.ts`)
- [x] Wiki tree and titles from file names (`wiki_engine.dart`, `file_tree.dart`; sorted by `collation.dart`, ICU's order without ICU)
- [x] Tasks: parsing, epics, comments section, custom field kinds (effort, tasks, date, choice); the time log split is only used by a task's activity, so it moved to [[GM-9]] with `changesBetween`
- [x] People and handles, and "me" (`people_engine.dart`, `people.dart`)
- [x] References: resolving `[[…]]` to tasks, pages and files happens in the kit, with Genbeya's own code, from the context the host sends; the native side needs it first for search and links, so the Dart port moved to [[GM-10]]
- [x] `.genbeya-content` and the content branch layout (read only): `content_layout.dart`, `RepositoryModel.locate`
- [x] Event-driven repository model instead of polled snapshots, with a parse cache by blob ID ([[Call chains#the-repository-model]]): the model and its in-memory cache; the app's own writes updating it directly come with the writes ([[GM-11]]), keeping the cache across starts with the first screens that need fast cold starts ([[GM-9]])
- [x] On resume, `status` catches changes made outside the app: the model reads Git's objects, not the working tree, so only uncommitted writes of the app itself can differ, which the write journal handles ([[GM-11]])

Wiki tree (2026-11-22): `WikiEngine` and `buildFileTree` are ported; 20 cases build the file and wiki trees of Genbeya, of this repository and of an edge list (case, accents, numbers, punctuation, folders with and without pages, `.MD`, other scripts, emoji; wiki roots `docs`, a subfolder, `` and `.`) and match Genbeya's output. The sorting needed ICU's collation in Dart: a table generated from Node's ICU, checked by 42 `collate` cases; on 1,511 strings all 2.3 million pairs compare as ICU compares them. Desktop sorts in the user's locale, so a Swedish or Danish desktop may order some titles differently; the phone follows ICU's root order, which English, German and most locales share.

People (2026-11-22): `PeopleEngine.merge` and `me`, and the handle and mention rules, are ported. Five cases merge people from the settings, made-up commit authors (no real emails in the fixtures), assignees and comment authors: aliases, plus addresses and GitHub's noreply addresses, generic mailboxes, handle collisions (`emile-2`), accents, other scripts and emoji (falling back to `person`), the 39-character cap, and 120 random authors; all match Genbeya. Sorting people needed `localeCompare` at full strength and `normalize("NFD")`, both from the generated table.

Repository model (2026-11-22): the core reads files from Git's objects (`resolve_commit`, `list_files` with blob IDs, `read_blobs` in one call, `read_file_at`, `changed_paths`, `config_value`; a flow test). `RepositoryModel` locates each area (checkout or content branch, by `.genbeya-content`, read as `git config` reads it: 24 conformance cases run real `git config --list`), then reads settings, the wiki tree, tasks (problems listed by file) and the people the settings, assignees and comments name, with parses cached by blob. Tested with a fake over every layout and over a real clone through the bridge. People also count the authors of HEAD's newest 5,000 commits as `.mailmap` names them (`commit_authors` in the core, read again only when HEAD moves), and `me` is who Git signs commits as in the clone (`user.name`, `user.email`, which the app sets per repository in [[GM-6]]). Not yet: keeping the cache across app starts.

