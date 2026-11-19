---
id: GM-3
title: "Spike: render Genbeya pages with the web kit"
type: spike
status: todo
priority: urgent
estimate: 3d
remaining: 3d
milestone: M0
depends_on: [GM-1]
---

Show that Genbeya's own renderer runs in a Flutter WebView, offline, as one more host of the VS Code webview protocol. See [[Architecture#the-web-kit]].

- [ ] `tool/build_kit`: check out Genbeya at `kit/GENBEYA_REF`, bundle the VS Code webview renderer (`src/shells/vscode/webview/markdown.ts`, `protocol.ts`) for the browser, copy to `kit/dist/`
- [ ] Serve it from a custom scheme in flutter_inappwebview with the desktop's content security policy; no network requests (checked)
- [ ] Send `preview` with a page and a hand-made `MarkdownContext`; get `follow` and `toggle` back
- [ ] Renders Genbeya's `docs/Guide/References.md`, a Mermaid and a PlantUML diagram (rockuml's WebAssembly), math, and `[GANTT]` on both platforms
- [ ] The WebView reports its height and scrolls inside a native list
- [ ] Note bundle size, first render time and anything the protocol lacks
- [ ] Bridge: context sent once per model version, apart from the page; every message from the kit checked (type, paths, sizes), as in [[Call chains#c5-render-a-page]]
- [ ] Checkbox toggles carry the page's version and offset, and are checked before C4's write
