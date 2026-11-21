# User stories

What people will use the app for, as stories with what has to be true when they are done. They test the plan in [[Experience]]: every story names the tasks that build it, and the trial ([[GM-24]]) walks through every **Must** story on real phones.

[TOC]

## Who uses it

| Role | Is | Reaches for the phone when |
| --- | --- | --- |
| **Maintainer** | Leads the project, plans milestones, reviews most pull requests | Between meetings, on the way home, when a question comes up away from the desk |
| **Team developer** | Works the board on several branches with others | At stand-up, on the commute, when a comment needs an answer |
| **Solo developer with agents** | Lets coding agents write code, tasks and pull request files, and reviews what they did | Away from the desk while the agents work |
| **Contributor without Git habits** | Designer, product owner, writer: reads the wiki, files tasks, comments, never opens a terminal | Most of the time; the phone may be their main client |
| **Newcomer** | Joined the project this week | Reading the wiki in spare minutes |

Priorities are for the trial: **Must** stories decide whether it succeeds, **Should** stories are expected, **Could** stories are welcome if time allows.

## Getting a repository onto the phone

### US-1 · Clone a private repository over SSH

**As a** team developer, **I want** to clone our private repository on my phone with an SSH key, **so that** I don't have to make a token with write access to everything.

- The app makes an Ed25519 key on the device and offers its public key to copy or share.
- The first connection shows the host key's fingerprint and asks once; a changed host key later stops the sync and says so.
- The clone is shallow and single-branch by default, shows progress, can be cancelled, and states its size when done.

**Must** · [[GM-2]], [[GM-6]]

### US-2 · Open a link a teammate sent

**As a** team developer, **I want** a `genbeya://` link from our chat to open the task in my clone, **so that** "can you look at GENBEYA-48?" takes one tap.

- The link opens the item in the clone whose remote matches, on whatever branch is checked out.
- Without such a clone, the app offers to clone it and opens the item afterwards.
- A malformed link, or one naming a local path, is refused with a reason; a link never runs anything.

**Must** · [[GM-10]]

### US-3 · Sign in without knowing what a token is

**As a** contributor without Git habits, **I want** to sign in with my GitHub or GitLab account and pick the repository from a list, **so that** I can start without learning about tokens and keys.

- The device flow shows a code and opens the browser; the app ends up with a token in the system keychain.
- My Git name and email are filled in from the account and can be changed per repository.

**Should** · [[GM-6]]

### US-29 · Try it without a repository of my own

**As a** tester, **I want** to try every screen on a repository that nothing depends on, **so that** I can learn the app without fear of breaking a real board.

- **Try the sample project** on the start screen makes Genbeya's sample repository on the phone, the same files and commits as the desktop's, without a remote.
- Sync explains that the sample has no remote; everything else works.
- The first time an idea matters (the sync badge, where edits go, why "me" is someone), a short sheet explains it, once.

**Should** · [[GM-27]]

## Staying informed

### US-4 · See what needs me this morning

**As a** team developer, **I want** to open the app and see what is waiting for me, **so that** I know where to start before I reach my desk.

- **Today** lists my open tasks (in-progress first, overdue dates in red), pull requests waiting for my verdict, mentions of my handle, and checklist items due soon.
- "Me" comes from the repository's Git identity, matched as the desktop matches people; when it matches no one, the screen explains how to fix it.
- Pull to refresh syncs first, then recomputes.

**Must** · [[GM-14]], [[GM-11]]

### US-5 · Look up a decision during a meeting

**As a** maintainer, **I want** to find the page where a decision is written down while someone asks about it, **so that** the answer comes from the wiki, not from memory.

- Search finds pages by title as I type and by full text below, with the matched line shown.
- The page renders as on desktop: references with live titles and states, callouts, tables, Mermaid and PlantUML diagrams, math.
- It works offline, and opens in under a second for this project's wiki on a mid-range phone.

**Must** · [[GM-8]], [[GM-10]], [[GM-3]]

### US-6 · Follow a reference

**As a** newcomer, **I want** to tap `[[GM-12]]`, `[[Architecture]]` or `[[lib/app.dart#L10-L20]]` in a page, **so that** I can explore the project the way its authors linked it.

- A task opens its screen, a page opens the page at its section, a file opens the viewer with those lines selected.
- A pinned reference (`@v1.0`) opens the file at that revision, read-only, with a way to the current version.
- A red reference offers to create the page; a dashed one says the file isn't there.

**Must** · [[GM-8]], [[GM-17]]

### US-7 · Check where a milestone stands

**As a** maintainer, **I want** to open our release plan page and see the timeline, the effort and what is blocked, **so that** I can answer "are we on track?" from anywhere.

- `[GANTT]`, `[EFFORT]`, `[DEPENDENCIES]` and `[BURNDOWN]` render from the tasks as on desktop, and a tap on a task opens it.
- Blocked tasks show a lock on the board, critical ones their mark.
- Where the clone is too shallow for a burndown, the app deepens it and says so.

