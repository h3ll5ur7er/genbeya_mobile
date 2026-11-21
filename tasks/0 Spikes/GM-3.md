---
id: GM-3
title: "Spike: render Genbeya pages with the web kit"
type: spike
status: review
priority: urgent
estimate: 3d
remaining: 0d
milestone: M0
depends_on: [GM-1]
ios: to-check
---

Show that Genbeya's own renderer runs in a Flutter WebView, offline, as one more host of the VS Code webview protocol. See [[Architecture#the-web-kit]].

- [x] `kit/src/` and `tool/build_kit` as [[Kit build]] specifies: Genbeya's sources at `kit/GENBEYA_REF`, the bundle's layout, `manifest.json` and protocol, written to `kit/dist/`
- [x] The desktop's content security policy, and no network requests (checked in Chromium)
- [x] Serve it to a web view: `webview_flutter` and a loopback server under a random path (`lib/access/kit/`), host messages checked and tested; builds into the Android app
- [x] Try it on a real Android phone (Pixel 9 Pro XL, 2026-11-21): the spike screen renders references with their states, mentions, dates, a checklist, a callout, a table, math, Mermaid and PlantUML offline; ready after 543 ms
- [x] Send `preview` with a page and a hand-made `MarkdownContext`; get `follow` and `toggle` back
- [x] Renders Genbeya's `docs/Guide/References.md`, a Mermaid and a PlantUML diagram (rockuml's WebAssembly), math, and `[GANTT]` on both platforms
- [x] The WebView reports its height and scrolls inside a native list (on the Pixel)
- [x] Note bundle size, first render time and anything the protocol lacks
- [x] Bridge: context in versioned parts, apart from the page; every message from the kit checked (type, paths, sizes), as in [[Call chains#c5-render-a-page]] (`lib/access/kit/kit_host.dart`)
- [x] Checkbox toggles carry the page's version and offset, and are checked before C4's write

In Chromium (`tool/build_kit/test.mjs`, 24 checks): pages render with references, embeds, Mermaid, PlantUML, math and plan macros; `toggle` carries hash and offset; the policy blocks inline scripts, remote images and fetches; nothing leaves the kit's files. About 400 kB first load (125 kB compressed), 18 MB in all (rockuml 10 MB, Mermaid 6 MB); load to `ready` 65 ms, Genbeya's References page 210 ms, a page with four diagrams 0.8 s. Seen in the screenshots: PlantUML stays white in dark mode, and `[EFFORT]` is wider than a phone. Left: the WebView on real phones.

On the Pixel: a table's border and header stopped short of its box (fixed: the box fits its rows); PlantUML stays white in dark mode, and Mermaid's dark boxes with light shadows look harsh: both for the theme work later.

The host's bridge (2026-11-21): `KitHost` keeps the kit's context in parts and sends a part again only when its version changes (everything again when the kit restarts); it answers image, file and history requests read-only within Genbeya's limits (2 MB of text, 10 MB per image, the seven image types) and passes on no internal error text; a save or draft must name the file open, in its version. A ticked checkbox reaches the write only if it names the document shown, in the version shown, with checkboxes that tick, and a task list item starts at its offset (`isCheckboxItemAt`): Genbeya ticks the first checkbox at or after any offset, which is fine for its own UI but too lenient for messages from a web view. The write then uses Genbeya's rule, so the bytes are the desktop's: 266 conformance cases tick checkboxes in pages (offsets counted after the frontmatter, as `wiki-page.ts` does) and in task descriptions, against Genbeya's own `toggleCheckboxAt`. The spike screen now ticks its checkboxes for real, in memory, and shows each new version. Left for the iPhone (`ios: to-check`); a checkbox inside a code block still passes the item check if a forged message names it, which only flips a character in the version shown.

