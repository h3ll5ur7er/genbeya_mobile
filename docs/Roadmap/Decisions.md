# Decisions

The open questions of the plan, each with the reasonable options, a recommendation and why. They are ordered by when they have to be settled. All twelve were decided on 2026-11-21: eleven as recommended, and D8 with images everywhere once Genbeya itself has them. Each section ends with its outcome; the consequences are in the pages and tasks it names.

[TOC]

## Overview

| | Decision | Needed before | Recommendation | Status |
| --- | --- | --- | --- | --- |
| D1 | License of this repository | The first code | FSL-1.1-ALv2, as Genbeya | Decided |
| D2 | Where the kit is built | [[GM-3]] | Here for the spike, then a `build:kit` target in Genbeya | Decided |
| D3 | Git core | End of M0 ([[GM-2]]) | Rust with `git2`; `git2dart` if the build fails | Decided |
| D4 | Editor | End of M0 ([[GM-4]]) | CodeMirror 6 in the kit for pages and code; a native field for comments | Decided |
| D5 | Where edits go without a content branch | [[GM-11]] | Ask once, offer the checked-out branch, move to `mobile/<handle>` when a push is refused | Decided |
| D6 | The rescue branch | [[GM-11]] | Push it, namespaced, and clean it up once merged | Decided |
| D7 | Clones visible to other apps | [[GM-7]] | Keep them private to the app | Decided |
| D8 | Photos and screenshots | M3 | Images in pages in the trial; in tasks and pull requests at release, as Genbeya will have them | Decided differently |
| D9 | Replies on a pull request whose file is on the source branch | [[GM-21]] | Commit onto the source branch without switching | Decided |
| D10 | Merging pull requests on the phone | [[GM-21]] | Not in the trial; **Mark merged**, **Close** and **Reopen** are | Decided |
| D11 | Onboarding | M5 | The sample project and teaching empty states; no tour | Decided |
| D12 | Notifications | After the trial | None in the trial; local notifications from background fetch first if missed | Decided |

## D1 · License of this repository

| Option | For | Against |
| --- | --- | --- |
| **A. FSL-1.1-ALv2, as Genbeya** | One license across the project; the same protection against a competing commercial copy; Apache 2.0 after two years | None that matters for a trial |
| B. A permissive license (MIT, Apache 2.0) | Simplest for contributors | Misleading: the kit is Genbeya's FSL code, and the engines are ports of it |
| C. No license, private until the trial ends | Keeps every option open | Nobody else can legally try or contribute; the repository is public on GitHub |

**Recommendation: A.**

The mobile app is Genbeya in another shape. The kit bundles Genbeya's sources and the engines are translations of them, so they are derived from FSL code either way; one license says so honestly. As the copyright holder you could relicense later, but nothing argues for a different license now. If the trial makes this the official client, nothing has to change.

To do with it: a third-party notice screen, since the app ships libgit2 (GPLv2 with the linking exception, which allows shipping it inside an app), libssh2, OpenSSL and the kit's npm dependencies.

**Decided 2026-11-21.** As recommended. `LICENSE.md` is Genbeya's, unchanged; the third-party notices are in [[GM-22]].

## D2 · Where the kit is built

| Option | For | Against |
| --- | --- | --- |
| A. Here, from a pinned Genbeya checkout (the plan) | No change upstream; fast to start | This repository's CI needs Genbeya's whole toolchain, Electron included; a renderer change upstream breaks the kit only when this repository notices |
| **B. A `build:kit` target in Genbeya, the bundle a release asset** | The bridge contract lives next to the renderer it depends on; Genbeya's CI builds it; releases already carry `genbeya-web-demo.zip` and the `.vsix`, so one more asset fits | One more thing for Genbeya to keep working |
| C. An npm package (`@genbeya/kit`) | Standard versioning | A public API to maintain, and npm publishing for one consumer |
| D. Genbeya as a Git submodule | Exact source pinning | Submodules are painful, and the build problem of A remains |

**Recommendation: A for the M0 spike, then B from M1.**

The spike ([[GM-3]]) should find out what the kit needs (entry points, messages, styles) without changing Genbeya for a trial that may end. Once that is known, the bundle belongs to Genbeya, beside the VS Code webview it is built from: a change to the renderer then breaks the kit in Genbeya's own CI, not in a nightly job here, and this repository downloads one pinned file instead of building someone else's project. Upstream, the change is a pull request into `develop` with no version bump.

