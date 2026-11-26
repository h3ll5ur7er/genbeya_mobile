# Kit build

A spec for Genbeya: **`npm run build:kit`** builds Genbeya's Markdown renderer and its editor as one self-contained browser bundle, the **kit**, that any host can show in a web view and talk to through messages. Each release carries it, as it carries the web demo and the VS Code extension. The mobile app is the first host; the VS Code webviews could become the second.

> [!NOTE]
> Shipped in Genbeya 0.2.1 ([GENBEYA-68](https://github.com/genbeya/genbeya/blob/main/tasks/GENBEYA-68.md), [GENBEYA-70](https://github.com/genbeya/genbeya/blob/main/tasks/GENBEYA-70.md)); the protocol as built is in Genbeya's wiki ([Kit](https://github.com/genbeya/genbeya/blob/main/docs/Architecture/Kit.md)), and the app uses it ([[GM-25]]). This page is the spec as proposed. Nothing here changes Genbeya's file formats or its managers. The kit is a shell like the VS Code webviews: it may use the client's code, and the client doesn't depend on it.

[TOC]

## Why

The VS Code extension already renders pages and tasks with the client's pipeline outside Angular (`src/shells/vscode/webview/`), and talks to its host only through messages (`protocol.ts`). A phone needs the same, plus an editor. Building it in Genbeya rather than in each client means:

- a change to the renderer that breaks the kit fails Genbeya's own CI, not a nightly job elsewhere;
- a host downloads one pinned, checked file instead of building Genbeya's sources with its whole toolchain;
- the protocol is documented and versioned next to the code that implements it.

## What the bundle holds

```text
genbeya-kit-<version>.zip
  kit.html          the page a host loads; the content security policy as a meta tag
  kit.js            entry: bridge, renderer, editor (loaded when first asked for)
  chunks/*.js       Mermaid, KaTeX, CodeMirror languages: loaded on demand
  kit.css           styles from the app's tokens
  rockuml.wasm      PlantUML's engine
  fonts/*.woff2     Inter, JetBrains Mono, STIX Two Math
  manifest.json     what this is: version, commit, protocol, every file with its SHA-256 and size
  LICENSES.txt      the third-party licenses of everything bundled
```

`manifest.json`:

```json
{
  "name": "genbeya-kit",
  "genbeya": "0.2.0",
  "commit": "51bca82…",
  "protocol": 1,
  "files": [{ "path": "kit.js", "sha256": "…", "bytes": 182311 }]
}
```

- **Built with** the esbuild settings of `vscodeWebviewBundle` in `scripts/bundles.mjs` (browser, ESM, splitting, minified), from a new folder `src/shells/kit/`: `kit.ts` (entry), `bridge.ts` (the host interface below), `protocol.ts` (the messages), `editor.ts`.
- **What it reuses**: the renderer of `src/shells/vscode/webview/markdown.ts`, adapted (its `toggle` carries no hash, it leaves `[BURNDOWN]` and `[BASELINE]` waiting, and it passes no calendar: Genbeya should share one renderer between VS Code and the kit), and the client modules it imports (`markdown-pipeline`, `markdown-dom`, `link-target`, `file-embeds`, `references`, `mathml`); for the editor, CodeMirror with the client's editor modules that don't need Angular (`editor-setup`, `syntax`, `markdown-completion`, `reference-completion`, `mention-suggestions`, `smart-dates`, `find-widget`). Two helpers they import reach Angular (`isMac` and `MOD_KEY` from the hotkeys, `iconElement`); Genbeya should move them into plain modules, so the kit needs no shims.
- **Not in it**: the board and the task view of the VS Code webviews. A host draws those natively; the kit renders Markdown bodies and edits text.
- **Content security policy**: `CONTENT_SECURITY_POLICY` of `src/shells/content-security-policy.ts`, as the demo applies it in `index.demo.html`, without `frame-ancestors`, which a meta tag can't carry. No network: `connect-src 'self'` and nothing loaded from elsewhere.
- **Served from an origin**: the host serves the files from a custom scheme or a local server, with their media types (`application/wasm` for `rockuml.wasm`); `file://` doesn't allow the modules and WebAssembly to load.

## Talking to the host

The kit knows nothing about the host's web view. The host defines one global before `kit.html` loads, and the kit defines one:

```ts
// Set by the host, e.g. with a user script:
window.genbeyaKitHost = { post(message: string): void };
// Set by the kit once it has started:
window.genbeyaKit = { receive(message: string): void };
```

Messages are JSON strings, so every web view can carry them (Flutter's JavaScript channels, Android's `WebMessagePort`, `WKScriptMessageHandler`, VS Code's `postMessage`). The kit's first message is `ready`, with the protocol it speaks.

### Host → kit

| Message | Carries | Notes |
| --- | --- | --- |
| `context` | Parts of the `MarkdownContext`, each with its own version: `wiki`, `tasks`, `plan`, `files`, `people`, `settings`, `author` | Only parts whose version changed are sent. On a repository with 20,000 files, the file list goes once, not with every edit |
| `theme` | The app's colour and type tokens, light or dark | Applied as CSS variables |
| `preview` | A document: `page` (path, title, source, hash), `task` (as in VS Code's protocol; the kit shows its description and comments, the host its title and properties), or `markdown` (area, path, source, hash: a pull request file, a comment) | Rendered against the current context; the hash comes back with `toggle` |
| `edit` | Path, area, text, its hash, read-only or not; the language follows from the path, as `languageFor` decides | Opens the editor; the hash comes back with `save` |
| `editorCommand` | `bold`, `italic`, `heading`, `list`, `checkbox`, `link`, `insert(text)`, `undo`, `redo`, `find`, `save` | The host's keyboard toolbar drives the editor |
| `reply` | The answer to a request: `id`, `value` or `error` | As in VS Code's protocol |

### Kit → host

| Message | Carries | The host must |
| --- | --- | --- |
| `ready` | `protocol`, the kit's Genbeya version | Refuse a kit whose protocol it doesn't speak |
| `follow` | A followed link: `external`, `missing` page, `person`, or `file` with anchor; a task reference arrives as its task's file | Navigate; open web links only for `http`, `https` and `mailto` |
| `toggle` | Area, path, the **hash** of the version shown, the offset of the checkbox in the source the kit rendered (a page's file, a task's description) | Check that the file still has that hash and a checkbox at that offset, then write |
| `image`, `file`, `fileAt` | `id`, a path (and a revision) | Check the path with Genbeya's path rules and answer read-only: a data URL for images of the allowed types, text for files, with Genbeya's size limits |
| `planHistory` | `id`, an optional baseline | Answer as `content.planHistory` does, for `[BURNDOWN]` and `[BASELINE]` |
| `height` | The rendered height in CSS pixels | Size the web view inside its native screen |
| `draft` | Path, base hash, text | Keep it outside the repository |
| `save` | Path, base hash, text | Write it as `content.write` does: refused once the file changed |
| `editorState` | The path, dirty or not, the selection, whether a completion is open | Show or hide toolbar buttons |
| `error` | What the kit refused, such as an invalid message | Log it |

Completion for `[[`, `@` and `//` runs inside the kit, from the context it already has, as `src/shells/vscode/webview/completion.ts` does: no round trip per keystroke.

Everything the kit sends is untrusted input to the host: the page it rendered is repository content. The protocol keeps the kit's power to what is listed: read files through checked paths, tick a checkbox in a version it names, and save text the person typed.

### Versions

- `protocol` is a whole number. Adding a message or an optional field keeps it; removing or changing one raises it.
- A host pins a Genbeya release and checks the kit's `protocol` on `ready`.

## In Genbeya's CI and releases

- `build.yml` builds the kit on Linux next to the web demo, uploads `Genbeya-kit` as an artifact on every run, and writes its compressed size to the step summary.
- A release attaches `genbeya-kit-<version>.zip`.
- `npm run e2e:kit` loads `kit.html` in Playwright's Chromium with a test host and checks that it renders a page with references, a Mermaid and a PlantUML diagram and math, answers a checkbox with `toggle`, completes `[[`, makes no request outside its own files, and that the policy refuses an inline script.
- The protocol's message checks get unit tests like `rpc.spec.ts`.
- Genbeya's [Architecture](https://github.com/genbeya/genbeya/blob/develop/docs/Architecture.md) gets the kit as a shell, and [Development](https://github.com/genbeya/genbeya/blob/develop/docs/Development.md) the command.

## Done when

- [x] `npm run build:kit` writes `dist/kit/` with the files above, `manifest.json` listing each with its SHA-256
- [x] The kit renders `preview` messages of all three kinds and edits text with completions, through the two globals only
- [x] `context` parts are versioned and applied separately
- [x] Every message from the kit is one of the protocol's, checked by unit tests
- [x] `e2e:kit` passes in CI; the release attaches the zip
- [x] The protocol is documented in Genbeya's wiki

## Until Genbeya had it

Until 0.2.1 the mobile app built this bundle itself from `kit/src/`, importing Genbeya's sources at a pinned commit ([[GM-3]]). Since 0.2.1 (2026-11-26), `tool/build_kit` downloads the release's zip, refuses it unless its SHA-256 is the one pinned in `kit/GENBEYA_KIT`, and checks every file against `manifest.json` ([[GM-25]]); `kit/src/` is gone. The nightly drift job builds Genbeya's own kit from `develop` and tests it with the app's messages. Genbeya chose some fields differently from what the app sent; the app follows Genbeya's ([[Upstream#genbeya-s-kit-and-this-app-s]]).

## Open questions

- **The VS Code webviews as a host.** They could load the kit instead of their own bundle, leaving one renderer bundle in Genbeya; their board and task view would stay. Worth it once the kit exists?
- **Fonts.** Bundling three font families costs about a megabyte; a host could pass its own. Keep them in the kit so it renders the same everywhere?
- **Size.** The first load is about 400 kB (125 kB compressed); everything is 18 MB, of which rockuml's WebAssembly is 10 MB and Mermaid's chunks 6 MB. Should PlantUML be a later download in the app?
- **The editor's size.** CodeMirror with every language is large; `@codemirror/language-data` loads languages on demand, which the split build keeps. Is a size budget per chunk worth a CI check?
