# Genbeya Mobile

A trial mobile client for [Genbeya](https://github.com/genbeya/genbeya), built with Flutter for Android and iOS (phones and tablets). It opens the same plain files as the desktop app — Markdown pages, one Markdown file per task, pull request files and `.genbeya.yml` — in a clone on the device, and syncs them with Git.

> [!NOTE]
> This repository holds the plan so far, no code yet. The goal is a prototype good enough to decide whether Genbeya gets an official second client. See [[Roadmap]] for what "good enough" means.

[TOC]

## Why a mobile client

Genbeya is the big room at the real place: the project's knowledge, plans and reviews kept where the work happens, in the repository. The real place is not always a desk. On a phone people:

- **look things up**: a page, a task's state, what a pull request is waiting for;
- **keep the board true**: move a task, tick a checklist item, log the time spent, answer a comment;
- **review**: read a diff, reply on a line, approve;
- **capture**: a new task or a note before it is forgotten;
- **fix small things**: a typo in a page, a line in a config file.

They don't run terminals, rebase interactively or refactor code there. The mobile client is for the first list and leaves the second to the desktop.

## Principles

The desktop app's rules hold here too, and a few follow from the device:

- **The files are the truth.** No server, no account, no database, no format of our own. What the app writes is byte for byte what Genbeya desktop would write: same frontmatter order, YAML comments, line endings and signed-line format.
- **Offline first.** A clone on the device; everything reads and edits without a network. Sync is an explicit, visible step.
- **Never lose an edit.** A sync that can't finish keeps local work on a branch of its own instead of discarding it.
- **Derived, not stored.** Sums, blocked marks, approvals and plans are computed from the files and Git, as on desktop.
- **Respect the project's choices.** Unused parts (`unused` in `.genbeya.yml`), the content branch layout and the approval policy apply on mobile as they do on desktop.
- **Thumb first.** One hand, short sessions, bottom sheets instead of menus, nothing that needs a hover or a right-click.

## Pages

| Page | Covers |
| --- | --- |
| [[Experience]] | What the app does and how it feels: navigation, screens, editing, sync |
| [[User stories]] | Who uses it, for what, and what has to be true when each story is done |
| [[Architecture]] | Flutter, the Git core, the web kit reused from Genbeya, the ported engines, and how the two codebases stay in step |
| [[Roadmap]] | Milestones, the live plan, how the trial is judged, risks and open decisions |
