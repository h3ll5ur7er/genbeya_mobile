/**
 * The kit's messages (docs/Upstream/Kit-build.md). Messages travel as JSON
 * strings: the host calls `window.genbeyaKit.receive(text)`, the kit calls
 * `window.genbeyaKitHost.post(text)`. Everything the host sends is checked
 * here before the kit acts on it; everything the kit sends is untrusted input
 * for the host, which checks it again.
 */
import type { ContentArea, FieldDefinition, Person, Task, TaskType, WikiNode } from "genbeya/contracts/model";
import type { PlanCalendar, PlanTask } from "genbeya/utilities/planning";

/** Raised when a message is removed or changed; adding one, or an optional field, keeps it. */
export const PROTOCOL = 1;

/** The parts of the Markdown context, each sent with its own version, and only when it changed. */
export interface ContextParts {
  readonly wiki: { readonly wikiRoot: string; readonly nodes: readonly WikiNode[] };
  readonly tasks: readonly Pick<Task, "id" | "path" | "title" | "status">[];
  /** The tasks as plan macros show them, with the calendar; null while the project doesn't plan. */
  readonly plan: { readonly tasks: readonly PlanTask[]; readonly calendar?: PlanCalendar } | null;
  readonly files: readonly string[];
  readonly people: readonly Person[];
  readonly settings: {
    readonly statuses: readonly string[];
    readonly hiddenColumns: readonly string[];
    readonly types: readonly TaskType[];
    readonly fields: readonly FieldDefinition[];
  };
  /** The name the user's comments are signed with. */
  readonly author: string | null;
}

export type PartName = keyof ContextParts;
export const PART_NAMES: readonly PartName[] = ["wiki", "tasks", "plan", "files", "people", "settings", "author"];

export type ContextUpdate = { readonly [K in PartName]?: { readonly version: string; readonly value: ContextParts[K] } };

/** What `preview` shows. `hash` is the version of the file it was read from; `toggle` names it. */
export type PreviewDocument =
  | { readonly kind: "page"; readonly path: string; readonly title: string; readonly source: string; readonly hash: string }
  | { readonly kind: "task"; readonly task: Task }
  | {
      readonly kind: "markdown";
      readonly area: ContentArea;
      readonly path: string;
      readonly source: string;
      readonly hash: string;
      /** Whether its checkboxes tick; a pull request file's to-dos do, a comment's don't. */
      readonly checkboxes?: boolean;
    };

export type EditorCommand =
  | { readonly command: "bold" | "italic" | "heading" | "list" | "checkbox" | "link" | "undo" | "redo" | "find" | "save" }
  | { readonly command: "insert"; readonly text: string };

/** Host → kit. */
export type ToKit =
  | { readonly type: "context"; readonly parts: ContextUpdate }
  | { readonly type: "theme"; readonly theme: "light" | "dark"; readonly tokens?: Readonly<Record<string, string>> }
  | { readonly type: "preview"; readonly document: PreviewDocument }
  | {
      readonly type: "edit";
      readonly area: ContentArea;
      readonly path: string;
      readonly text: string;
      readonly hash: string;
      readonly readOnly?: boolean;
    }
  | ({ readonly type: "editorCommand" } & EditorCommand)
  | { readonly type: "reply"; readonly id: number; readonly value?: string; readonly error?: string };

/** A link the user followed, resolved against the document it is in. */
export type FollowedLink =
  | { readonly kind: "external"; readonly url: string }
  | { readonly kind: "missing"; readonly title: string }
  | { readonly kind: "person"; readonly handle: string }
  | { readonly kind: "file"; readonly path: string; readonly anchor: string | undefined };

/** Kit → host, requests: answered by a `reply` with the same `id`. */
export type KitRequest =
  /** An image of the repository, answered with a data URL. */
  | { readonly type: "image"; readonly id: number; readonly path: string }
  /** A text file as it is now, for embeds. */
  | { readonly type: "file"; readonly id: number; readonly path: string }
  /** A text file as committed in a revision, for pinned references. */
  | { readonly type: "fileAt"; readonly id: number; readonly path: string; readonly revision: string }
  /** The tasks' history as `content.planHistory` answers it, as JSON, for `[BURNDOWN]` and `[BASELINE]`. */
  | { readonly type: "planHistory"; readonly id: number; readonly baseline: string | null };

/** Kit → host. */
export type FromKit =
  | { readonly type: "ready"; readonly protocol: number; readonly genbeya: string }
  | { readonly type: "follow"; readonly link: FollowedLink }
  /** A ticked checkbox: `offset` counts in the source the kit rendered (a page, a task's description). */
  | { readonly type: "toggle"; readonly area: ContentArea; readonly path: string; readonly hash: string; readonly offset: number }
  | KitRequest
  | { readonly type: "height"; readonly height: number }
  | { readonly type: "draft"; readonly path: string; readonly hash: string; readonly text: string }
  | { readonly type: "save"; readonly path: string; readonly hash: string; readonly text: string }
  | {
      readonly type: "editorState";
      readonly path: string;
      readonly dirty: boolean;
      readonly selection: { readonly from: number; readonly to: number };
      readonly completing: boolean;
    }
  /** Something the kit couldn't do: an invalid message, a failed render. For the host's log. */
  | { readonly type: "error"; readonly message: string };

