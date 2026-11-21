---
id: GM-3
title: "Spike: render Genbeya pages with the web kit"
type: spike
status: in-progress
priority: urgent
estimate: 3d
remaining: 3d
milestone: M0
depends_on: [GM-1]
---

Show that Genbeya's own renderer runs in a Flutter WebView, offline, as one more host of the VS Code webview protocol. See [[Architecture#the-web-kit]].

- [x] `kit/src/` and `tool/build_kit` as [[Kit build]] specifies: Genbeya's sources at `kit/GENBEYA_REF`, the bundle's layout, `manifest.json` and protocol, written to `kit/dist/`
- [x] The desktop's content security policy, and no network requests (checked in Chromium)
- [ ] Serve it from a custom scheme in flutter_inappwebview on Android and iOS
- [x] Send `preview` with a page and a hand-made `MarkdownContext`; get `follow` and `toggle` back
- [x] Renders Genbeya's `docs/Guide/References.md`, a Mermaid and a PlantUML diagram (rockuml's WebAssembly), math, and `[GANTT]` on both platforms
- [ ] The WebView reports its height and scrolls inside a native list
- [x] Note bundle size, first render time and anything the protocol lacks
- [ ] Bridge: context in versioned parts, apart from the page; every message from the kit checked (type, paths, sizes), as in [[Call chains#c5-render-a-page]]
- [ ] Checkbox toggles carry the page's version and offset, and are checked before C4's write

In Chromium (`tool/build_kit/test.mjs`, 24 checks): pages render with references, embeds, Mermaid, PlantUML, math and plan macros; `toggle` carries hash and offset; the policy blocks inline scripts, remote images and fetches; nothing leaves the kit's files. About 400 kB first load (125 kB compressed), 18 MB in all (rockuml 10 MB, Mermaid 6 MB); load to `ready` 65 ms, Genbeya's References page 210 ms, a page with four diagrams 0.8 s. Seen in the screenshots: PlantUML stays white in dark mode, and `[EFFORT]` is wider than a phone. Left: the WebView on real phones.