**Decided 2026-11-21.** As recommended. [[GM-3]] builds the kit here; [[GM-25]] moves the build into Genbeya in M1.

## D3 · Git core

| Option | For | Against |
| --- | --- | --- |
| **A. Rust with `git2` (libgit2), through flutter_rust_bridge** | One native call per composite operation (in-memory rebase, commit onto a branch's tree, change ID); full control of diff options; progress streams and cancellation; Rust is already in the Tauri shell; rockuml can join later | Cross-compiling libgit2, OpenSSL and libssh2 for Android and iOS takes setup |
| B. `git2dart` (libgit2 over Dart FFI) | Prebuilt binaries for Android and iOS; no Rust toolchain | Composite operations become many FFI calls on the Dart side; a smaller project to depend on; its coverage of in-memory rebase and SSH needs checking |
| C. gitoxide (`gix`) | Pure Rust, easy to build | Push isn't finished |
| D. Forge APIs only | No Git on the phone | Breaks "any Git host" and offline |

**Recommendation: A, with B as the fallback. The spike decides with a time limit: if the Rust core doesn't clone, commit and push on both platforms within two days of [[GM-2]], switch to B.**

The [[Call chains]] showed that the app needs Git as a few whole operations, each one atomic and off the UI thread: sync rebases in memory, retries and maybe rescues; a review reply commits onto another branch's tree; a change ID diffs with exact options and hashes. In Rust each is one function behind one bridge call; with Dart FFI the same logic is spread over many small calls, with libgit2's objects and their lifetimes on the Dart side. The setup cost is paid once, and the Tauri shell and rockuml already put Rust in the project.

**Decided 2026-11-21.** As recommended, with the two-day limit in [[GM-2]].

## D4 · Editor

| Option | For | Against |
| --- | --- | --- |
| **A. CodeMirror 6 in the kit** | The desktop's editor: Genbeya's Markdown language and the `[[`, `@` and `//` completions come with it; the platform's own text input, so autocorrect, dictation, selection handles and other scripts' keyboards behave; about 100 languages highlighted | A WebView has a start cost, and its keyboard toolbar must work with Flutter's |
| B. A native Flutter editor (re_editor or another) | Native scrolling and theming | Completions written again; editors that draw text themselves often handle selection and input methods poorly; re_editor's maintenance is unclear |
| C. Split: CodeMirror for pages, native for code | Each where it is strongest | Two editors to learn and maintain |
| D. A plain text field with a toolbar | Simplest, most native | No highlighting, no completion popups in place, slow on long files |

**Recommendation: A for pages and code, with one WebView kept warm so editing opens at once; and a plain native text field for comments, with the pickers above it. The spike ([[GM-4]]) confirms it on real phones.**

Pages and code need what the desktop's editor already has, and writing it again is exactly the duplication the kit exists to avoid. On phones, text input is the part where drawn-by-the-app editors most often feel wrong; CodeMirror 6 leaves input to the platform and was built with touch in mind. Comments are short, though: a native field opens instantly and feels like a chat app, and the pickers come from the app anyway (see [[Call chains#c6-edit-a-page]]).

**Decided 2026-11-21.** As recommended. [[GM-4]] confirms it on real phones; [[GM-13]] uses a native text field.

## D5 · Where edits go without a content branch

| Option | For | Against |
| --- | --- | --- |
| A. Always the checked-out branch | Like committing on desktop; the board is current for everyone after a sync | Pushes straight to `main` or `develop`, against many projects' rules (Genbeya's own included) |
| B. Always `mobile/<handle>`, with a pull request | Never breaks branch rules | Every status change waits for a merge; the board is stale for everyone else meanwhile |
| C. Ask once per repository (the plan) | The person who knows the rules decides | A question on the first edit, with no help for answering it |
| **D. Ask once, offer the checked-out branch, and fall back when a push is refused** | C, plus no dead end: a protected branch refuses the push, and the app offers to move the unpushed commits to `mobile/<handle>` | One more path in sync |

**Recommendation: D, and to point teams with protected branches at the content branch.**

