/**
 * Runs one conformance case through Genbeya's own engines, imported from the
 * checkout that generate.mjs points the `genbeya` alias at.
 */
import { SettingsEngine } from "genbeya/src/engines/settings-engine";
import { TaskEngine } from "genbeya/src/engines/task-engine";
import { contentAreaOf } from "genbeya/src/engines/settings-engine";
import { SearchEngine } from "genbeya/src/engines/search-engine";
import type { TaskInput } from "genbeya/src/contracts/model";
import { toggleCheckboxAt } from "genbeya/src/client/app/markdown/task-checkbox";
// Imports Angular, which generate.mjs stubs: only this plain function is used.
import { stripFrontmatter } from "genbeya/src/client/app/core/file-resource";
import { buildFileTree } from "genbeya/src/utilities/file-tree";
import { WikiEngine } from "genbeya/src/engines/wiki-engine";
import { PeopleEngine } from "genbeya/src/engines/people-engine";
import { handleSlug } from "genbeya/src/utilities/people";
import { CONTENT_AREAS } from "genbeya/src/contracts/model";
import { namesRemoteHelper, parseRemote, sameRepository, webUrl, withoutCredentials } from "genbeya/src/utilities/remote-url";
import { describeLinkItem, formatGenbeyaLink, parseGenbeyaLink } from "genbeya/src/utilities/genbeya-link";
import { mentionSuggestions, mentionText } from "genbeya/src/client/app/editor/mention-suggestions";
import { dateSuggestions } from "genbeya/src/client/app/editor/smart-dates";
import { referenceCandidates } from "genbeya/src/client/app/markdown/references";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

export interface Case {
  readonly id: string;
  readonly kind: "settings.parse" | "task.parse" | "task.update" | "page.toggle" | "task.toggle" | "collate" | "file.tree" | "wiki.tree" | "people.merge" | "handle.slug" | "collate.full" | "areas.parse" | "remote.parse" | "remote.same" | "area.of" | "collate.base" | "task.changes" | "search.area" | "search.excerpt" | "link.parse" | "link.format" | "web.url" | "task.comment" | "task.new" | "task.nextId" | "task.spelling" | "task.template" | "suggest.mentions" | "suggest.references" | "suggest.dates";
  readonly input: Record<string, any>;
}

const settings = new SettingsEngine();
const tasks = new TaskEngine();
const wiki = new WikiEngine();
const people = new PeopleEngine();
const search = new SearchEngine();

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
      // Description edits as the editor sends them: a line appended, or the text replaced with CRLF lines.
      const body = i.edit === "append" ? `${task.body.trimEnd()}\n\nAdded on the phone.\n` : i.edit === "replace" ? "New text\r\n\r\n- [ ] item\r\n" : undefined;
      const change = { ...(i.change ?? {}), ...(body !== undefined && { body }) };
      return { output: tasks.serializeUpdate(i.content, tasks.validate(inputOf(task, change), i.statuses)) };
    }
    case "suggest.mentions":
      // What the comment box offers after `@`, and what picking the first inserts.
      return {
        output: i.queries.map((query: string) => {
          const found = mentionSuggestions(i.people, query);
          return { handles: found.map((person) => person.handle), insert: found[0] ? [mentionText(found[0], ""), mentionText(found[0], " x")] : null };
        }),
      };
    case "suggest.references":
      return { output: referenceCandidates({ ...i, statuses: [] }) };
    case "suggest.dates":
      // A typed date's label is in the user's language; the dates are what is inserted.
      return {
        output: i.queries.map((query: string) =>
          dateSuggestions(query, i.today).map((s) => ({ date: s.date, label: s.date === query.trim() ? null : s.label })),
        ),
      };
    case "task.new":
      // content-manager.ts createTask: validate, then serializeNew.
      return { output: tasks.serializeNew(i.id, tasks.validate(i.input, i.statuses)) };
    case "task.nextId": {
      const taken = new Set(i.taken);
      return { output: tasks.nextId(i.prefix, i.ids, (id) => taken.has(id)) };
    }
    case "task.spelling":
      return { output: i.epics.map((epic: string) => tasks.existingSpelling(epic, i.files, i.taskRoot)) };
    case "task.template":
      if (i.types)
        return {
          output: {
            templates: i.types.map((type: string) => tasks.newTemplate(type)),
            paths: i.paths.map((type: string) => { try { return tasks.templatePath("tasks", type); } catch (error) { return { error: (error as Error).message }; } }),
          },
        };
      return { output: tasks.parseTemplate(i.content) };
    case "page.toggle": {
      // wiki-page.ts toggleCheckbox: offsets count from the end of the frontmatter.
      const at = i.content.length - stripFrontmatter(i.content).length + i.offset;
      return { output: toggleCheckboxAt(i.content, at) };
    }
    case "collate":
      // The comparison Genbeya sorts names and titles with (file-tree.ts, wiki-engine.ts).
      return { output: [...i.strings].sort((a: string, b: string) => a.localeCompare(b, undefined, { numeric: true, sensitivity: "base" })) };
    case "link.parse":
      return { output: i.texts.map((text: string) => { const link = parseGenbeyaLink(text); return link && { ...link, described: describeLinkItem(link.item) }; }) };
    case "link.format":
      return { output: i.links.map((link: any) => formatGenbeyaLink(link)) };
    case "web.url":
      return {
        output: {
          files: i.files.map(([remote, path, branch]: string[]) => webUrl(remote, { kind: "file", path, branch })),
          commits: i.commits.map(([remote, hash]: string[]) => webUrl(remote, { kind: "commit", hash })),
        },
      };
    case "search.area":
      return { output: i.settings.map((settings: any) => i.paths.map((path: string) => search.areaOf(path, settings))) };
    case "search.excerpt":
      return { output: i.lines.map(({ line, ranges }: any) => search.excerpt(line, ranges)) };
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
    case "task.comment":
      // Comments are signed in local time; generate.mjs runs in UTC.
      if (i.op === "add") return { output: tasks.addComment(i.content, i.author, new Date(i.date), tasks.validComment(i.text)) };
      if (i.op === "edit") return { output: tasks.editComment(i.content, i.index, tasks.validComment(i.text)) };
      return { output: tasks.removeComment(i.content, i.index) };
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

export { desktopRepository } from "./desktop-repository";
