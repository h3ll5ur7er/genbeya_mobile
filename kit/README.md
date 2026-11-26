# The kit

Genbeya's Markdown renderer and editor as one browser bundle, which the app shows in a web view and talks to only through messages. Genbeya builds it (`npm run build:kit`, `src/shells/kit/`) and attaches it to every release as `genbeya-kit-<version>.zip`; its protocol is documented in Genbeya's wiki ([Kit](https://github.com/genbeya/genbeya/blob/main/docs/Architecture/Kit.md)). The app's side is `lib/access/kit/` (GM-3, GM-25).

## Which kit

| File | Holds |
| --- | --- |
| `GENBEYA_KIT` | The release the app ships: its version, the zip's URL and the zip's SHA-256 |
| `GENBEYA_REF` | The commit of that release, which the conformance cases (`tool/conformance/`) use too: the renderer and the engines are of one Genbeya version |

To follow a new release: put its version, URL and the zip's SHA-256 (the release page lists each asset's) into `GENBEYA_KIT`, its commit into `GENBEYA_REF`, run the build and the test below, regenerate the conformance cases, and make the Dart side pass.

## Build and test

Needs Node 22 or 24, `unzip`, and Git for the test.

```bash
cd tool/build_kit
node build.mjs                  # the release in GENBEYA_KIT → kit/dist, checked against its manifest
node build.mjs --source develop # Genbeya's own build at a branch, tag or commit (the nightly drift job)
node test.mjs                   # Playwright (the preinstalled one) against kit/dist, 26 checks
```

`build.mjs` downloads the zip once into `tool/build_kit/.cache/` and refuses it unless its SHA-256 is the pinned one. It then refuses `kit/dist` unless every file matches `manifest.json` (SHA-256 and size, nothing missing, nothing more), the kit speaks the protocol of `lib/access/kit/kit_protocol.dart`, and a release comes from the commit in `GENBEYA_REF`.

`kit/dist` holds `kit.html` (with Genbeya's content security policy as a meta tag), `kit.js`, `chunks/`, `kit.css`, `fonts/`, `rockuml.wasm`, `LICENSES.txt` and `manifest.json`. It is not committed: see [Size](#size).

`test.mjs` runs the kit in headless Chromium with a test host that sends what the app sends (`themeMessage`, `kitContext`), serving Genbeya's own repository at `GENBEYA_REF` (cloned into `.cache/` once): references with live titles and states, embeds through `file` and `fileAt`, images, Mermaid, PlantUML, `[GANTT]` and `[BURNDOWN]`, math, `[EFFORT]`, mentions, `height`, `outline` and `reveal`, a checkbox's `toggle`, `follow`, the content security policy, invalid messages refused, `[[`, `@` and `//` completion, toolbar commands, undo, `save`, `editorState`, drafts, and the editor in Pixel 7 and iPhone 15 emulation. Screenshots go to `test/screenshots/`.

## Numbers

Genbeya 0.2.1's kit, measured with `node test.mjs` in headless Chromium on the build machine (4 cores); a phone is several times slower.

| | |
| --- | ---: |
| The release zip | 8.1 MB |
| Everything: 251 files | 19.2 MB |
| of it `rockuml.wasm` | 9.9 MB |
| Page load to `ready` | 75–140 ms |
| `preview` of Genbeya's References page to references rendered | 185–270 ms |
| `preview` of a page with Mermaid, PlantUML, GANTT and BURNDOWN to all four diagrams drawn | 0.8–1.0 s |
| `edit` to the editor shown | 80–110 ms |

## Size

At 19 MB, `kit/dist` is too large to commit with every release. The app's build runs `node tool/build_kit/build.mjs` before `flutter build`, and CI caches `tool/build_kit/.cache/` by `GENBEYA_KIT`. Smaller options exist if the app's size needs them: PlantUML diagrams as a later download (rockuml is half the kit), or leaving out Mermaid's rarely used diagram types.

## Behaviour to know

- **Undo after toolbar commands.** Genbeya 0.2.1's kit joins a toolbar step with what was typed less than half a second before into one undo step (asked of Genbeya in [Kit additions](../docs/Upstream/Kit-additions.md)).
- **Saved once sent.** After `save`, the kit reports the text as clean before the host has written it; the host keeps a failed save unsaved itself (`task_edit_screen.dart`).
- **Host messages aren't path-checked by the kit.** The kit trusts the paths of `preview` and `edit`; the app is the side that checks them, and every message the kit sends is checked by `parseFromKit`.
