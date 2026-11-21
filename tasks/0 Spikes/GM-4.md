---
id: GM-4
title: "Spike: compare editors on the device"
type: spike
status: in-progress
priority: high
estimate: 2d
remaining: 2d
milestone: M0
depends_on: [GM-3]
---

Confirm the decided editor, CodeMirror 6 in the kit for pages and code, against a native one on real phones (D4 in [[Decisions]]). Comments use a native text field. See [[Architecture#the-web-kit]].

- [x] CodeMirror 6 in the kit, with Genbeya's Markdown language and `[[` completion
- [ ] re_editor (or another maintained native editor) with Markdown highlighting
- [ ] Try each on a 2,000-line Markdown file: typing, autocorrect, the system keyboard's suggestions, selection handles, undo, scrolling, a toolbar above the keyboard
- [ ] Confirm CodeMirror 6 on both phones; only if it fails, the code editor goes native, and record it in [[Architecture]]

In Chromium with Pixel 7 and iPhone 15 emulation: tap, type, complete by tapping, select and undo work; toolbar commands, drafts and save with the base hash too. Autocorrect, input methods, selection handles and the keyboard toolbar can only be judged on real phones.

Spike screens (2026-11-21): **Editor (kit)** opens CodeMirror 6 in the kit full screen with Genbeya's completions, a native toolbar above the keyboard and a status line (selection, drafts, save); **Editor (native)** opens re_editor 0.10 on the same text with the same toolbar, without completions. Both switch to a 2,000-line page. The first build had no editor screen at all (the tile led nowhere); this one is to try on the Pixel.

On the Pixel: the kit's editor opens and highlights Markdown, but its toolbar sat under Android's navigation bar; re_editor's plain text was nearly invisible (its default text colour on the app's dark background). Both fixed: the toolbar stays in the safe area, and re_editor takes the app's colours.
