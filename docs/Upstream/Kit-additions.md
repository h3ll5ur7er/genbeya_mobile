# Kit additions

Three additions to Genbeya's kit (`src/shells/kit/`, [GENBEYA-68](https://github.com/genbeya/genbeya/blob/develop/tasks/GENBEYA-68.md)) that the mobile app needs before it can use the kit instead of building its own ([[GM-25]]). All three only add a message or an optional field, so `KIT_PROTOCOL` stays `1` ("adding a message or an optional field keeps it"). They are written for Genbeya's repository; the mobile app's kit (`kit/src/` here) already does each of them, so its code is a reference, not something to copy blindly.

The mobile app adapts to everything else Genbeya chose (`theme.mode`, tokens without `--`, the `wiki`, `settings` and `plan` parts, `readOnly` always sent): see [[Upstream#genbeya-s-kit-and-this-app-s]].

## 1. `outline`: the headings of the document rendered

**Why.** The app's wiki has **On this page**, a sheet listing the page's headings that jumps to one. It needs the headings as the renderer made them, with the ids it gave them; working them out from the Markdown in the app would be a second slugger that drifts from Genbeya's. The app also takes `outline` as the sign that a page has finished rendering, to time how long opening a page takes.

**Message** (kit → host), added to `FromKit`:

```ts
export interface OutlineHeading {
  /** 1 to 6. */
  readonly level: number;
  /** The heading's text, trimmed, at most 300 characters. */
  readonly text: string;
  /** The element id the renderer gave the heading, at most 300 characters; `reveal` takes it. */
  readonly id: string;
}

  /** The headings of the document just rendered, in document order, for the host's "On this page". */
  | { readonly type: "outline"; readonly path: string; readonly headings: readonly OutlineHeading[] }
```

**When.** After every `preview` of kind `page` or `markdown` has rendered, including when a new `context` re-renders it, once per render. `path` is the document's path, so a host can drop an outline that arrives for a document it no longer shows. Not sent for `task` previews (the app draws a task's structure itself). A document without headings sends `headings: []`, which also tells the host rendering finished.

**What counts.** Every `h1` to `h6` with an `id` in the rendered document, in document order, at most 500. Headings inside embedded content count as the renderer puts them in the page; headings without an id are left out, since nothing can reveal them.

**Checks.** `checkFromKit` accepts it: `path` a string, `headings` a list of at most 500 objects with a whole `level` from 1 to 6 and string `text` and `id`.

The mobile app's version: `postOutline` in `kit/src/kit.ts`.

## 2. `reveal`: scroll to a heading

**Why.** A link to `[[Page#Heading]]` arrives at the host as `follow` with `kind: "file"` and an `anchor`; the host opens the page and then must scroll to the heading. **On this page** needs the same. Only the kit knows where the heading is.

**Message** (host → kit), added to `ToKit`:

```ts
  /** Scrolls the document shown to the element with this id (an `outline` heading's, or a link's anchor). */
  | { readonly type: "reveal"; readonly id: string }
```

**Behaviour.** While a preview is shown, find the element whose `id` is exactly `id` and scroll it to the top (`scrollIntoView({ block: "start" })`); look it up with `CSS.escape` or an attribute selector, never by building a selector from the raw id. No element, or the editor shown: nothing happens, no error. A host sends `reveal` after the `outline` of the document it means, so the element exists.

**Checks.** `parseToKit` accepts it when `id` is a string of at most 300 characters; anything else answers `error` as other invalid messages do.

**The anchor of `follow`.** `follow`'s `anchor` is the fragment of the link's `href` as the renderer writes it (`resolveHref` in `link-target.ts`), which for `[[Page#Heading]]` is the id the heading gets when that page renders. The mobile app relies on that and sends the anchor as it arrives; nothing about `follow` changes.

The mobile app's version: the `reveal` case in `kit/src/kit.ts` and `parseToKit` in `kit/src/protocol.ts`.

## 3. `checkboxes` on a Markdown preview

**Why.** A `preview` of kind `markdown` shows any other Markdown: a pull request's file, whose to-dos tick, and, later, a single comment or a reply, whose checkboxes must not (desktop doesn't tick checkboxes in comments either). Today the kit makes every Markdown preview's checkboxes interactive, so a host can't show a comment without offering ticks it would then have to refuse.

**Field**, optional, added to the `markdown` kind of `KitDocument`:

```ts
  | {
      readonly kind: "markdown";
      readonly area: ContentArea;
      readonly path: string;
      readonly source: string;
      readonly hash: string;
      /** Whether its checkboxes tick, answered by `toggle`. Leaving it out keeps them ticking, as now. */
      readonly checkboxes?: boolean;
    };
```

**Behaviour.** `checkboxes: false` renders the checkboxes read-only, as a task's comments are rendered now (`checkboxes: false` in `showTask`), and sends no `toggle` for them. Absent or `true`: as today. Pages always tick; tasks as now (description yes, comments no).

**Default.** Absent means `true` here, so the kit keeps doing what 0.2.1 would ship. (The mobile app's own kit defaults to `false`; the app will always send the field, so either default works for it. `true` is the one that changes nothing in Genbeya.)

**Checks.** `parseToKit`: `checkboxes` absent or a boolean.

## Tests

- `protocol.spec.ts`: `outline` passes `checkFromKit` and one with a level of 7, 501 headings or a missing `path` doesn't; `reveal` passes `parseToKit`, one with a number or a 301-character id answers `error`; a `markdown` preview with `checkboxes: false`, `true` and absent passes, with `"no"` doesn't.
- `e2e:kit`: a page with three headings (one nested, one with characters the slugger changes) posts `outline` with their levels, texts and ids after `preview`, and again after a `context` that re-renders it; `reveal` with the second id scrolls its heading to the top; `reveal` with an unknown id does nothing and posts no `error`; a `markdown` preview with `checkboxes: false` posts no `toggle` when its checkbox is clicked, and one without the field does.
- The protocol's page in Genbeya's wiki ([Kit](https://github.com/genbeya/genbeya/blob/develop/docs/Architecture/Kit.md)) lists the two messages and the field.

## Until Genbeya has it

The mobile app keeps building its own kit from `kit/src/` at the release pinned in `kit/GENBEYA_REF`. Once a Genbeya release has these three, [[GM-25]] adapts the host to Genbeya's fields and switches to that release's zip.
