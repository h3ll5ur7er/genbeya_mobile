/**
 * Runs one conformance case through Genbeya's own engines, imported from the
 * checkout that generate.mjs points the `genbeya` alias at.
 */
import { SettingsEngine } from "genbeya/src/engines/settings-engine";
import { TaskEngine } from "genbeya/src/engines/task-engine";
import type { TaskInput } from "genbeya/src/contracts/model";
import { toggleCheckboxAt } from "genbeya/src/client/app/markdown/task-checkbox";
// Imports Angular, which generate.mjs stubs: only this plain function is used.
import { stripFrontmatter } from "genbeya/src/client/app/core/file-resource";

export interface Case {
  readonly id: string;
  readonly kind: "settings.parse" | "task.parse" | "task.update" | "page.toggle" | "task.toggle";
  readonly input: Record<string, any>;
}

const settings = new SettingsEngine();
const tasks = new TaskEngine();

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
