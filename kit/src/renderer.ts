/**
 * Rendered Markdown in the kit, with Genbeya's own pipeline. Adapted from the
 * VS Code webview's renderer (src/shells/vscode/webview/markdown.ts), which it
 * follows line for line where it can. What differs: `toggle` names the hash of
 * the version shown, `[BURNDOWN]` and `[BASELINE]` are filled through
 * `planHistory`, plan macros get the calendar, and the theme comes from
 * `data-theme` instead of VS Code's body classes. Once the kit lives in
 * Genbeya, both should share one renderer.
 */
import type mermaid from "mermaid";
import type katex from "katex";
import type { Rockuml } from "@rockuml/core";
import type { ContentArea, PlanHistory } from "genbeya/contracts/model";
import { checkPinned, fillEmbed, type EmbeddedFiles } from "genbeya/client/app/markdown/file-embeds";
import { footnotePreview } from "genbeya/client/app/markdown/footnotes";
import { resolveHref } from "genbeya/client/app/markdown/link-target";
import {
  icon,
  renderMarkdownTree,
  type Diagram,
  type Formula,
  type PlanHistoryBlock,
  type RepositoryImage,
} from "genbeya/client/app/markdown/markdown-dom";
import { parseMarkdown, type GenbeyaOptions } from "genbeya/client/app/markdown/markdown-pipeline";
import { mathElement } from "genbeya/client/app/markdown/mathml";
import { today } from "genbeya/client/app/ui/calendar-date";
import { flattenPages, subpagesOf, findPage } from "genbeya/client/app/features/wiki/wiki-pages";
import { baselineComparison, baselineMarkdown, burnChart, burnDown } from "genbeya/utilities/plan-history";
import { parseFilter } from "genbeya/utilities/planning";
import type { Bridge } from "./bridge";
import type { ContextParts } from "./protocol";

/** Where rendered Markdown comes from: the file, its area, its version, and whether its checkboxes tick. */
export interface Source {
  readonly path: string;
  readonly area: ContentArea;
  readonly hash: string;
  readonly checkboxes: boolean;
}

interface Render {
  readonly objectUrls: string[];
}

const light = () => document.documentElement.dataset["theme"] === "light";

let mermaidModule: Promise<typeof mermaid> | null = null;
let katexModule: Promise<typeof katex> | null = null;
let rockumlEngine: Promise<Rockuml> | null = null;
let diagramCounter = 0;

/** Reference targets, mentions, subpages and plans of a document, from the context the host sent. */
export function markdownOptions(context: ContextParts, path: string): GenbeyaOptions {
  return {
    references: {
      wikiRoot: context.wiki.wikiRoot,
      pages: flattenPages(context.wiki.nodes).map(({ title, path }) => ({ title, path })),
      tasks: context.tasks,
      statuses: context.settings.statuses,
      files: context.files,
    },
    people: context.people,
    subpages: subpagesOf(findPage(context.wiki.nodes, path)?.node.children ?? []),
    plan: context.plan
      ? { tasks: context.plan.tasks, statuses: context.settings.statuses, today: today(), calendar: context.plan.calendar }
      : null,
  };
}

/** LaTeX as MathML through Genbeya's allowlist, never as HTML. Shared with the editor's math preview. */
export async function typeset(source: string, display: boolean): Promise<{ readonly math: Element } | { readonly error: string }> {
  try {
    const tex = await (katexModule ??= import("katex").then((module) => module.default));
    const markup = tex.renderToString(source, {
      output: "mathml",
      throwOnError: true,
      trust: false,
      strict: "warn",
      maxSize: 20,
      maxExpand: 500,
      displayMode: display,
    });
    const math = mathElement(markup, document);
    return math ? { math } : { error: "KaTeX returned no formula." };
  } catch (failure) {
    return { error: failure instanceof Error ? failure.message : String(failure) };
  }
}

export class Renderer {
  /** The latest render of each host, so a slow image or diagram never lands in a newer one. */
  private readonly renders = new WeakMap<HTMLElement, Render>();
  /** Plan histories by plan version and baseline, read once. */
  private readonly histories = new Map<string, Promise<PlanHistory>>();

  /** Embeds and pinned references read files through the host. */
  private readonly files: EmbeddedFiles = {
    file: (path) => this.bridge.request({ type: "file", path }),
    fileAt: (path, revision) => this.bridge.request({ type: "fileAt", path, revision }),
  };

  constructor(
    private readonly bridge: Bridge,
    private readonly planVersion: () => string,
  ) {}