const AREAS: readonly string[] = ["wiki", "tasks", "settings", "pulls"];
const COMMANDS: readonly string[] = ["bold", "italic", "heading", "list", "checkbox", "link", "undo", "redo", "find", "save"];
/** CSS custom properties a host may set: a name, and a value that can't end the declaration. */
const TOKEN_NAME = /^--[a-z][a-z0-9-]{0,63}$/;
const TOKEN_VALUE = /^[^;{}<>\\]{0,200}$/;

type Json = Record<string, unknown>;
const isObject = (value: unknown): value is Json => typeof value === "object" && value !== null && !Array.isArray(value);
const isString = (value: unknown): value is string => typeof value === "string";
const isStringArray = (value: unknown): value is string[] => Array.isArray(value) && value.every(isString);
const isArea = (value: unknown): value is ContentArea => isString(value) && AREAS.includes(value);

/** A repository path as Genbeya's path rules allow it: relative, no `..`, nothing in `.git`. */
export const isRepositoryPath = (value: unknown): value is string =>
  isString(value) &&
  value.length > 0 &&
  value.length <= 1024 &&
  !value.startsWith("/") &&
  !value.includes("\\") &&
  !value.includes("\0") &&
  value.split("/").every((part) => part !== "" && part !== "." && part !== ".." && part.toLowerCase() !== ".git");

function checkPart(name: PartName, value: unknown): boolean {
  switch (name) {
    case "wiki":
      return isObject(value) && isString(value["wikiRoot"]) && Array.isArray(value["nodes"]);
    case "tasks":
      return (
        Array.isArray(value) &&
        value.every((task) => isObject(task) && isString(task["id"]) && isString(task["path"]) && isString(task["title"]) && isString(task["status"]))
      );
    case "plan":
      return value === null || (isObject(value) && Array.isArray(value["tasks"]));
    case "files":
      return isStringArray(value);
    case "people":
      return Array.isArray(value) && value.every((person) => isObject(person) && isString(person["handle"]) && isString(person["name"]));
    case "settings":
      return (
        isObject(value) &&
        isStringArray(value["statuses"]) &&
        isStringArray(value["hiddenColumns"]) &&
        Array.isArray(value["types"]) &&
        Array.isArray(value["fields"])
      );
    case "author":
      return value === null || isString(value);
  }
}

function checkDocument(value: unknown): value is PreviewDocument {
  if (!isObject(value)) return false;
  switch (value["kind"]) {
    case "page":
      return isRepositoryPath(value["path"]) && isString(value["title"]) && isString(value["source"]) && isString(value["hash"]);
    case "task": {
      const task = value["task"];
      return (
        isObject(task) &&
        isString(task["id"]) &&
        isRepositoryPath(task["path"]) &&
        isString(task["body"]) &&
        isString(task["hash"]) &&
        Array.isArray(task["comments"])
      );
    }
    case "markdown":
      return (
        isArea(value["area"]) &&
        isRepositoryPath(value["path"]) &&
        isString(value["source"]) &&
        isString(value["hash"]) &&
        (value["checkboxes"] === undefined || typeof value["checkboxes"] === "boolean")
      );
    default:
      return false;
  }
}

/** Parses and checks a message from the host; throws with the reason when it isn't one of the protocol's. */
export function parseToKit(text: string): ToKit {
  let message: unknown;
  try {
    message = JSON.parse(text);
  } catch {
    throw new Error("A message that isn't JSON.");
  }
  if (!isObject(message) || !isString(message["type"])) throw new Error("A message without a type.");
  const fail = (): never => {
    throw new Error(`An invalid ${String(message["type"])} message.`);
  };
  switch (message["type"]) {
    case "context": {
      const parts = message["parts"];
      if (!isObject(parts)) return fail();
      for (const [name, part] of Object.entries(parts)) {
        if (!PART_NAMES.includes(name as PartName)) throw new Error(`An unknown context part: ${name}.`);
        if (!isObject(part) || !isString(part["version"]) || !checkPart(name as PartName, part["value"])) {
          throw new Error(`An invalid context part: ${name}.`);
        }
      }
      return message as ToKit;
    }
    case "theme": {
      const tokens = message["tokens"];
      if (message["theme"] !== "light" && message["theme"] !== "dark") return fail();
      if (tokens !== undefined) {
        if (!isObject(tokens)) return fail();
        for (const [name, value] of Object.entries(tokens)) if (!TOKEN_NAME.test(name) || !isString(value) || !TOKEN_VALUE.test(value)) return fail();
      }
      return message as ToKit;
    }
    case "preview":
      return checkDocument(message["document"]) ? (message as ToKit) : fail();
    case "edit":
      return isArea(message["area"]) &&
        isRepositoryPath(message["path"]) &&
        isString(message["text"]) &&
        isString(message["hash"]) &&
        (message["readOnly"] === undefined || typeof message["readOnly"] === "boolean")
        ? (message as ToKit)
        : fail();
    case "editorCommand":
      if (message["command"] === "insert") return isString(message["text"]) ? (message as ToKit) : fail();
      return isString(message["command"]) && COMMANDS.includes(message["command"]) ? (message as ToKit) : fail();
    case "reply":
      return Number.isInteger(message["id"]) &&
        (message["value"] === undefined || isString(message["value"])) &&
        (message["error"] === undefined || isString(message["error"]))
        ? (message as ToKit)
        : fail();
    default:
      throw new Error(`An unknown message: ${String(message["type"])}.`);
  }
}
