# Experience

What the app does, screen by screen, and what it leaves to the desktop. Tasks for each part are on the board; [[Roadmap]] orders them.

[TOC]

## Navigation

```mermaid
flowchart LR
  repos[Repositories] --> home[Today]
  home --- wiki[Wiki]
  home --- tasks[Tasks]
  home --- pulls[Pull requests]
  home --- code[Code]
  search[Search, from every screen] -.-> wiki & tasks & pulls & code
  sync[Sync badge] -.-> changes[Changes]
```

- **Repositories** is the start screen: clones on the device, with their branch, unsynced edits and last sync. **Add** clones from a URL, a pasted or scanned `genbeya://` link, or a repository from the forge account you signed in with.
- **A bottom bar** inside a repository: **Today**, **Wiki**, **Tasks**, **Pull requests**, **Code**. Parts the project doesn't use, or that hide themselves until used (planning, time log, pull requests), are left out as on desktop ([Optional parts](https://github.com/genbeya/genbeya/blob/develop/docs/Design/Optional-parts.md)).
- **Search** sits in the top bar of every screen: one field for pages, tasks, pull requests and files by name, and full text below them. It plays the part of the desktop's `Ctrl+K` palette.
- **The sync badge** in the top bar shows unsynced edits and opens **Changes**.
- **Tablets** show two panes: the list or board on the left, the open page, task or pull request on the right, as the desktop's panels do.

## Today

The screen a repository opens on, and the one thing desktop doesn't have: what needs *you*, computed from the files.

- Tasks assigned to me that aren't done, the in-progress ones first, overdue dates in red.
- Pull requests waiting for my verdict, and my own with new replies or a request for changes.
- Recent mentions of my handle (`@ada`) in pages, tasks and comments.
- Checklist items with a due date (`- [ ] Send the offer 2026-10-12`) that are mine or in my tasks.