The edits people make on a phone are board edits: small, frequent, and only useful once others see them, which a branch per edit defeats. The checked-out branch is the right default where pushing to it is allowed. Where it isn't, the host says so when the push is refused, and that is the moment to offer `mobile/<handle>`, not a guess beforehand. For a team whose code branches are protected, the real answer is Genbeya's own: keep the tasks on the [Content branch](https://github.com/genbeya/genbeya/blob/develop/docs/Architecture/Content-branch.md). Genbeya's repository is such a project: dogfooding it in the trial ([[GM-24]]) means either moving its tasks to the content branch, or living with `mobile/<handle>`.

**Decided 2026-11-21.** As recommended, in [[GM-11]]. For genbeya/genbeya itself, [[GM-24]] chooses between moving its tasks to the content branch and `mobile/<handle>`.

## D6 · The rescue branch

| Option | For | Against |
| --- | --- | --- |
| A. Keep it on the phone | Nothing visible to others | The commits exist only on the device most likely to be lost, broken or reset; the desktop can't reach them |
| **B. Push it as `mobile/rescue/<handle>-<date>`** | The edits are safe off the phone and the desktop can finish the merge; the team sees that something went wrong | Branches on the remote, which need cleaning up |
| C. Push it and open a pull request file for it | Very visible | A pull request for an accident is noise |
| D. Export a Git bundle through the share sheet | No remote branch | Manual, and easy to forget |

**Recommendation: B, with the branch namespaced by person, a banner in the app until it is resolved, and an offer to delete it once its commits are in the upstream branch.**

"Never lose an edit" isn't true while the only copy is on a phone. The rescue exists so a computer can finish what the phone couldn't, and pushing is how the computer gets it. The content goes to the same repository either way once resolved, so pushing it early reveals nothing new; a namespaced branch is easy to recognise and the app can tell when it is no longer needed. Offline, it waits on the phone and goes with the next sync.

**Decided 2026-11-21.** As recommended, in [[GM-11]].

## D7 · Clones visible to other apps

| Option | For | Against |
| --- | --- | --- |
| **A. Private to the app (the plan)** | The app is the only writer, which allows the event-driven model and the write journal; nothing else can change a file the app then commits under your name | No other editor on the phone sees the files |
| B. In shared storage (the Files app, Android's shared folders) | Other apps (Markdown editors, Git clients) can work on the same clone | Polling comes back; another app's half-written file could be committed by sync under your name; Android's shared storage is slow for Git |
| C. Private, with **Open in…** and **Save back** per file | Another app for one file when needed | Round trips by hand |

**Recommendation: A, keeping the check on resume that finds changes made outside the app, so B stays possible later.**

The [[Call chains]] rest on the app being the only writer: it is what makes large repositories cheap without polling, and what lets the journal tell an unfinished save from a change it never made. Committing changes another app made is the harm to avoid: a sync would sign them with your name. People who want another editor on a phone already have Git clients that own their clones.

**Decided 2026-11-21.** As recommended: the event-driven model of [[GM-7]] stands.

## D8 · Photos and screenshots

| Option | For | Against |
| --- | --- | --- |
| A. None in the trial | No repository growth, no format decision | The most common thing people do on a phone is missing: the whiteboard photo after a meeting |
| **B. Images in pages, the way the desktop renders them** | `![Whiteboard](images/2026-11-19-whiteboard.jpg)` next to the page is what Genbeya already shows; no new format | Images stay in the history for good |
| C. Images in tasks too, in a new attachments folder | Covers bug reports with screenshots | A new convention that only the phone knows; the desktop and the agent skill would have to learn it first |
| D. Upload to the forge or a server | No repository growth | Breaks "no server, any Git host" |

**Recommendation: B in M3 ([[GM-16]]), with three guards, and C proposed upstream as a Genbeya design question first.**

- **Shrunk** to 1600 pixels on the long side as JPEG or WebP, with the size shown before saving: a photo is in the history forever.
- **Stripped** of location and camera metadata: a photo's GPS position doesn't belong in a repository.
- **Next to the page**, in an `images` folder beside it, as Genbeya's own wiki does.

Pages already render relative images on desktop, so B adds a button, not a format. Task attachments need a place and a rule that every Genbeya client shares, and by Genbeya's lean test a new convention is decided in Genbeya's design pages, not invented by one client.

**Decided 2026-11-21.** Wider than the recommendation. In the trial, images go into pages, as in B and with its three guards ([[GM-16]], US-28 in [[User stories]]). At release, images go into tasks and pull requests too: screenshots in tasks and pull requests are coming to Genbeya itself, so the convention is decided there and this app follows it, checked by conformance cases ([[GM-26]]).

## D9 · Replies on a pull request whose file is on the source branch

| Option | For | Against |
| --- | --- | --- |
| A. Read-only until you switch to the source branch (desktop parity) | Same rule as desktop | Switching branches on a phone rewrites the checkout, may need a fetch, and interrupts what was open; reviewing an agent's work (US-19) becomes a chore |
| **B. Commit onto the source branch without switching; the next sync pushes it there** | The reply lands exactly where a desktop reviewer's would; uses the same mechanism as the content branch | Commits on someone else's branch, as the format intends but without the explicit switch |
| C. Write replies somewhere else (the content branch, the target) | No commits on the author's branch | Splits one pull request's discussion over two places; breaks the format |
| D. Only allow review when pull requests live on the content branch | No question at all | Leaves out the default layout |

**Recommendation: B, with the branch named on the reply button ("Reply on feature/GM-2-git-core"), only for branches that exist on the remote, never forced, and a rejected push rebased and retried (only the pull request file changed, so conflicts are rare).**

The desktop is read-only for other branches because one checkout can only be on one branch, not because reviewers shouldn't write there: in the checkout layout, reviewers commit to the author's branch by design. The phone's Git core can commit onto any branch without a checkout, so the reason for the restriction doesn't apply, while the cost of switching does. Naming the branch on the button keeps it from being a surprise.

**Decided 2026-11-21.** As recommended, in [[GM-21]].

## D10 · Merging pull requests on the phone

| Option | For | Against |
| --- | --- | --- |
| **A. Not in the trial, but Mark merged, Close and Reopen are** | Status changes are cheap and safe; the trial measures review first | Merging needs the desktop |
| B. Clean merges only: every condition of **Ready to merge?** met, no conflicts, a merge commit named after the pull request, then push | Closes the loop on a phone | Pushes to the target branch, usually the most protected one; the merge and the file update must match the desktop's exactly |
| C. Any merge, conflicts included | Complete | Resolving conflicts on a phone is what the plan avoids |

**Recommendation: A for the trial; B as the first candidate after it, if the dogfooding shows reviews that stop at "approved, merge later".**

A merge is the most consequential action the app could take: it changes the branch everyone builds from. The trial's question is whether reviewing on a phone works; merging is one tap more once it does, and it can be judged on real use. **Mark merged** covers merges made elsewhere (on desktop or the forge) and only records what Git already shows.

**Decided 2026-11-21.** As recommended. **Mark merged**, **Close** and **Reopen** are in [[GM-21]]; clean merges are the first candidate after the trial, judged in [[GM-24]].

## D11 · Onboarding

| Option | For | Against |
| --- | --- | --- |
| A. None | Nothing to build | The contributor without Git habits (US-3) meets terms like branch and sync unexplained |
| **B. The sample project, as on desktop** | Try everything on a repository that can't be harmed, offline; the sample engine is pure files, cheap to port; doubles as the source for store screenshots | A local repository without a remote can't show sync |
| C. A guided tour | Shows each screen | Costly to keep in step while the screens change during a trial |
| **D. Empty states and first-time sheets that teach** | Explains each idea where it first matters: what a sync badge counts, where edits go (D5), why "me" is unknown | Text to write and keep true |

**Recommendation: B and D in M5 ([[GM-22]]); no tour.**

Testers should be able to try the app without risking a real repository, and the sample already exists as pure data in Genbeya. The few ideas that are new on a phone (every save is a commit, sync, where edits go) are best explained where they first appear. A tour is the part that ages fastest while screens still change, so it waits for an official client.

**Decided 2026-11-21.** As recommended, in [[GM-27]].

## D12 · Notifications

| Option | For | Against |
| --- | --- | --- |
| **A. None in the trial; Today and pull to refresh** | Nothing in the background; no battery or data cost | Nobody is told about a mention until they open the app |
| B. Background fetch with local notifications | No server: the phone fetches and computes what's new for me, as Today does | iOS runs background work when it chooses, so timing differs by platform; battery and data |
| C. The forge's notifications | Timely | Ties a feature to GitHub or GitLab |
| D. A push service run by Genbeya | Timely everywhere | A server, which Genbeya doesn't have, by design |

**Recommendation: A for the trial; B is the first step after it if the trial shows missed reactions, starting on Android, where scheduling is dependable.**

B fits Genbeya's rules (no server, everything derived from Git) and the architecture already allows it (managers without Flutter, a lock file per clone). But in a trial its behaviour would differ between the two platforms and blur what is measured: whether opening **Today** is enough. C and D give up "any Git host" or "no server", which is a decision for Genbeya as a whole, not for a mobile trial.

**Decided 2026-11-21.** As recommended. Whether reactions were missed is collected in [[GM-24]].
