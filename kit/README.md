# The kit

Genbeya's Markdown renderer and editor as one browser bundle that the app shows in a web view and talks to only through messages. It implements the spec in `docs/Upstream/Kit-build.md` (GM-3, GM-4); once Genbeya builds the kit itself, this folder's sources move there (GM-25).

## Build and test

Needs Node 22 or 24 and Git. The build clones Genbeya at the commit in `GENBEYA_REF` into `tool/build_kit/.cache/`, installs its dependencies without scripts, and bundles with Genbeya's own esbuild and the settings of its VS Code webview bundle.

```bash
cd tool/build_kit
node build.mjs            # → kit/dist; GENBEYA_SOURCE=<path or URL> to clone from elsewhere
node build.mjs --check    # also type-checks kit/src against Genbeya's sources
node test.mjs             # Playwright (the preinstalled one) against kit/dist
```

`kit/dist` holds the spec's layout: `kit.html` (with Genbeya's content security policy as a meta tag), `kit.js`, `chunks/`, `kit.css`, `fonts/`, `rockuml.wasm`, `LICENSES.txt` and `manifest.json` (Genbeya's version and commit, the protocol, and every file with its SHA-256 and size). It is not committed: see [Size](#size).

## Sources

| File | Does |
| --- | --- |
| `src/kit.ts` | The entry: keeps the context parts and their versions, the theme, shows previews, opens the editor on first `edit`, reports its height |
| `src/bridge.ts` | `window.genbeyaKitHost.post(text)` out, `window.genbeyaKit.receive(text)` in; requests and their replies by `id`; queues messages until the host's side exists |
| `src/protocol.ts` | The messages, `PROTOCOL = 1`, and the checks every incoming message passes |
| `src/renderer.ts` | Genbeya's renderer, adapted from the VS Code webview's `markdown.ts` (see below) |
| `src/editor.ts` | CodeMirror 6 with Genbeya's editing setup, languages, math preview and Markdown completions (`[[`, `@`, `//`, blocks); toolbar commands, drafts, save |
| `src/shims/` | Plain versions of the two helpers through which Genbeya's editor modules reach Angular |
| `src/kit.css` | Genbeya's tokens, Markdown and mention styles and fonts, sized for a phone |

## Protocol

Messages are JSON strings. The host defines `window.genbeyaKitHost = { post(text) }` before `kit.html` loads; the kit then defines `window.genbeyaKit.receive(text)` and posts `ready`.

Host → kit:

| Message | Example |
| --- | --- |
| `context` | `{"type":"context","parts":{"tasks":{"version":"t7","value":[{"id":"GM-2","path":"tasks/0 Spikes/GM-2.md","title":"Spike: Git…","status":"in-progress"}]}}}` — any of `wiki` (`{wikiRoot, nodes}`), `tasks`, `plan` (`{tasks, calendar}` or `null`), `files`, `people`, `settings` (`{statuses, hiddenColumns, types, fields}`), `author`; a part whose version didn't change is ignored |
| `theme` | `{"type":"theme","theme":"dark","tokens":{"--accent":"#7c7ff2"}}` |
| `preview` | `{"type":"preview","document":{"kind":"page","path":"docs/Home.md","title":"Home","source":"# Home…","hash":"<blob id>"}}`, or `{"kind":"task","task":<Task>}`, or `{"kind":"markdown","area":"pulls","path":"pulls/PR-1.md","source":"…","hash":"…","checkboxes":true}` |
| `edit` | `{"type":"edit","area":"wiki","path":"docs/Home.md","text":"…","hash":"<blob id>","readOnly":false}` |
| `editorCommand` | `{"type":"editorCommand","command":"bold"}` — `bold`, `italic`, `heading`, `list`, `checkbox`, `link`, `undo`, `redo`, `find`, `save`, or `{"command":"insert","text":"…"}` |
| `reply` | `{"type":"reply","id":3,"value":"data:image/png;base64,…"}` or `{"type":"reply","id":3,"error":"No such file."}` |

Kit → host:

| Message | Example |
| --- | --- |
| `ready` | `{"type":"ready","protocol":1,"genbeya":"0.1.0"}` |
| `follow` | `{"type":"follow","link":{"kind":"file","path":"docs/Getting-started.md"}}`; kinds `external`, `missing` (a page to create), `person`, `file` (task references arrive as the task's file) |
| `toggle` | `{"type":"toggle","area":"wiki","path":"docs/Plan.md","hash":"h-plan","offset":114}` — `offset` counts in the source the kit rendered: a page's file, a task's description |
| `image`, `file`, `fileAt`, `planHistory` | `{"type":"image","id":3,"path":"docs/images/board.png"}`; answered by `reply`: a data URL of PNG, JPEG, GIF, WebP, AVIF or SVG (anything else shows a placeholder), the file's text, an error naming what is missing, or `content.planHistory`'s answer as JSON |
| `height` | `{"type":"height","height":2189}` |
| `draft`, `save` | `{"type":"save","path":"docs/Notes.md","hash":"h-notes","text":"…"}` — `hash` is the base the text was edited from |
| `editorState` | `{"type":"editorState","path":"docs/Notes.md","dirty":true,"selection":{"from":57,"to":57},"completing":false}` |
| `error` | `{"type":"error","message":"An invalid preview message."}` — for the host's log |

## Numbers

Built from Genbeya 0.1.0 at `82e9002`, measured with `node build.mjs` and `node test.mjs` in headless Chromium on the build machine (4 cores); a phone will be several times slower.

| | |
| --- | ---: |
| Build | 1.1 s (after the first `npm ci` in the cache, about 20 s) |
| First load: `kit.html`, `kit.css`, `kit.js` and its static chunks | 397 kB, 125 kB gzipped |
| Everything: 251 files | 18.0 MB, 8.0 MB gzipped |
| of it `rockuml.wasm` | 9.9 MB |
| of it Mermaid's diagram chunks (largest: `elk` 1.5 MB) | about 6 MB |
| of it fonts (Inter, JetBrains Mono, STIX Two Math) | about 0.8 MB |
| Page load to `ready` | 80 ms |
| `preview` of Genbeya's References page to references rendered | 180–260 ms |
| `preview` of a page with Mermaid, PlantUML, GANTT and BURNDOWN to all four diagrams drawn (engines loaded on first use) | 0.8–0.9 s |
| `edit` to the editor shown (editor chunk loaded on first use) | 100 ms |

## Size

At 18 MB, `kit/dist` is too large to commit with every bump of `GENBEYA_REF`. Instead:

- The app's build runs `node tool/build_kit/build.mjs` before `flutter build`, and CI caches `tool/build_kit/.cache/` and `kit/dist/` by `GENBEYA_REF`. Building needs Node, Git and access to npm and Genbeya's repository.
- Once Genbeya releases the kit (GM-25), the step downloads the release's zip and checks it against `manifest.json` instead.
- Smaller options exist if the app's size needs them: PlantUML diagrams as a later download (rockuml is over half the kit), or leaving out Mermaid's rarely used diagram types.

## Where it differs from the spec

Each is a correction the spec (`docs/Upstream/Kit-build.md`) should take:

- **Hashes on documents.** `preview` documents (`page`, `markdown`) and `edit` carry the `hash` of the version they were read from; `toggle` and `save` send it back. A task carries its own `hash`. The spec's tables leave it out of `preview` and `edit`.
- **`toggle.offset`** counts in the source the kit rendered (a page's file, a task's description), not in the file; the host maps a task's offset into its file.
- **`follow`** has the kinds `external`, `missing`, `person` and `file`; task references arrive as `file` with the task's path, as in VS Code. The spec lists a `task` kind.
- **`editorCommand`** also has `italic` and `save` (the host's Save button needs a way to ask for the text).
- **`error`** is a message of the kit's, for the host's log.
- **`editorState`** names the `path`.
- **The content security policy** in the meta tag leaves out `frame-ancestors`, which only works as a header.
- **The host must serve the kit from an origin** (a custom scheme or a local server), not `file://`: `kit.js` is an ES module, and `'self'` in the policy needs an origin. MIME types matter: `.js` as `text/javascript`, `.wasm` as `application/wasm`.
- **The renderer is adapted, not imported.** VS Code's `markdown.ts` sends `toggle` without a hash, leaves `[BURNDOWN]` and `[BASELINE]` as spinners, gives plans no calendar, and takes the theme from VS Code's body classes. Once the kit lives in Genbeya, one renderer should serve both (VS Code would gain plan histories).
- **Two shims.** `client/app/editor/find-widget.ts` and `folding.ts` import `isMac`, `MOD_KEY` and `iconElement` from modules that also hold an Angular service and component. In Genbeya, moving those three into Angular-free modules would let the kit import the editor unchanged.
- **No source maps** in `kit/dist`, to keep it smaller; the VS Code bundle has linked ones.
- **A task preview** shows the description and comments only; the title and properties are the host's, drawn natively.

## Verified, and not

Verified in headless Chromium (`node test.mjs`, 24 checks): `ready`; task references with live titles and states, page, file, pinned and missing references; embeds through `file` and `fileAt` (including the error when a revision is missing); repository images through `image`; Mermaid, PlantUML, `[GANTT]` and `[BURNDOWN]` drawn as images (`[BURNDOWN]` through `planHistory`); MathML; `[EFFORT]`; mentions; `height`; a checkbox's `toggle` with the hash and the item's offset; `follow`; the policy refusing an inline script, a remote image and a fetch, and no request outside the kit's own files; invalid messages refused; `[[`, `@` and `//` completion; toolbar commands as their own undo steps; `undo`; `save` with the base hash; `editorState`; drafts; and in Pixel 7 and iPhone 15 emulation (Chromium with the device's size, touch and user agent): tapping to place the cursor, typing, completing by tapping, selecting and undoing. Screenshots: `test/screenshots/`.

Not verified, and only real phones can tell (GM-4):

- Android's WebView and iOS's WKWebView themselves: loading ES modules and WebAssembly from the app's custom scheme, the policy as each applies it, memory with Mermaid and rockuml loaded.
- Typing with real keyboards: autocorrect and suggestions, dictation, input methods for other scripts, the system's selection handles and magnifier, the keyboard covering the editor, and the host's toolbar above it. Emulation sends keys, not an input method.
- Speed on a mid-range phone, and scrolling a web view inside native screens.
- WebKit's rendering in general: the emulated iPhone runs Chromium.
- The editor's folding gutter takes about 28 pixels on a phone for prose; hiding it for Markdown is a choice to make on a device.