**Should** · [[GM-18]], [[GM-8]]

### US-8 · Read and work offline

**As a** team developer on a train without signal, **I want** to read and edit as usual, **so that** a dead zone doesn't stop me.

- Everything reads offline; edits become commits on the device.
- The sync badge counts what isn't pushed yet; the next sync sends it.
- Nothing asks for the network until I sync.

**Must** · [[GM-11]]

## Keeping the board true

### US-9 · Move a task after stand-up

**As a** team developer, **I want** to move my task to review with my thumb, **so that** the board is right before I forget.

- Long-press and drag a card to another column, or choose **Move to…**; on the task screen, the status chip opens the states.
- The file changes only in `status`: other fields, their order, YAML comments and line endings stay as they are.
- The change is one commit named after the task (`GM-12: Move to review`).

**Must** · [[GM-12]], [[GM-11]]

### US-10 · Tick a checklist item

**As a** team developer, **I want** to tick a step in a task's or a page's checklist while reading it, **so that** progress shows without opening an editor.

- Ticking saves the file; only that box changes.
- A dated item turns neutral once ticked.

**Must** · [[GM-12]], [[GM-16]]

### US-11 · Capture a task from another app

**As a** contributor without Git habits, **I want** to share a message or a screenshot description from another app into Genbeya as a new task, **so that** a bug report from a customer call doesn't get lost.

- The share sheet offers the app; I choose the repository, the type and the epic, and the shared text becomes the description.
- Choosing a type fills the description from its template; the task gets the next free ID.
- The app icon's quick action **New task** does the same without shared text.

**Should** · [[GM-12]]

### US-12 · Answer a comment

**As a** team developer, **I want** to reply to a question on my task and mention the person who asked, **so that** they get their answer without waiting for me to be at my desk.

- The composer offers people after `@`, dates after `//` and tasks, pages and files after `[[`.
- The comment is signed with my Git name and the local time with its offset, in the desktop's exact format, and goes last.
- I can edit or delete my own comments, never others'.

**Must** · [[GM-13]]

### US-13 · Log the time at the end of the day

**As a** team developer on a project that logs time, **I want** to log what I spent and what is left, **so that** the plan stays honest without a timesheet.

- **Log time** asks for the time, what for and the new remaining effort, filled with the old value minus the time spent.
- It adds one line to `## Time log` and updates `remaining`, in one commit.
- The option only shows where the project logs time.

**Should** · [[GM-18]]

### US-14 · Reassign or reprioritise

**As a** maintainer, **I want** to change a task's assignee, priority, epic or milestone from its screen, **so that** I can triage the backlog in a waiting room.

- Each chip opens a bottom sheet: people for the assignee, the configured types, the epics (moving the file), the milestone's options.
- Custom fields are edited by their kind: dates with a date picker, effort as `16h` or `2d`, task lists as references.

**Must** · [[GM-12]]

## Writing

### US-15 · Fix a typo while reading

**As a** newcomer, **I want** to fix a mistake I notice in a page right there, **so that** the next reader doesn't trip over it.

- **Edit** opens the page's Markdown at the place I was reading.
- **Save** writes the file with its line endings and makes one commit; **Cancel** asks before throwing edits away.
- Unsaved edits survive the app going to the background.

**Must** · [[GM-16]]

### US-16 · Take meeting notes

**As a** maintainer, **I want** to write notes into a new page during a meeting, linking the tasks we discuss and the dates we agree on, **so that** the outcome is in the wiki before the meeting ends.

- **New page** below the current one; the toolbar above the keyboard has headings, lists, checkboxes and the `[[`, `@` and `//` pickers.
- Checklist items with dates and mentions work as on desktop, so they show up in people's **Today**.

**Should** · [[GM-16]]

### US-28 · Add a photo of the whiteboard

**As a** maintainer, **I want** to add a photo of the whiteboard to the meeting notes, **so that** the sketch stays with the decision it led to.

- **Photo** takes a picture or picks one, shrinks it to 1600 pixels, strips location and camera data, and shows its size before saving.
- The image goes into the wiki's `images/` folder and its reference into the page, in one commit, as [[Attached images]] describes; the page renders it as the desktop does.

**Should** · [[GM-16]]

### US-17 · Point someone at the code

**As a** team developer, **I want** to select lines in a file and paste a reference to them into a comment, **so that** "the bug is here" is exact.

- Select lines in the viewer, **Copy reference** puts `[[path#L10-L20]]` on the clipboard.
- The comment renders it as the lines' path, and tapping it opens them.

**Should** · [[GM-17]]

### US-18 · Fix one line of a file

**As a** solo developer with agents, **I want** to correct a wrong value in a config file or a README from my phone, **so that** a trivial fix doesn't wait for my laptop.

- The code viewer has **Edit**, with undo, find and replace, and the file's indentation.
- Saving makes one commit; nothing builds or runs.

**Could** · [[GM-17]]

## Review

### US-19 · Review an agent's pull request on the go