  /** Renders `markdown` into `host`, replacing what it held. */
  render(host: HTMLElement, markdown: string, source: Source, context: ContextParts): void {
    for (const url of this.renders.get(host)?.objectUrls ?? []) URL.revokeObjectURL(url);
    const render: Render = { objectUrls: [] };
    this.renders.set(host, render);
    const options = markdownOptions(context, source.path);
    const tree = parseMarkdown(markdown, options);
    const rendered = renderMarkdownTree(tree, document, { path: source.path, interactiveCheckboxes: source.checkboxes });
    host.classList.add("markdown", "selectable");
    host.replaceChildren(rendered.fragment);
    host.dataset["path"] = source.path;
    host.dataset["area"] = source.area;
    host.dataset["hash"] = source.hash;
    const current = () => this.renders.get(host) === render;
    for (const image of rendered.images) void this.load(image, current);
    for (const diagram of rendered.diagrams) void this.draw(diagram, current, render);
    for (const formula of rendered.formulas) void this.typeset(formula, current);
    for (const embed of rendered.embeds) void fillEmbed(embed, this.files, current);
    for (const history of rendered.histories) void this.fillHistory(history, source.path, options, current, render);
    for (const link of host.querySelectorAll<HTMLAnchorElement>("a.md-ref-pinned")) void checkPinned(link, source.path, this.files, current);
  }

  /** Follows links and toggles checkboxes in rendered Markdown below `root`. */
  listen(root: HTMLElement): void {
    root.addEventListener("click", (event) => {
      const target = event.target as Element;
      const host = target.closest<HTMLElement>(".markdown[data-path]");
      if (!host) return;
      const copy = target.closest<HTMLElement>("[data-copy]");
      if (copy) return void navigator.clipboard?.writeText(copy.dataset["copy"] ?? "");
      const wrap = target.closest<HTMLElement>("[data-wrap]");
      if (wrap) {
        const wrapped = wrap.closest(".md-code")?.classList.toggle("is-wrapped") ?? false;
        return wrap.setAttribute("aria-pressed", String(wrapped));
      }
      const checkbox = target.closest<HTMLElement>(".md-check.is-interactive");
      if (checkbox) return this.toggle(host, Number(checkbox.dataset["offset"]));
      const anchor = target.closest("a");
      if (!anchor) return;
      event.preventDefault();
      const href = anchor.getAttribute("href");
      if (!href) return;
      const link = resolveHref(host.dataset["path"]!, href);
      if (link.kind === "anchor") host.querySelector(`#${CSS.escape(link.id)}`)?.scrollIntoView({ behavior: "smooth" });
      else this.bridge.post({ type: "follow", link });
    });
    root.addEventListener("keydown", (event) => {
      const checkbox = (event.target as Element).closest<HTMLElement>(".md-check.is-interactive");
      const host = checkbox?.closest<HTMLElement>(".markdown[data-path]");
      if (!checkbox || !host || (event.key !== " " && event.key !== "Enter")) return;
      event.preventDefault();
      this.toggle(host, Number(checkbox.dataset["offset"]));
    });
    let preview: HTMLElement | null = null;
    root.addEventListener("pointerover", (event) => {
      const reference = (event.target as Element).closest<HTMLAnchorElement>("a[data-footnote-ref]");
      const host = reference?.closest<HTMLElement>(".markdown");
      if (!reference || !host) return;
      preview?.remove();
      preview = footnotePreview(reference, host);
    });
    root.addEventListener("pointerout", (event) => {
      if ((event.target as Element).closest("a[data-footnote-ref]")) preview = (preview?.remove(), null);
    });
  }

  private toggle(host: HTMLElement, offset: number) {
    if (!Number.isInteger(offset)) return;
    this.bridge.post({
      type: "toggle",
      area: host.dataset["area"] as ContentArea,
      path: host.dataset["path"]!,
      hash: host.dataset["hash"]!,
      offset,
    });
  }

  private async load(image: RepositoryImage, current: () => boolean) {
    try {
      const url = await this.bridge.request({ type: "image", path: image.path });
      if (!/^data:image\/(png|jpeg|gif|webp|avif|svg\+xml);base64,/.test(url)) throw new Error("Not an image.");
      if (current()) image.element.src = url;
    } catch {
      if (!current()) return;
      const placeholder = document.createElement("span");
      placeholder.className = "md-remote-image";
      placeholder.append(icon(document, "imageOff", 14), document.createTextNode(` ${image.element.alt || image.path}`));
      image.element.replaceWith(placeholder);
    }
  }

