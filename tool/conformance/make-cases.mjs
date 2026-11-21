// Writes cases/*.json from fixtures/: every settings file is parsed; every
// task file is parsed and has its status moved; the edge cases and every
// fourth real task also get the other edits a phone makes.
import { mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const STATUSES = ["backlog", "todo", "in-progress", "review", "done"];
const cases = [];
const add = (id, kind, input) => cases.push({ id, kind, input });
const read = (path) => readFileSync(path, "utf8");

for (const name of readdirSync(join(here, "fixtures/settings")).sort()) {
  add(`settings-${name.replace(/\.yml$/, "")}`, "settings.parse", {
    content: read(join(here, "fixtures/settings", name)),
    folderName: "my-repo",
    windows: false,
  });
}

const walk = (dir) => readdirSync(dir).flatMap((n) => (statSync(join(dir, n)).isDirectory() ? walk(join(dir, n)) : [join(dir, n)]));
for (const set of readdirSync(join(here, "fixtures/tasks")).sort()) {
  const root = join(here, "fixtures/tasks", set);
  walk(root)
    .filter((f) => f.endsWith(".md"))
    .sort()
    .forEach((file, index) => {
      const path = `tasks/${relative(root, file)}`;
      const content = read(file);
      const id = `task-${set}-${basename(file, ".md")}`;
      const base = { path, content, taskRoot: "tasks", statuses: STATUSES };
      add(`${id}-parse`, "task.parse", base);
      const status = /^status:\s*(\S+)/m.exec(content)?.[1];
      const next = STATUSES[(STATUSES.indexOf(status) + 1) % STATUSES.length];
      add(`${id}-status`, "task.update", { ...base, change: { status: next } });
      if (set !== "edge" && index % 4) return;
      const priority = /^priority:\s*(\S+)/m.exec(content)?.[1];
      add(`${id}-priority`, "task.update", { ...base, change: { priority: priority === "high" ? "none" : "high" } });
      add(`${id}-field`, "task.update", { ...base, change: { fields: { remaining: "3h" } } });
      add(`${id}-field-list`, "task.update", { ...base, change: { fields: { depends_on: ["GM-1", "GM-2"] } } });
      add(`${id}-label`, "task.update", { ...base, change: { labels: [...labelsOf(content), "mobile"] } });
      add(`${id}-no-type`, "task.update", { ...base, change: { type: "" } });
      add(`${id}-title`, "task.update", { ...base, change: { title: "Renamed: on the phone" } });
    });
}

// Checkbox toggles: a page's checkbox at every task list item (the first and
// last three of a long page) and at offsets where no item starts, which this
// app refuses and Genbeya would tick the next checkbox for; a task's in its
// description. `item` says whether an item starts at the offset.
const ITEM = /^(?:[ \t]*>[ \t]?)*[ \t]*((?:[-*+]|\d{1,9}[.)])[ \t]+\[[ xX]\])/dgm;
const itemOffsets = (text) => [...text.matchAll(ITEM)].map((m) => m.indices[1][0]);
const sample = (list) => (list.length > 6 ? [...list.slice(0, 3), ...list.slice(-3)] : list);
const offsetCases = (text, edge) => [
  ...sample(itemOffsets(text)).map((offset) => ({ offset, item: true })),
  ...(itemOffsets(text).includes(0) ? [] : [{ offset: 0, item: false }]),
  ...(edge ? [{ offset: text.length + 5, item: false }] : []),
];
const stripPageFrontmatter = (text) => text.replace(/^---\r?\n[\s\S]*?\r?\n---[ \t]*\r?\n/, "");
for (const set of readdirSync(join(here, "fixtures/pages")).sort()) {
  for (const name of readdirSync(join(here, "fixtures/pages", set)).sort()) {
    const content = read(join(here, "fixtures/pages", set, name));
    for (const { offset, item } of offsetCases(stripPageFrontmatter(content), set === "edge")) {
      add(`page-${set}-${name.replace(/\.md$/, "")}-toggle-${offset}`, "page.toggle", { content, offset, item });
    }
  }
}
function descriptionOf(content) {
  const raw = content.replace(/^\uFEFF/, "");
  const front = /^---\r?\n([\s\S]*?\r?\n)?---[ \t]*(?:\r?\n|$)/.exec(raw);
  const body = (front ? raw.slice(front[0].length) : raw).replace(/^\r?\n/, "");
  const comments = /^## Comments[ \t]*$/m.exec(body);
  return comments ? body.slice(0, comments.index) : body;
}
for (const set of readdirSync(join(here, "fixtures/tasks")).sort()) {
  const root = join(here, "fixtures/tasks", set);
  for (const file of walk(root).filter((f) => f.endsWith(".md")).sort()) {
    const content = read(file);
    const offsets = itemOffsets(descriptionOf(content));
    if (!offsets.length) continue;
    const chosen = [...new Set([offsets[0], offsets.at(-1)])].map((offset) => ({ offset, item: true }));
    if (set === "edge" || !offsets.includes(0)) chosen.push({ offset: 0, item: offsets.includes(0) });
    for (const { offset, item } of chosen) {
      add(`task-${set}-${basename(file, ".md")}-toggle-${offset}`, "task.toggle", {
        path: `tasks/${relative(root, file)}`,
        content,
        taskRoot: "tasks",
        statuses: STATUSES,
        offset,
        item,
      });
    }
  }
}

function labelsOf(content) {
  const flow = /^labels:\s*\[(.*)\]/m.exec(content);
  if (flow) return flow[1].split(",").map((s) => s.trim()).filter(Boolean);
  const block = /^labels:\s*\n((?:\s+- .*\n)+)/m.exec(content);
  return block ? block[1].split("\n").map((l) => l.replace(/^\s+- /, "").trim()).filter(Boolean) : [];
}

rmSync(join(here, "cases"), { recursive: true, force: true });
mkdirSync(join(here, "cases"));
for (const c of cases) writeFileSync(join(here, "cases", `${c.id}.json`), JSON.stringify(c, null, 2) + "\n");
console.log(`${cases.length} cases`);
