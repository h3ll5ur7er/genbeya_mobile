/**
 * Runs one conformance case through Genbeya's own engines, imported from the
 * checkout that generate.mjs points the `genbeya` alias at.
 */
import { SettingsEngine } from "genbeya/src/engines/settings-engine";
import { TaskEngine } from "genbeya/src/engines/task-engine";
import { contentAreaOf } from "genbeya/src/engines/settings-engine";
import type { TaskInput } from "genbeya/src/contracts/model";
import { toggleCheckboxAt } from "genbeya/src/client/app/markdown/task-checkbox";
// Imports Angular, which generate.mjs stubs: only this plain function is used.
import { stripFrontmatter } from "genbeya/src/client/app/core/file-resource";
import { buildFileTree } from "genbeya/src/utilities/file-tree";
import { WikiEngine } from "genbeya/src/engines/wiki-engine";
import { PeopleEngine } from "genbeya/src/engines/people-engine";
import { handleSlug } from "genbeya/src/utilities/people";
import { CONTENT_AREAS } from "genbeya/src/contracts/model";
import { namesRemoteHelper, parseRemote, sameRepository, withoutCredentials } from "genbeya/src/utilities/remote-url";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

export interface Case {
  readonly id: string;
  readonly kind: "settings.parse" | "task.parse" | "task.update" | "page.toggle" | "task.toggle" | "collate" | "file.tree" | "wiki.tree" | "people.merge" | "handle.slug" | "collate.full" | "areas.parse" | "remote.parse" | "remote.same" | "area.of" | "collate.base" | "task.changes";
  readonly input: Record<string, any>;
}

const settings = new SettingsEngine();
const tasks = new TaskEngine();
const wiki = new WikiEngine();
const people = new PeopleEngine();

/**
 * content-store.ts areasAt: `git config --blob <commit>:.genbeya-content --list`
 * (here `--file`, the same parser), null when Git refuses it, then parseAreas,
 * which is private there and mirrored line for line.
 */
function areasOf(file: string | null): Record<string, string> {
  if (file === null) return Object.fromEntries(CONTENT_AREAS.map((area) => [area, "branch"]));
  const dir = mkdtempSync(join(tmpdir(), "areas-"));
  let listed: string | null;
  try {
    writeFileSync(join(dir, "areas"), file);
    listed = execFileSync("git", ["config", "--file", join(dir, "areas"), "--list"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
  } catch {
    listed = null;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
  if (listed === null) return Object.fromEntries(CONTENT_AREAS.map((area) => [area, "branch"]));
  const values = new Map(listed.split("\n").map((line) => [line.slice(0, line.indexOf("=")), line.slice(line.indexOf("=") + 1).trim()]));
  return Object.fromEntries(CONTENT_AREAS.map((area) => [area, values.get(`areas.${area}`) === "branch" ? "branch" : "checkout"]));
}

/** What the desktop client sends to update a task: the whole task (task-model.ts inputOf) with the change applied. */
function inputOf(task: ReturnType<TaskEngine["parse"]>, change: Record<string, any>): TaskInput {
  return {
    title: task.title,
    status: task.status,
    priority: task.priority,
    assignee: task.assignee,
    labels: task.labels,
    type: task.type,
    fields: { ...task.fields, ...(change.fields ?? {}) },
    body: task.body,
    epic: task.epic,
    ...Object.fromEntries(Object.entries(change).filter(([key]) => key !== "fields")),
  } as TaskInput;
}

function run(c: Case): unknown {
  const i = c.input;
  switch (c.kind) {
    case "settings.parse":
      return { settings: settings.parse(i.content, settings.defaults(i.folderName), i.windows ?? false) };
    case "task.parse":
      return { task: tasks.parse(i.path, i.content, "hash", i.taskRoot) };
    case "task.update": {
      const task = tasks.parse(i.path, i.content, "hash", i.taskRoot);
      return { output: tasks.serializeUpdate(i.content, tasks.validate(inputOf(task, i.change), i.statuses)) };
    }
    case "page.toggle": {
      // wiki-page.ts toggleCheckbox: offsets count from the end of the frontmatter.
      const at = i.content.length - stripFrontmatter(i.content).length + i.offset;
      return { output: toggleCheckboxAt(i.content, at) };
    }
    case "collate":
      // The comparison Genbeya sorts names and titles with (file-tree.ts, wiki-engine.ts).
      return { output: [...i.strings].sort((a: string, b: string) => a.localeCompare(b, undefined, { numeric: true, sensitivity: "base" })) };
    case "area.of":
      return { output: i.settings.map((settings: any) => i.paths.map((path: string) => contentAreaOf(path, settings))) };
    case "remote.parse":
      return {
        output: i.urls.map((url: string) => ({ remote: parseRemote(url), helper: namesRemoteHelper(url), safe: withoutCredentials(url) })),
      };
    case "remote.same":
      return { output: i.pairs.map(([a, b]: [string, string]) => sameRepository(a, b)) };
    case "areas.parse":
      return { output: areasOf(i.file) };
    case "collate.base":
      // The comparison Genbeya sorts epics with (task-model.ts compareEpics).
      return { output: [...i.strings].sort((a: string, b: string) => a.localeCompare(b, undefined, { sensitivity: "base" })) };
    case "collate.full":
      // The comparison Genbeya sorts people with (people-engine.ts).
      return { output: [...i.strings].sort((a: string, b: string) => a.localeCompare(b)) };
    case "file.tree":
      return { output: buildFileTree(i.files) };
    case "wiki.tree": {
      const settings = { wikiRoot: i.wikiRoot, wikiHome: i.wikiHome };
      return { output: { tree: wiki.tree(i.files, settings), pages: wiki.pages(i.files, settings) } };
    }
    case "people.merge": {
      const merged = people.merge(i.sources);
      return { output: { people: merged, me: i.identities.map((identity: any) => people.me(merged, identity)) } };
    }
    case "handle.slug":
      return { output: i.texts.map(handleSlug) };
    case "task.changes":
      return { output: tasks.changesBetween(i.before, i.after, i.taskRoot) };
    case "task.toggle": {
      // task-panel.ts toggleCheckbox: the description with the checkbox flipped.
      const task = tasks.parse(i.path, i.content, "hash", i.taskRoot);
      const change = { body: toggleCheckboxAt(task.body, i.offset) };
      return { output: tasks.serializeUpdate(i.content, tasks.validate(inputOf(task, change), i.statuses)) };
    }
  }
}

export function runCase(c: Case): unknown {
  try {
    return run(c);
  } catch (error) {
    return { error: (error as Error).message };
  }
}
