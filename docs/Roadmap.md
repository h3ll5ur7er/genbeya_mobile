# Roadmap

Six milestones, each ending in something to hold in the hand. The order puts the risky parts first (Git on a phone, Genbeya's renderer in a WebView), then reading, then the edits people make most often on a phone, then writing, planning and review.

The trial's estimates add up to about 86 working days; 3 more follow once Genbeya ships the two [[Upstream]] specs, which the trial doesn't wait for. The critical path is 35 days (Git core → repositories → board → task edits → comments → review actions → trial), so the timeline below, which runs work in parallel where nothing waits, is what two or three people could do; the milestone dates in `.genbeya.yml` assume one developer full time. Move them as you learn.

> [!TIP]
> Open this repository in Genbeya desktop (the `develop` build, which has planning) to see the blocks below drawn from the tasks: the timeline, what waits for what, and the effort.

[TOC]

## Milestones

| | Milestone | You can | Tasks |
| --- | --- | --- | --- |
| M0 | **Spikes** | Clone, commit and push on a real phone; see a Genbeya page rendered offline; pick the editor | [[GM-1]] to [[GM-5]] |
| M1 | **Read anywhere** | Clone a repository, read its wiki, browse its board, search, open `genbeya://` links | [[GM-6]] to [[GM-10]] |
| M2 | **Work on tasks** | Move tasks, edit fields, tick checklists, comment, create tasks, sync, see **Today** | [[GM-11]] to [[GM-15]] |
| M3 | **Write** | Edit pages and add photos to them, browse and edit code, copy references to lines | [[GM-16]], [[GM-17]] |
| M4 | **Plan and review** | See effort and what blocks what, log time; review pull requests, comment on lines, approve | [[GM-18]] to [[GM-21]] |
| M5 | **Trial** | Install a test build, try the sample project, use it daily for two weeks, decide | [[GM-22]] to [[GM-24]], [[GM-27]] |
| — | **When Genbeya has it** | The kit from Genbeya's releases; images in tasks and pull requests ([[Upstream]]) | [[GM-25]], [[GM-26]] |

M0 ends with a decision gate: if Git on iOS or the kit in a WebView doesn't work well enough, the plan changes before more is built (see [Risks](#risks)).

**Android first** (2026-11-21): the app builds for iOS in CI, but trying it on an iPhone and signing it wait until a Mac is at hand; the spikes and milestones are judged on Android until then. A task finished without an iPhone check carries `ios: to-check` (a field in `.genbeya.yml`), so the iPhone round is a filter rather than a memory: once a Mac can build, sign and run the app, go through those and set `works` or `fails`.

## The plan

[GANTT]

### What waits for what

[DEPENDENCIES]

### Effort

[EFFORT]

## How the trial is judged

The question for the end of M5 is whether Genbeya should have an official mobile client. These make the answer concrete:

| Measure | Good enough |
| --- | --- |
| **Fidelity** | No spurious diff in any file the app wrote, over two weeks of use on genbeya/genbeya; every write covered by a conformance case |
| **Sync** | Never an edit lost; a sync of a few task edits under 5 s on a mobile network |
| **Speed** | Cold start to **Today** under 2 s; a wiki page under 1 s; a shallow clone of genbeya/genbeya under 30 s on Wi-Fi |
| **Use** | Reached for it at least daily, for reading, the board and reviews, instead of waiting to be at the desk |
| **Cost of two codebases** | How many nightly conformance failures a month of Genbeya `develop` caused, and how long each took to follow |

The last row decides how an official client would be built: if following the desktop is cheap, the separate codebase stays; if not, the upstream changes in [[Architecture#changes-upstream-that-would-help]] come first.

## Risks

| Risk | Why it matters | What we do |
| --- | --- | --- |
| libgit2 on iOS and Android (cross-compiling, OpenSSL, SSH) | Nothing works without Git | First spike ([[GM-2]]); `git2dart` with prebuilt binaries as the fallback |
| The change ID differs from the desktop's | Pull request approvals computed on the phone would read as stale | The ID hashes `git diff` output; libgit2's diff must match it with the same options. Conformance cases in [[GM-19]]; if it can't match, the phone shows approvals by commit and says "check on desktop" for rebased ones |
| YAML edits reformat frontmatter | A status change would rewrite `labels: [a, b]` or drop a comment | yaml_edit for edits that keep comments, else a line-level edit of the one key, as narrow as the desktop's; conformance cases for each field kind |
| WebView inside native screens | Scrolling, height and keyboard can feel off | Measured in [[GM-3]]; pages that are only Markdown can be a full-screen WebView with native chrome |
| libgit2's own bugs | A failed TLS check behind an HTTP proxy writes into a freed stream and hangs (found in [[GM-2]]) | Report upstream; a one-line patch to libgit2-sys if needed; network timeouts set in the core |
| Desktop formats still moving (planning and pull requests are prototypes) | The ported engines go stale | Nightly conformance against `develop`; the kit follows by bumping `kit/GENBEYA_REF` |
| Large repositories on a phone | Storage, clone time | Shallow single-branch clones, deepened on demand; per-repository size on the start screen |
| Background limits on iOS | Automatic sync can't run while the app is closed | Sync on open, on pull to refresh and after edits; no promise of background sync in the trial |

## Decisions

All twelve open decisions were decided on 2026-11-21, eleven as recommended. Images go into pages in the trial, and into tasks and pull requests at release, following Genbeya. [[Decisions]] keeps each with its options, its reasons and what it changed.
