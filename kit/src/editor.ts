/**
 * The kit's editor: CodeMirror 6 with the editing setup, languages and
 * Markdown completions of Genbeya's client (`[[` references, `@` people, `//`
 * dates, blocks), driven by the host's keyboard toolbar through
 * `editorCommand`. Loaded on first `edit`.
 */
import { completionStatus } from "@codemirror/autocomplete";
import { redo, undo } from "@codemirror/commands";
import { Compartment, EditorSelection, EditorState, type ChangeSpec, type Extension } from "@codemirror/state";
import { EditorView, keymap } from "@codemirror/view";
import { editingSetup, isProse, languageFor } from "genbeya/client/app/editor/editor-setup";
import { wordWrap } from "genbeya/client/app/editor/editor-keymap";
import { openFindCommand } from "genbeya/client/app/editor/find-widget";
import { markdownCompletion } from "genbeya/client/app/editor/markdown-completion";
import { mathPreview } from "genbeya/client/app/editor/math-preview";
import { referenceCandidates } from "genbeya/client/app/markdown/references";
import type { Bridge } from "./bridge";
import type { ContextParts, EditorCommand } from "./protocol";
import { markdownOptions, typeset } from "./renderer";

const isMarkdown = (path: string) => /\.(md|markdown)$/i.test(path);
/** How long typing pauses before the draft goes to the host. */
const DRAFT_DELAY = 1500;

interface Opened {
  readonly path: string;
  readonly hash: string;
  readonly base: string;
}

export class Editor {
  private view: EditorView | null = null;
  private opened: Opened | null = null;
  private readonly language = new Compartment();
  private draftTimer = 0;
  private lastState = "";

  constructor(
    private readonly host: HTMLElement,
    private readonly bridge: Bridge,
    private readonly context: () => ContextParts,
  ) {
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "hidden") this.sendDraft();
    });
  }

  /** Opens `text` of `path` for editing, replacing what was open. */
  open(path: string, text: string, hash: string, readOnly: boolean): void {
    this.sendDraft();
    this.opened = { path, hash, base: text };
    const markdown = isMarkdown(path);
    const extensions: Extension[] = [
      ...editingSetup(!isProse(path)),
      wordWrap(isProse(path)),
      this.language.of([]),
      markdown
        ? markdownCompletion({
            references: () => referenceCandidates(markdownOptions(this.context(), path).references!),
            people: () => this.context().people,
          })
        : [],
      markdown ? mathPreview(typeset) : [],
      EditorState.readOnly.of(readOnly),
      EditorView.editable.of(!readOnly),
      EditorView.contentAttributes.of({
        "aria-label": `Edit ${path}`,
        spellcheck: isProse(path) ? "true" : "false",
        autocorrect: isProse(path) ? "on" : "off",
        autocapitalize: isProse(path) ? "sentences" : "off",
      }),
      keymap.of([{ key: "Mod-s", run: () => (this.save(), true) }]),
      EditorView.updateListener.of((update) => {
        if (update.docChanged) {
          clearTimeout(this.draftTimer);
          this.draftTimer = window.setTimeout(() => this.sendDraft(), DRAFT_DELAY);
        }
        if (update.docChanged || update.selectionSet || update.transactions.length) this.reportState();
      }),
    ];
    this.view?.destroy();
    this.view = new EditorView({ parent: this.host, state: EditorState.create({ doc: text, extensions }) });
    void languageFor(path).then((support) => {
      if (support && this.opened?.path === path) this.view?.dispatch({ effects: this.language.reconfigure(support) });
    });
    this.lastState = "";
    this.reportState();
  }

  /** What the host's toolbar asks for. */
  command(command: EditorCommand): void {
    const view = this.view;
    if (!view) return;
    view.focus();
    switch (command.command) {
      case "undo":
        undo(view);
        break;
      case "redo":
        redo(view);
        break;
      case "find":
        openFindCommand(view);
        break;
      case "save":
        this.save();
        break;
      case "insert":
        view.dispatch(view.state.replaceSelection(command.text), { scrollIntoView: true });
        break;
      case "bold":
        this.wrap("**", "**", "bold");
        break;
      case "italic":
        this.wrap("_", "_", "italic");
        break;
      case "link":
        this.wrap("[", "](https://)", "text");
        break;
      case "heading":
        this.prefix(/^#{1,6} /, "## ");
        break;
      case "list":
        this.prefix(/^- (?!\[[ xX]\] )/, "- ");
        break;
      case "checkbox":
        this.prefix(/^- \[[ xX]\] /, "- [ ] ");
        break;
    }
  }

  /** Wraps each selection in `before` and `after`; an empty one gets `placeholder`, selected. */
  private wrap(before: string, after: string, placeholder: string) {
    const view = this.view!;
    view.dispatch(
      view.state.changeByRange((range) => {
        const text = view.state.sliceDoc(range.from, range.to) || placeholder;
        return {
          changes: { from: range.from, to: range.to, insert: before + text + after },
          range: EditorSelection.range(range.from + before.length, range.from + before.length + text.length),
        };
      }),
      { scrollIntoView: true },
    );
  }

  /** Adds `prefix` to the lines of the selection, or takes it away when every line has it. */
  private prefix(present: RegExp, prefix: string) {
    const view = this.view!;
    const { state } = view;
    const lines = new Map<number, string>();
    for (const range of state.selection.ranges) {
      for (let at = state.doc.lineAt(range.from).number; at <= state.doc.lineAt(range.to).number; at++) {
        lines.set(at, state.doc.line(at).text);
      }
    }
    const all = [...lines.values()].every((text) => present.test(text));
    const changes: ChangeSpec[] = [];
    for (const [number, text] of lines) {
      const line = state.doc.line(number);
      const match = present.exec(text);
      if (all && match) changes.push({ from: line.from, to: line.from + match[0].length });
      else if (!all) changes.push({ from: line.from, to: line.from + (/^(#{1,6} |- \[[ xX]\] |- )/.exec(text)?.[0].length ?? 0), insert: prefix });
    }
    view.dispatch({ changes, scrollIntoView: true });
  }

  private save() {
    if (!this.view || !this.opened) return;
    clearTimeout(this.draftTimer);
    this.bridge.post({ type: "save", path: this.opened.path, hash: this.opened.hash, text: this.view.state.doc.toString() });
  }

  private sendDraft() {
    clearTimeout(this.draftTimer);
    if (!this.view || !this.opened) return;
    const text = this.view.state.doc.toString();
    if (text === this.opened.base) return;
    this.bridge.post({ type: "draft", path: this.opened.path, hash: this.opened.hash, text });
  }

  private reportState() {
    if (!this.view || !this.opened) return;
    const { state } = this.view;
    const main = state.selection.main;
    const message = {
      type: "editorState" as const,
      path: this.opened.path,
      dirty: state.doc.toString() !== this.opened.base,
      selection: { from: main.from, to: main.to },
      completing: completionStatus(state) !== null,
    };
    const key = JSON.stringify(message);
    if (key === this.lastState) return;
    this.lastState = key;
    this.bridge.post(message);
  }

  /** The text being edited, for tests and for a host that asks before it navigates away. */
  get text(): string | null {
    return this.view?.state.doc.toString() ?? null;
  }
}
