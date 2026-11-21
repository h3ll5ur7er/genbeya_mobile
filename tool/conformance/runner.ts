/**
 * Runs one conformance case through Genbeya's own engines, imported from the
 * checkout that generate.mjs points the `genbeya` alias at.
 */
import { SettingsEngine } from "genbeya/src/engines/settings-engine";
import { TaskEngine } from "genbeya/src/engines/task-engine";
import type { TaskInput } from "genbeya/src/contracts/model";

export interface Case {
  readonly id: string;
  readonly kind: "settings.parse" | "task.parse" | "task.update";
  readonly input: Record<string, any>;
}

const settings = new SettingsEngine();
const tasks = new TaskEngine();

function run(c: Case): unknown {
  const i = c.input;
  switch (c.kind) {
    case "settings.parse":
      return { settings: settings.parse(i.content, settings.defaults(i.folderName), i.windows ?? false) };
    case "task.parse":
      return { task: tasks.parse(i.path, i.content, "hash", i.taskRoot) };
    case "task.update": {
      const task = tasks.parse(i.path, i.content, "hash", i.taskRoot);
      // What the desktop client sends: the whole task (task-model.ts inputOf) with the change applied.
      const input: TaskInput = {
        title: task.title,
        status: task.status,
        priority: task.priority,
        assignee: task.assignee,
        labels: task.labels,
        type: task.type,
        fields: { ...task.fields, ...(i.change.fields ?? {}) },
        body: task.body,
        epic: task.epic,
        ...Object.fromEntries(Object.entries(i.change).filter(([key]) => key !== "fields")),
      } as TaskInput;
      return { output: tasks.serializeUpdate(i.content, tasks.validate(input, i.statuses)) };
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
