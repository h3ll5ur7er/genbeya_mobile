/**
 * The kit's entry (docs/Upstream/Kit-build.md): Genbeya's renderer and editor
 * in a web view, talking to its host only through messages. It renders what
 * the host sends against the context the host keeps it up to date with, and
 * reports links, ticked checkboxes, edits and its height.
 */
import type { Task } from "genbeya/contracts/model";
import { Bridge } from "./bridge";
import type { Editor } from "./editor";
import { PART_NAMES, PROTOCOL, type ContextParts, type PartName, type PreviewDocument, type ToKit } from "./protocol";
import { Renderer } from "./renderer";

declare const GENBEYA_VERSION: string;

const context: { -readonly [K in PartName]: ContextParts[K] } = {
  wiki: { wikiRoot: "docs", nodes: [] },
  tasks: [],
  plan: null,
  files: [],
  people: [],
  settings: { statuses: [], hiddenColumns: [], types: [], fields: [] },
  author: null,
};
const versions = new Map<PartName, string>();

const preview = document.getElementById("preview")!;
const editorHost = document.getElementById("editor")!;
let shown: PreviewDocument | null = null;
let editor: Promise<Editor> | null = null;
let mode: "preview" | "edit" = "preview";

const bridge = new Bridge(receive);
const renderer = new Renderer(bridge, () => versions.get("plan") ?? "");
renderer.listen(preview);

function receive(message: Exclude<ToKit, { type: "reply" }>) {
  switch (message.type) {
    case "context": {
      let changed = false;
      for (const name of PART_NAMES) {
        const part = message.parts[name];
        if (!part || versions.get(name) === part.version) continue;
        versions.set(name, part.version);
        (context as Record<PartName, unknown>)[name] = part.value;
        changed = true;
      }
      // References show live titles and states: what is shown follows the context.
      if (changed && shown && mode === "preview") show(shown);
      return;
    }
    case "theme":
      document.documentElement.dataset["theme"] = message.theme;
      for (const [name, value] of Object.entries(message.tokens ?? {})) document.documentElement.style.setProperty(name, value);
      if (shown && mode === "preview") show(shown);
      return;
    case "preview":
      shown = message.document;
      setMode("preview");
      return show(message.document);
    case "edit":
      setMode("edit");
      editor ??= import("./editor").then(({ Editor }) => new Editor(editorHost, bridge, () => context));
      void editor.then((open) => open.open(message.path, message.text, message.hash, message.readOnly ?? false));
      return;
    case "editorCommand":
      void editor?.then((open) => open.command(message));
      return;
    case "reveal":
      if (mode !== "preview") return;
      preview.querySelector(`[id="${CSS.escape(message.id)}"]`)?.scrollIntoView({ block: "start" });
      return;
  }
}

function setMode(next: "preview" | "edit") {
  mode = next;
  preview.hidden = next !== "preview";
  editorHost.hidden = next !== "edit";
  document.body.dataset["mode"] = next;
}

function show(document: PreviewDocument) {
  try {
    if (document.kind === "task") return showTask(document.task);
    const page = element("article", "kit-page");
    preview.replaceChildren(page);
    const area = document.kind === "page" ? "wiki" : document.area;
    const checkboxes = document.kind === "page" ? true : (document.checkboxes ?? false);
    renderer.render(page, document.source, { path: document.path, area, hash: document.hash, checkboxes }, context);
    postOutline(page, document.path);
  } catch (error) {
    bridge.post({ type: "error", message: `Couldn't render ${documentPath(document)}: ${error instanceof Error ? error.message : String(error)}` });
  }
}

/** The rendered headings with their ids, at most 500, for the host's "On this page". */
function postOutline(root: HTMLElement, path: string) {
  const headings = [...root.querySelectorAll<HTMLElement>("h1[id], h2[id], h3[id], h4[id], h5[id], h6[id]")].slice(0, 500).map((heading) => ({
    level: Number(heading.tagName.slice(1)),
    text: (heading.textContent ?? "").trim().slice(0, 300),
    id: heading.id.slice(0, 300),
  }));
  bridge.post({ type: "outline", path, headings });
}

const documentPath = (document: PreviewDocument) => (document.kind === "task" ? document.task.path : document.path);

/** A task's description and comments. Its title and properties are the host's to draw. */
function showTask(task: Task) {
  const article = element("article", "kit-task");
  const body = element("div", "kit-task-body");
  if (task.body.trim()) renderer.render(body, task.body, { path: task.path, area: "tasks", hash: task.hash, checkboxes: true }, context);
  else body.append(element("p", "kit-empty", "No description."));
  article.append(body);
  if (task.comments.length) {
    const section = element("section", "kit-comments");
    section.append(element("h2", "", `Comments (${task.comments.length})`));
    for (const comment of task.comments) {
      const item = element("div", "kit-comment");
      const header = element("div", "kit-comment-header");
      header.append(element("strong", "", comment.author), element("span", "kit-faint", formatTime(comment.date)));
      const text = element("div", "kit-comment-body");
      renderer.render(text, comment.body, { path: task.path, area: "tasks", hash: task.hash, checkboxes: false }, context);
      item.append(header, text);
      section.append(item);
    }
    article.append(section);
  }
  preview.replaceChildren(article);
}

function formatTime(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(date);
}

function element(tag: string, className: string, text?: string): HTMLElement {
  const created = document.createElement(tag);
  if (className) created.className = className;
  if (text !== undefined) created.textContent = text;
  return created;
}

/** The rendered height, so the host can size the web view inside its native screen. */
let reported = -1;
let frame = 0;
new ResizeObserver(() => {
  cancelAnimationFrame(frame);
  frame = requestAnimationFrame(() => {
    const height = Math.ceil(document.documentElement.getBoundingClientRect().height);
    if (Math.abs(height - reported) < 1) return;
    reported = height;
    bridge.post({ type: "height", height });
  });
}).observe(document.documentElement);

setMode("preview");
bridge.post({ type: "ready", protocol: PROTOCOL, genbeya: GENBEYA_VERSION });
