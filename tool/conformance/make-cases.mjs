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