"Me" is the person whose Git name or email matches the identity set for the repository ([Writing pages](https://github.com/genbeya/genbeya/blob/develop/docs/Guide/Writing.md#who-is-in-the-list)).

## Wiki

- **The page tree** is a drawer; the current page's place shows as a breadcrumb.
- **Reading** renders pages exactly as the desktop does — references with live titles and states, embeds, callouts, Mermaid, PlantUML, math and plan macros — because it uses Genbeya's own renderer (see [[Architecture#the-web-kit]]). Images and diagrams zoom with a pinch.
- **Tapping a reference** opens the task, page or file; a red one offers to create the page.
- **Checklists** tick while reading, which saves the page, as on desktop.
- **On this page** (a sheet from the top bar) lists the headings.
- **Editing** opens the page's Markdown in the editor with a toolbar above the keyboard: heading, bold, list, checkbox, link, and pickers for `[[` references, `@` people and `//` dates, the same completions the desktop offers. Swipe or tap **Preview** to see the result.
- **New page** below the current one; moving and renaming pages, with the reference rewrite, come later.

## Tasks

- **The list** is the default on phones: grouped by state, filtered by type, epic, assignee, priority, label and milestone, with the filter chips the desktop's **Filter by** has.
- **The board** shows one column per screen on phones (swipe between columns, a strip at the top shows where you are and how many cards each has) and the whole board on tablets. Long-press a card to drag it, or to get **Move to…** with the states and epics. Swimlanes by epic on tablets.
- **A card** shows type, ID, title, assignee, priority, dates, a lock when blocked, the critical-path mark and an open pull request, as desktop cards do.
- **A task** opens full screen: title, then chips for status, type, priority, assignee, epic and labels that open bottom sheets; custom fields below them; the description rendered, with tickable checklist items; then **Comments**, **Activity** (from Git history) and, where planning is used, the five numbers, **Blocked by**, **Blocks** and float.
- **Log time** is a bottom sheet: the time spent, what for, and the new remaining effort, filled with the old value minus the time spent.
- **New task** from the board, from a column, from the app icon's quick action, or from text shared into the app from another app. Choosing a type fills the description from its template (`tasks/.templates/<type>.md`).
- **Comments** have a composer above the keyboard with `@`, `//` and `[[` pickers, signed with the Git name and time, written in the desktop's exact format; your own can be edited and deleted.

## Pull requests

Shown once the repository has a pull request file, as on desktop ([Pull requests](https://github.com/genbeya/genbeya/blob/develop/docs/Guide/Pull-requests.md)).

- **The list**: open (with drafts), merged, closed, with open to-dos counted and the filter of the desktop.
- **Conversation**: the branches, commits ahead and behind, each reviewer's latest verdict (approved, stale, changes requested, waiting), **Ready to merge?** condition by condition, the tasks it names, and the file rendered with tickable to-dos.
- **Files**: one file at a time as a unified diff (side by side only on tablets in landscape), with review threads under their lines and outdated ones marked.
- **Comment on lines**: tap a line number, drag to extend the range, then start a topic or add the range to one, with an optional suggestion (edit the lines; the app writes the `diff` block) and an optional to-do.
- **Reply, Approve, Request changes, Withdraw approval, Request review** append the desktop's signed lines, naming the commit the source branch is at.
- **New pull request** from a branch, and **Close** and **Reopen**.
- **Merging** and **Clean up…** stay on the desktop in the trial: a merge can stop for conflicts, which a phone is a poor place to resolve.

## Code

- **Files**: the repository's tree, with a filter; recent files first.
- **Viewer**: syntax highlighting, line numbers, find, wrap toggle; Markdown files can switch to the rendered preview. Images show as images.
- **Select lines → Copy reference** puts `[[src/app.ts#L10-L20]]` on the clipboard, ready for a comment or a page. Opening a reference selects its lines; a pinned one (`@v1.0`) opens that revision read-only.
- **Edit** for small changes: the same editor as for pages, with undo, find and replace, and indentation that follows the file. New file, rename and delete.
- Not a mobile IDE: no language servers, no build, no terminal.

## Search

Full text over pages, tasks, pull requests and code, with the matched line in context, grouped by kind. Hidden parts are left out, as on desktop. **Mentions of me** is a shortcut.

## Sync and changes

How a mobile edit reaches everyone else is the part that has to be right; [[Architecture#where-edits-go]] has the mechanics.

- **Every save is a commit** on the device, named after what changed and the task (`GM-12: Move to review`), signed with the repository's Git identity. A phone has no staging step to forget.
- **Sync** fetches, puts local commits on top of what others pushed, and pushes. It runs when you tap the badge, on pull to refresh in any list, and (optionally) a few seconds after an edit, as **Sync automatically** does on desktop.
- **Where commits go** is chosen per repository on its first edit:
  - **The content branch**, when the project keeps tasks, wiki or pull requests there. This is what the content branch was made for, and needs no further choice.
  - **The checked-out branch**, for repositories where people push to it directly.
  - **A branch of my own** (`mobile/<handle>`), with a pull request to open from it: for projects that never push to `main` or `develop` directly.
- **Changes** lists the unsynced commits and lets you undo the last ones before they are pushed.
- **When sync can't finish**, tasks and pull request files are merged the Genbeya way (fields one by one; comments, time log lines and replies both kept, since new ones always go last). If that still conflicts, local commits are kept on `mobile/rescue-<date>`, the branch is reset to the remote, and the app says what happened and which files differ, so the desktop can finish the job. Nothing is ever discarded.

## Sharing and links

- **Copy Genbeya link** and **Copy web link** on pages, tasks, files and pull requests, as on desktop ([Sharing](https://github.com/genbeya/genbeya/blob/develop/docs/Guide/Sharing.md)); the system share sheet sends them.
- **`genbeya://open?…` links** open in the app: the clone with that remote, or an offer to clone it. Parsing follows the desktop's strict rules.

## Signing in

- **HTTPS with a token**, kept in the system keychain (iOS Keychain, Android Keystore).
- **SSH**: the app makes an Ed25519 key on the device, shows the public key to add to the forge, and asks to trust a host's key the first time, showing its fingerprint.
- **GitHub and GitLab sign-in** through the device flow (a code to enter in the browser), as a convenience that ends in a token.
- **Git identity** per repository: name and email, filled from the forge account when there is one.

## Left to the desktop

Terminal; interactive rebase, cherry-pick, revert, stashes, resets; staging hunks and lines; resolving conflicts by hand; WSL and SSH hosts; the settings editor beyond reading (`.genbeya.yml` stays editable as a file in **Code**); generating agent files; merging pull requests and their cleanup. Each can come later if the trial shows it is missed.
