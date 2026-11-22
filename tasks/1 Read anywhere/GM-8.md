---
id: GM-8
title: Read the wiki
type: feature
status: review
priority: high
estimate: 3d
remaining: 0d
milestone: M1
depends_on: [GM-3, GM-6, GM-7]
ios: to-check
---

Pages exactly as the desktop shows them. See [[Experience#wiki]].

- [x] Page tree drawer, breadcrumb, home page first
- [x] Page body in the kit with a real `MarkdownContext`; images and embeds served through checked paths (`RepositorySession`: each path from its area's commit; plan macros wait for [[GM-18]])
- [x] Tapping references opens tasks (a task view until [[GM-9]]'s screen), pages (at the section) and web links; files say they open in Code ([[GM-17]]); red references say creating pages comes with [[GM-16]]
- [x] **On this page** sheet: the kit sends each page's `outline` and scrolls to a heading on `reveal` (two messages added to the protocol, which stays 1)
- [x] Pinch to zoom diagrams and images (the web view zooms natively)
- [x] Opens in under a second for Genbeya's own wiki on a mid-range phone ("basically instant" on the Pixel)
- [x] Completions for `[[`, `@` and `//` inside the kit, from its context ([[Kit build]]): in the kit's editor since [[GM-4]]

Built (2026-11-22): opening a clone shows a shell with **Wiki**, **Tasks** (until [[GM-9]]) and **About**. The wiki opens on the home page, full screen in the kit; the drawer holds the page tree and how long the last page took to open, the app bar the breadcrumb and **On this page**; back goes to the previous page. Checkbox ticks say they come with editing ([[GM-11]]). To measure on the phone: opening a page of Genbeya's wiki.

On the Pixel (2026-11-22): the wiki, its page tree, references and **On this page** work. Pinch to zoom works, references and back too, and pages open "basically instant". The model reads genbeya/genbeya (65 tasks, 31 pages, 789 files) in 262 ms.
