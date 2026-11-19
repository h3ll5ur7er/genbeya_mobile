# Architecture

How the app is put together, and how it stays in step with Genbeya desktop while the two codebases are separate. Decisions marked **Spike** are made in milestone M0 ([[Roadmap]]).

[TOC]

## Overview

The desktop app's layering by volatility carries over ([Architecture](https://github.com/genbeya/genbeya/blob/develop/docs/Architecture.md)): each layer hides one thing that is likely to change, and calls only go down.

```mermaid
flowchart TB
  subgraph Flutter["Flutter (Dart)"]
    features[Features: today, wiki, tasks, pulls, code, search, changes] --> core[State, navigation, sheets]
    core --> managers[Managers: workspace, content, version control]
    managers --> engines[Engines: tasks, comments, settings, planning, pulls, references, people, wiki]
    managers --> access[Access: Git core, files, credentials, preferences]
  end
  subgraph Kit["Web kit (TypeScript from Genbeya, in a WebView)"]
    render[Renderer: Genbeya's Markdown pipeline, Mermaid, rockuml, KaTeX]
    editor[Editor: CodeMirror 6 with Genbeya's completions]
  end
  subgraph Native["Native core (Rust)"]
    git[git2 / libgit2: clone, fetch, commit, merge, rebase, diff, push]
  end
  features -- "messages" --> Kit
  access -- "flutter_rust_bridge" --> git
```

