# Upstream

Changes this app would like in Genbeya itself. Each page is a spec written for Genbeya's repository, in the style of its own [design pages](https://github.com/genbeya/genbeya/blob/develop/docs/Design.md): what it adds, how it fits the plain-file foundation, what is decided and what is open.

None of them blocks the first version of this app. Each spec ends with **Until Genbeya has it**: what the app does meanwhile, and what changes once Genbeya ships it.

| Spec | Adds to Genbeya | Mobile tasks | State in Genbeya |
| --- | --- | --- | --- |
| [[Kit build]] | `build:kit`: Genbeya's renderer and editor as one browser bundle with a message protocol, carried by each release | [[GM-3]] builds it here meanwhile; [[GM-25]] switches to Genbeya's | Built on `develop` ([GENBEYA-68](https://github.com/genbeya/genbeya/blob/develop/tasks/GENBEYA-68.md)), released with 0.2.1; differs from this app's kit, see below |
| [[Attached images]] | Where pasted and captured images live for pages, tasks and pull requests, how they are referenced, and the change ID rule that keeps approvals | [[GM-16]] for pages now; [[GM-26]] for tasks and pull requests | Screenshots in tasks and pull requests decided; the rest proposed |

When Genbeya ships one, note the version here and in the spec, and start its mobile task.

## Genbeya's kit and this app's

Genbeya's kit (`src/shells/kit/` on `develop`, 2026-11-25) speaks protocol 1, as this app's (`kit/src/`) does, but the two differ. The spec ([[Kit build]]) named the messages and left their fields open; Genbeya chose its own, and this app added two messages after the spec. Before the app can use Genbeya's kit ([[GM-25]]):

| | Genbeya's kit | This app's kit | Who changes |
| --- | --- | --- | --- |
| `outline` (kit → host: the headings of the document rendered) | missing | the wiki's **On this page**, and when a page has finished rendering | Genbeya (adds a message; protocol stays 1) |
| `reveal` (host → kit: scroll to a heading) | missing | links to `Page#heading`, and **On this page** | Genbeya (adds a message) |
| `preview` of `markdown`: `checkboxes` | always tick | only where the host says (a pull request's to-dos, not a comment's) | Genbeya (an optional field) |
| `theme` | `mode`, `tokens` without `--` (required) | `theme`, `tokens` with `--` (optional) | the app |
| `context` `wiki` | the nodes | `{wikiRoot, nodes}` | the app |
| `context` `settings` | `{wikiRoot, statuses, calendar}` | `{statuses, hiddenColumns, types, fields}` | the app |
| `context` `plan` | the plan's tasks | `{tasks, calendar}` or null | the app |
| `edit` `readOnly` | required | optional | the app |

## What the conformance cases found in Genbeya

Running Genbeya's own engines over its own task files ([[GM-5]]) showed that a task update changes more than the field it is about. The mobile app reproduces all of it byte for byte, since it must write what the desktop writes; each would be a small fix in Genbeya, after which the app follows by bumping `kit/GENBEYA_REF`.

| Seen with Genbeya at `82e9002` | How often | Why | Suggested fix |
| --- | --- | --- | --- |
| Moving a task's status rewrites `labels: [a, b]` as a block list (`labels:` then `  - a`, `  - b`) | 63 of 100 real task files | `serializeUpdate` sets `labels` to a new array on every update, and new arrays are written in block style; custom fields keep their spelling because they are only set when changed | Set `labels` only when the list changed, as custom fields are |
| Comment headings written without a `## Comments` section get a `\` in front of them on the first edit | 8 of 100 (all written by a coding agent) | Without the section they are description lines that look like comment headings, which `protectHeadings` escapes | Teach the agent skill to add the section; or treat a description that ends in comment headings as comments |
| `estimate: 08` becomes `estimate: 8` | Edge case | YAML 1.2 reads `08` as the number 8, and the whole frontmatter is written again | Quote such values when writing, or write untouched lines back as they were |
| Spacing before a trailing `# comment` collapses to one space; four-space indentation becomes two; long quoted strings are folded at 80 characters | Edge cases | The `yaml` library re-renders the whole document | Acceptable; noted so nobody is surprised by the diffs |