**As a** solo developer with agents, **I want** to review the pull request an agent opened and tell it what to change, **so that** it keeps working while I'm away from the desk.

- The pull request shows its description, the tasks it names, and each file's diff against where the branches meet.
- I can tap line numbers, drag to a range, and start a topic with a comment, a suggestion and a to-do.
- **Request changes** adds my verdict naming the source's commit; after a sync, the agent finds my remarks in the pull request file.

**Must** · [[GM-19]], [[GM-20]], [[GM-21]]

### US-20 · Approve once my remarks are addressed

**As a** maintainer, **I want** to approve a pull request after its author answered my remarks, **so that** they can merge without waiting for me.

- New replies and commits since my last verdict are visible, and outdated threads are marked.
- **Approve** names the commit the source is at; the header then shows my approval, and later shows it as stale if the code changes again.
- Approvals compare the change, so a rebase that keeps the code keeps my approval, as on desktop.

**Must** · [[GM-19]], [[GM-21]]

### US-21 · See why a pull request isn't ready

**As a** team developer, **I want** to see what still keeps my pull request from merging, **so that** I know whom to nudge.

- **Ready to merge?** lists approvals that still count, open requests for changes, open to-dos and conflicts, each on its own.
- Each reviewer shows their latest verdict, and "committed by" when someone else wrote it.

**Should** · [[GM-20]]

## Sync and safety

### US-22 · Sync after a teammate changed the same task

**As a** team developer, **I want** my status change and a teammate's new comment on the same task to both survive the sync, **so that** working on the board at the same time is safe.

- Changes to different frontmatter keys merge; comments, time log lines and replies from both sides are kept in time order.
- The result is what the desktop would show after merging the same edits.

**Must** · [[GM-11]]

### US-23 · Never lose an edit when sync can't finish

**As a** team developer, **I want** a sync that can't be resolved on the phone to keep my work safe, **so that** I can trust the app with real edits.

- Local commits are kept on `mobile/rescue/<handle>-<date>`, the branch is reset to the remote, and a banner lists the files that differ until the rescue's commits are upstream; then the app offers to delete it.
- The rescue branch is pushed, so I can finish the merge on the desktop.
- No sync ever discards a commit.

**Must** · [[GM-11]]

### US-24 · Work on a project that never pushes to main

**As a** team developer on a project with protected branches, **I want** my mobile edits to go to a branch of my own, **so that** I follow the project's rules.

- When the host refuses a push to the checked-out branch, the app offers to move the commits not pushed yet to `mobile/<handle>`.
- With my own branch, the app offers **New pull request** from it.

**Should** · [[GM-11]], [[GM-21]]

### US-25 · Share the board through the content branch

**As a** team developer on a project that keeps its tasks on Genbeya's content branch, **I want** the phone to show and change the same board as everyone's desktop, **so that** the board doesn't depend on a branch.

- The areas `.genbeya-content` puts on the branch are read from it; edits are committed onto it and pushed with the next sync.
- The wiki can stay with the code at the same time.

**Should** · [[GM-15]]

### US-26 · Look around a repository I don't trust

**As a** newcomer, **I want** to clone an open-source project I don't know and read its wiki safely, **so that** curiosity can't harm my phone or my accounts.

- Pages can't run scripts or load remote content; links leave the app only for `http`, `https` and `mailto`, through the system browser.
- No repository setting runs anything on clone or sync.

**Must** · [[GM-3]], [[GM-8]]

## Tablets

### US-27 · Plan on a tablet

**As a** maintainer, **I want** the full board with swimlanes and the task beside it on a tablet, **so that** a planning session on the couch is as good as at the desk.

- The whole board shows, with swimlanes by epic; the open task sits in a second pane.
- The diff of a pull request shows side by side in landscape.

**Could** · [[GM-22]]

## A day with the app

The stories combine into moments, which is how the trial should try them:

1. **The commute.** Open the app on the train (US-8): **Today** (US-4) shows a question on a task; answer it with a mention (US-12), move another task to review (US-9), sync when the signal is back.
2. **Between meetings.** Someone asks about a decision: search, open the page, show the diagram (US-5); spot a typo and fix it (US-15); file a task from what came up (US-11).
3. **The evening.** The agents opened a pull request: review it, comment on two ranges, request changes (US-19); log the day's time (US-13).

## Not for the trial

What people might ask for, deliberately left out, so the trial stays a test of the core ([[Experience#left-to-the-desktop]]):

- Merging a pull request, and **Clean up…**: a merge can stop for conflicts, a phone is a poor place to resolve them.
- Resolving conflicts by hand, beyond the Genbeya merge and the rescue branch.
- Running tests, builds or a terminal.
- Interactive rebase, cherry-pick, stashes, staging lines.
- Editing settings through forms (`.genbeya.yml` stays editable as a file).
- Background sync while the app is closed, which iOS doesn't allow reliably.
- Images in tasks and pull requests: at release, following the convention Genbeya will have ([[GM-26]]).
- Notifications when a teammate pushes: nothing tells the phone without a server, and Genbeya has none.