| Layer | Folder | Hides | Notes |
| --- | --- | --- | --- |
| Contracts | `lib/contracts/` | Nothing: the model types (`Task`, `Settings`, `WikiNode`, `Pull`, …) | Mirror `src/contracts/model.ts`, same names and JSON shape |
| Engines | `lib/engines/` | The rules for the file formats | Pure Dart, no I/O; ported from Genbeya and checked against it ([Conformance](#conformance)) |
| Access | `lib/access/` | How Git is called, where files and secrets are kept | Git through the native core; files through `dart:io` |
| Managers | `lib/managers/` | The use cases: open, save a task, comment, sync | Named after the desktop's managers and their calls, so a desktop change points at its mobile counterpart |
| Features | `lib/features/` | The user interface | Flutter widgets; state with Riverpod, routes with go_router |
| Web kit | `kit/` | Rendering and editing Markdown and code | Built from Genbeya's own sources, see below |
| Native core | `native/` | libgit2, and later rockuml | A Rust crate, bound with flutter_rust_bridge |

## Git on the device

Mobile platforms have no `git` command, and iOS can't run one. Desktop Genbeya speaks Git's command line, so this is the one part that is truly new.

| Option | Clone, fetch, push | Merge, rebase, diff | Android and iOS | Verdict |
| --- | --- | --- | --- | --- |
| **Rust core with `git2` (libgit2)** through flutter_rust_bridge | Yes, HTTPS and SSH | Yes, with options close to Git's (indent heuristic, rename detection) | Cross-compiles with vendored libgit2, OpenSSL and libssh2; GitSync is a Flutter app on this stack | **Recommended**. The Tauri shell is already Rust, and rockuml can join the same crate later |
| `git2dart` (libgit2 over Dart FFI) | Yes | Yes | Prebuilt binaries for Android and iOS | Fallback if the Rust toolchain costs too much time |
| gitoxide (`gix`) | Clone and fetch; push not finished | Partly | Pure Rust, easy to build | Not yet |
| Pure-Dart Git | Partial | Little | Yes | Too incomplete |
| Forge APIs only (GitHub, GitLab REST) | Through the API | Through the API | Yes | Breaks "any Git host" and offline; not the core, maybe a later "quick look without cloning" |

**Spike** ([[GM-2]]): clone, edit, commit, fetch, rebase and push over HTTPS and SSH on a real Android phone and an iPhone, with a shallow clone, before anything else is built on it.

The native core exposes a small, task-shaped API rather than libgit2 itself: `clone`, `fetch`, `status`, `commitFiles` (write a commit from changed paths, optionally onto another branch's tree without a checkout), `rebaseOnto`, `push`, `log` (with paths, for activity and plan history), `diff` (merge base to head, for pull requests), `mergeTree` (would it conflict), `readBlob` (a file at a revision).

### Clones on a phone

- **Shallow, single branch** by default (the newest 200 commits), plus the content branch if a remote has one. **Activity**, **Burndown** and **Baseline** deepen the clone on demand and say so while they do.
- **Storage** per repository is shown on the start screen, with **Remove clone**.
- **The content branch** needs no worktree on the device: its areas are read from the branch's tree and edits are committed straight onto it, which libgit2 does without a checkout. `.genbeya-content` decides the layout as on desktop ([Content branch](https://github.com/genbeya/genbeya/blob/develop/docs/Architecture/Content-branch.md)).

## Where edits go

```mermaid
sequenceDiagram
  participant U as You
  participant A as App
  participant L as Local clone
  participant R as Remote
  U->>A: Move GM-12 to review
  A->>L: write tasks/GM-12.md, commit "GM-12: Move to review"
  U->>A: Sync
  A->>R: fetch
  A->>L: rebase local commits onto the remote branch
  alt applies cleanly
    A->>R: push
  else conflicts in a task or pull request file
    A->>L: Genbeya merge: fields one by one, signed lines from both sides
    A->>R: push
  else still conflicts
    A->>L: keep local commits on mobile/rescue-date, reset to the remote
    A->>U: say what differs, finish on desktop
  end
```

- The target branch (content branch, checked-out branch, or `mobile/<handle>`) is chosen per repository, see [[Experience#sync-and-changes]].
- The Genbeya merge for task and pull request files is an engine of its own ([[GM-11]]): three-way per frontmatter key; for `## Comments`, `## Time log`, replies and verdicts, both sides' new lines in time order. It only acts where the formats were designed to merge, and gives up otherwise.
- Pushes go through a queue: one sync at a time per repository, as the desktop's serial queue does.

## The web kit

Genbeya renders Markdown with a pipeline of about 5,000 lines (`src/client/app/markdown/`: references, embeds, mentions, dates, callouts, math, diagrams, plan macros) on top of unified and remark, draws Mermaid, PlantUML through rockuml's WebAssembly, and KaTeX. Porting that to Dart would be the largest and most fragile part of the work, and every desktop change would have to be redone.

The VS Code extension already solved the same problem: its webviews (`src/shells/vscode/webview/`) render pages and tasks with the client's pipeline, outside Angular, and talk to the host only through messages (`protocol.ts`): the host sends a document and a `MarkdownContext` (wiki tree, task titles and states, people, settings, plan tasks); the webview reports followed links, checkbox toggles and requests for images and files. **The mobile app is another host for that protocol.**

- **The kit** is a small bundle built from a pinned Genbeya commit: the VS Code webview's Markdown renderer and its message protocol, plus a CodeMirror 6 editor with Genbeya's Markdown language and the `[[`, `@` and `//` completions (`references.ts`, `mention-suggestions.ts`, `smart-dates.ts`). `tool/build_kit` checks out Genbeya at the ref in `kit/GENBEYA_REF`, builds, and copies the result into `kit/dist/`, which is committed so the app builds without Node.
- **The WebView** is flutter_inappwebview, serving the kit from a custom scheme (as Electron serves `genbeya://app`), with the desktop's content security policy: no remote scripts, no network, WebAssembly allowed for rockuml. Markdown never becomes HTML; the allowlisted DOM builder is the same code.
- **Native around it**: titles, chips, sheets, lists and the board are Flutter. The WebView renders the body of a page, a task's description and comments, a pull request's file, and hosts the editors. It reports its height so it scrolls with the native parts around it.
- **Theme**: the app's colours are passed in as the kit's tokens, light and dark.

**Spike** ([[GM-3]], [[GM-4]]): render this wiki and Genbeya's own `docs/` (references, Mermaid, PlantUML, math, `[GANTT]`) on both platforms offline; and compare editing a long Markdown file in CodeMirror 6 in the WebView with a native Flutter editor (re_editor) for typing, selection handles, autocorrect and scrolling on real devices. CodeMirror 6 is the expected winner (built for touch, the desktop's editor, completions for free); if it loses, the code editor goes native and only Markdown stays in the kit.

## Engines

What the app decides itself is ported to Dart, small and pure as on desktop:

| Engine | From Genbeya | Does |
| --- | --- | --- |
| Settings | `settings-engine.ts` | Reads `.genbeya.yml` with its defaults and validation; edits keep comments (yaml_edit) |
| Tasks | `task-engine.ts`, `text-style.ts` | Parses task files; changes a field without touching the others, their order, YAML comments, line endings or BOM; creates tasks with the next ID and templates |
| Comments and signed lines | `task-comments.ts`, the time log in `planning.ts` | Reads, appends, edits comments and time log lines; flags lines it can't read |
| Planning | `planning.ts` | Effort, the five numbers, blocked and ready, critical path and float for the task screen and cards |
| Pull requests | `pull-requests.ts`, `pull-engine.ts` | Topics, code ranges, replies, verdicts, to-dos, effective approvals, ready to merge, the change ID |
| References and links | `utilities/references.ts`, `genbeya-link.ts`, `remote-url.ts` | Resolving `[[…]]`, strict `genbeya://` parsing, web links per forge |
| People | `people-engine.ts`, `utilities/people.ts` | Handles, aliases, "me" |
| Wiki | `wiki-engine.ts` | The page tree and titles from file names |
| Activity | `task-activity.ts` | Field changes between versions of a task |
| Search | `search-engine.ts` | Results and excerpts, over the files with Dart's regular expressions, in an isolate |

Plan macros need no Dart port: the kit computes them from the tasks it is given, with the desktop's own `planning.ts` and `plan-history.ts`.

## Conformance

Two codebases drift unless something notices. Every engine is checked against Genbeya itself:

- `tool/conformance/` holds fixture repositories and edits (change a status in a file with YAML comments and CRLF, append a comment, log time, add a verdict, parse a broken time log line, compute float, compute a change ID, …).
- A Node script imports Genbeya's engines from the pinned checkout, runs each case and writes the expected results as JSON.
- Dart tests run the same cases through the ported engines and compare, byte for byte for files.
- CI runs it against the pinned ref on every push, and nightly against Genbeya's `develop`, so a desktop change that the mobile app doesn't follow yet shows up as a failing case, not as a corrupted file in someone's repository.

The rule that follows: the app writes nothing that conformance doesn't cover.

## Security

The same stance as the desktop ([Security](https://github.com/genbeya/genbeya/blob/develop/docs/Architecture/Security.md)): repositories are untrusted content.

- The kit runs with the desktop's content security policy, no network, and only the message protocol to reach the app. Links open in the system browser for `http`, `https` and `mailto` only.
- Every path a message names is checked with the desktop's path rules before a file is read.
- Credentials live in the system keychain, never in the clone's config or in links.
- SSH host keys are pinned on first use, with the fingerprint shown.
- Git runs no hooks (libgit2 has none) and no filters from the repository.

## Repository layout

```text
lib/
  contracts/  engines/  access/  managers/  features/  app.dart
kit/
  GENBEYA_REF  dist/  src/        # the kit's entry points, importing Genbeya's sources
native/
  genbeya_core/                   # Rust crate: git2, later rockuml
tool/
  build_kit  conformance/
test/  integration_test/
docs/  tasks/  .genbeya.yml       # this wiki and board
```

## Changes upstream that would help

None are needed for the trial; each would make an official client cheaper:

- A `build:kit` target in Genbeya that builds the VS Code webview renderer and the editor as one browser bundle, so the mobile repository doesn't need its own build of Genbeya's sources.
- Conformance cases kept in Genbeya, next to the engines' specs, as JSON any client can run.
- A short page of the file formats' grammar (signed lines, verdicts, time log), which the design pages already ask for.