  /** Diagrams are shown as images, so markup inside them can never run. */
  private async draw({ element, language, source }: Diagram, current: () => boolean, render: Render) {
    const name = language === "mermaid" ? "Mermaid" : "PlantUML";
    try {
      const { svg, isError } = language === "mermaid" ? await drawMermaid(source) : await drawPlantUml(source);
      if (!current()) return;
      const url = URL.createObjectURL(new Blob([svg], { type: "image/svg+xml" }));
      render.objectUrls.push(url);
      const image = document.createElement("img");
      image.src = url;
      image.alt = `${name} diagram`;
      element.classList.toggle("is-error", isError);
      element.replaceChildren(image);
    } catch (error) {
      if (!current()) return;
      const failure = document.createElement("div");
      failure.className = "md-diagram-error";
      const title = document.createElement("strong");
      title.textContent = `${name} diagram`;
      const message = document.createElement("span");
      message.textContent = error instanceof Error ? error.message : String(error);
      const code = document.createElement("pre");
      code.textContent = source;
      failure.append(title, message, code);
      element.replaceWith(failure);
    }
  }

  private async typeset({ element, source, display }: Formula, current: () => boolean) {
    const result = await typeset(source, display);
    if (!current()) return;
    if ("math" in result) return element.replaceWith(result.math);
    element.classList.add("md-math-error");
    element.title = result.error;
  }

  /** `[BURNDOWN]` and `[BASELINE]`: the tasks' history from the host, drawn as Markdown of its own (as the app's PlanHistories does). */
  private async fillHistory(
    { element, kind, args }: PlanHistoryBlock,
    path: string,
    options: GenbeyaOptions,
    current: () => boolean,
    render: Render,
  ) {
    const plan = options.plan;
    let markdown: string;
    try {
      markdown = plan ? await this.historyMarkdown(kind, args, plan) : "*No tasks to plan here.*";
    } catch (error) {
      markdown = `*Can't read the plan's history: ${error instanceof Error ? error.message : String(error)}*`;
    }
    if (!current()) return;
    const rendered = renderMarkdownTree(parseMarkdown(markdown, options), document, { path, interactiveCheckboxes: false });
    element.replaceChildren(rendered.fragment);
    for (const diagram of rendered.diagrams) void this.draw(diagram, current, render);
  }

  private history(baseline: string | null): Promise<PlanHistory> {
    const key = `${this.planVersion()}\n${baseline ?? ""}`;
    let history = this.histories.get(key);
    if (!history) {
      history = this.bridge.request({ type: "planHistory", baseline }).then((text) => JSON.parse(text) as PlanHistory);
      history.catch(() => this.histories.delete(key));
      this.histories.set(key, history);
    }
    return history;
  }

  private async historyMarkdown(kind: "BURNDOWN" | "BASELINE", args: string, plan: NonNullable<GenbeyaOptions["plan"]>): Promise<string> {
    const words = args.trim().split(/\s+/).filter(Boolean);
    const revision = kind === "BASELINE" ? (words.find((word) => !word.includes("=")) ?? null) : null;
    const filter = parseFilter(words.filter((word) => word !== revision).join(" "));
    if (kind === "BASELINE" && !revision) return "*Name the baseline, a tag or commit: `[BASELINE v1.0]`.*";
    const history = await this.history(revision);
    const truncated = history.truncated ? "\n\n*Only the newest commits of the tasks are read.*" : "";
    if (kind === "BASELINE") {
      if (!history.baseline?.commit) return `*This repository has no commit or tag ${revision}.*`;
      return baselineMarkdown(baselineComparison(history, plan.tasks, filter, plan.statuses), revision!) + truncated;
    }
    const chart = burnChart(burnDown(history, plan.tasks, filter, plan.statuses, plan.today));
    if (!chart) return "*Not enough history for a burn chart yet: it needs commits on more than one day.*";
    return `\`\`\`mermaid\n${chart}\n\`\`\`\n\n*Bars: hours left; line: hours logged so far, by the day of each commit.*${truncated}`;
  }
}

async function drawMermaid(source: string) {
  const engine = await (mermaidModule ??= import("mermaid").then((module) => module.default));
  engine.initialize({
    startOnLoad: false,
    securityLevel: "strict",
    theme: light() ? "neutral" : "dark",
    fontFamily: getComputedStyle(document.body).fontFamily,
    // Labels as SVG text, so the diagram works as an image.
    flowchart: { htmlLabels: false },
  });
  const { svg } = await engine.render(`gd-mermaid-${++diagramCounter}`, source);
  // As an image, width="100%" would stretch the diagram; keep its natural width instead.
  const width = /viewBox="[-\d.]+ [-\d.]+ ([\d.]+) /.exec(svg)?.[1];
  return { svg: width ? svg.replace('width="100%"', `width="${width}"`) : svg, isError: false };
}

async function drawPlantUml(source: string) {
  const engine = await (rockumlEngine ??= import("@rockuml/core").then(({ load }) => load(document.body.dataset["rockuml"])));
  // A bare diagram body is a convenience; rockuml needs the start and end markers.
  const text = /^\s*@start/m.test(source) ? source : `@startuml\n${source}\n@enduml`;
  const { data, isError } = await engine.render(text);
  return { svg: data, isError };
}
