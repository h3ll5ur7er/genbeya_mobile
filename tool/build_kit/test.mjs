// Checks the built kit (kit/dist) in Chromium with a test host, as a phone's web view would
// host it: messages through window.genbeyaKitHost and window.genbeyaKit only. Uses Genbeya's
// own repository (the build cache) as the repository the host serves.
// Usage: node test.mjs   (after node build.mjs)
import { execFileSync, execSync } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../..");
const dist = path.join(repo, "kit/dist");
const ref = fs.readFileSync(path.join(repo, "kit/GENBEYA_REF"), "utf8").trim();
const genbeya = path.join(here, ".cache", `genbeya-${ref.slice(0, 12)}`);
const shots = path.join(repo, "kit/test/screenshots");
const { chromium, devices } = createRequire(path.join(execSync("npm root -g").toString().trim(), "_.js"))("playwright");

const results = [];
const check = (name, ok, detail = "") => {
  results.push({ name, ok, detail });
  console.log(`${ok ? "✓" : "✗"} ${name}${detail ? ` — ${detail}` : ""}`);
};
const timings = {};

// ---- The repository the host serves: Genbeya's own, at the pinned commit. ----
const read = (file) => fs.readFileSync(path.join(genbeya, file), "utf8");
const files = execFileSync("git", ["-C", genbeya, "ls-files"]).toString().trim().split("\n");
const title = (name) => name.replace(/\.md$/, "").replace(/-/g, " ");
function wikiTree(dir) {
  const entries = fs.readdirSync(path.join(genbeya, dir), { withFileTypes: true });
  const pages = entries.filter((entry) => entry.isFile() && entry.name.endsWith(".md")).map((entry) => entry.name);
  const folders = entries.filter((entry) => entry.isDirectory() && entry.name !== "images").map((entry) => entry.name);
  const nodes = pages.map((page) => {
    const folder = folders.includes(page.replace(/\.md$/, "")) ? `${dir}/${page.replace(/\.md$/, "")}` : null;
    return { title: title(page), path: `${dir}/${page}`, folder, children: folder ? wikiTree(folder) : [] };
  });
  for (const folder of folders.filter((name) => !pages.includes(`${name}.md`))) {
    nodes.push({ title: title(folder), path: null, folder: `${dir}/${folder}`, children: wikiTree(`${dir}/${folder}`) });
  }
  return nodes;
}
const frontmatter = (text, key) => new RegExp(`^${key}: *"?(.*?)"?$`, "m").exec(text)?.[1] ?? "";
const tasks = files
  .filter((file) => /^tasks\/.*GENBEYA-\d+\.md$/.test(file))
  .map((file) => {
    const text = read(file);
    return { id: frontmatter(text, "id"), path: file, title: frontmatter(text, "title"), status: frontmatter(text, "status") };
  });
const statuses = ["backlog", "todo", "in-progress", "review", "done"];
const people = [
  { handle: "ada", name: "Ada Lovelace", email: "ada@example.com", aliases: [], commits: 12 },
  { handle: "alex", name: "Alex Chen", email: "alex@example.com", aliases: [], commits: 30 },
];
const planTask = (id, title, status, fields, logged = 0) => ({
  id,
  path: `tasks/Plan/${id}.md`,
  title,
  status,
  epic: "Plan",
  assignee: "alex",
  labels: [],
  type: "feature",
  fields,
  logged,
  unreadable: 0,
});
const plan = [
  planTask("GM-1", "Set up the app", "done", { estimate: "2d", remaining: "0h", milestone: "M0" }, 14),
  planTask("GM-2", "Git core", "in-progress", { estimate: "4d", remaining: "16h", milestone: "M0", depends_on: ["GM-1"] }, 20),
  planTask("GM-3", "Web kit", "todo", { estimate: "3d", remaining: "3d", milestone: "M0", depends_on: ["GM-1"] }),
  planTask("GM-6", "Repositories", "todo", { estimate: "4d", remaining: "4d", milestone: "M1", depends_on: ["GM-2"] }),
];
const planHistory = {
  commits: [
    { commit: "c3", date: "2026-11-20T18:00:00+01:00", author: "Alex Chen", subject: "c3", tasks: [{ path: plan[1].path, task: { ...plan[1], fields: { ...plan[1].fields, remaining: "16h" } } }] },
    { commit: "c2", date: "2026-11-19T12:00:00+01:00", author: "Alex Chen", subject: "c2", tasks: [{ path: plan[1].path, task: { ...plan[1], fields: { ...plan[1].fields, remaining: "24h" }, logged: 10 } }] },
    { commit: "c1", date: "2026-11-18T09:00:00+01:00", author: "Alex Chen", subject: "c1", tasks: plan.map((task) => ({ path: task.path, task: { ...task, status: "todo", logged: 0, fields: { ...task.fields, remaining: task.fields.estimate } } })) },
  ],
  truncated: false,
  baseline: null,
};
const context = {
  wiki: { version: "w1", value: { wikiRoot: "docs", nodes: wikiTree("docs") } },
  tasks: { version: "t1", value: [...tasks, ...plan.map(({ id, path, title, status }) => ({ id, path, title, status }))] },
  plan: { version: "p1", value: { tasks: plan, calendar: { workdays: ["mon", "tue", "wed", "thu", "fri"], holidays: [], milestones: [{ name: "M0", due: "2026-12-04" }] } } },
  files: { version: "f1", value: files },
  people: { version: "pe1", value: people },
  settings: { version: "s1", value: { statuses, hiddenColumns: [], types: [], fields: [] } },
  author: { version: "a1", value: "Alex Chen" },
};
const references = { kind: "page", path: "docs/Guide/References.md", title: "References", source: read("docs/Guide/References.md"), hash: "h-references" };
const planPage = {
  kind: "page",
  path: "docs/Plan.md",
  title: "Plan",
  hash: "h-plan",
  source: `# Plan

A page with everything the kit draws: see [[GENBEYA-42]] and [[Getting started]], by @ada on 2026-11-21.

- [ ] Note bundle size 2026-11-24
- [x] Render References

$$\\int_0^1 x^2\\,dx = \\tfrac{1}{3}$$

\`\`\`mermaid
flowchart LR
  app[Flutter] --> core[Native core]
  app --> kit[Web kit]
\`\`\`

\`\`\`plantuml
Alice -> Bob: hello
Bob --> Alice: hi
\`\`\`

![The board](images/task-board.png)

[EFFORT]

[GANTT]

[BURNDOWN]
`,
};

// ---- The host: serves kit/dist on its own origin and answers the kit's requests. ----
const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".wasm": "application/wasm", ".woff2": "font/woff2", ".json": "application/json", ".txt": "text/plain" };
const server = http.createServer((request, response) => {
  const file = path.join(dist, decodeURIComponent(new URL(request.url, "http://x").pathname));
  if (!file.startsWith(dist) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) return response.writeHead(404).end();
  response.writeHead(200, { "content-type": types[path.extname(file)] ?? "application/octet-stream" }).end(fs.readFileSync(file));
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const origin = `http://127.0.0.1:${server.address().port}`;

const safe = (file) => typeof file === "string" && !file.startsWith("/") && !file.split("/").some((part) => part === ".." || part === ".git" || part === "");
async function answer(message) {
  switch (message.type) {
    case "image": {
      if (!safe(message.path) || !fs.existsSync(path.join(genbeya, message.path))) throw new Error("No such image.");
      const ext = path.extname(message.path).slice(1).replace("jpg", "jpeg").replace("svg", "svg+xml");
      return `data:image/${ext};base64,${fs.readFileSync(path.join(genbeya, message.path)).toString("base64")}`;
    }
    case "file":
      if (!safe(message.path) || !files.includes(message.path)) throw new Error("No such file.");
      return read(message.path);
    case "fileAt":
      if (!safe(message.path) || !/^[\w.\-/]+$/.test(message.revision)) throw new Error("Not a revision.");
      try {
        return execFileSync("git", ["-C", genbeya, "show", `${message.revision}:${message.path}`], { stdio: ["ignore", "pipe", "ignore"] }).toString();
      } catch {
        throw new Error(`No ${message.path} in ${message.revision}.`);
      }
    case "planHistory":
      return JSON.stringify(planHistory);
  }
  throw new Error(`Not a request: ${message.type}`);
}

async function open(browser, contextOptions = {}) {
  const browserContext = await browser.newContext(contextOptions);
  const page = await browserContext.newPage();
  const messages = [];
  const requests = [];
  const violations = [];
  page.on("request", (request) => requests.push(request.url()));
  page.on("console", (message) => {
    if (message.type() === "error") violations.push(message.text());
  });
  page.on("pageerror", (error) => console.log(`  page error: ${error.message}`));
  await page.exposeBinding("__kitPost", async ({ page: source }, text) => {
    const message = JSON.parse(text);
    messages.push(message);
    if ("id" in message) {
      let reply;
      try {
        reply = { type: "reply", id: message.id, value: await answer(message) };
      } catch (error) {
        reply = { type: "reply", id: message.id, error: error.message };
      }
      await source.evaluate((json) => window.genbeyaKit.receive(json), JSON.stringify(reply));
    }
  });
  // What a host's user script does before the page loads.
  await page.addInitScript(() => {
    window.genbeyaKitHost = { post: (text) => window.__kitPost(text) };
    document.addEventListener("securitypolicyviolation", (event) => {
      (window.__violations ??= []).push(`${event.violatedDirective} ${event.blockedURI}`);
    });
  });
  const send = (message) => page.evaluate((json) => window.genbeyaKit.receive(json), JSON.stringify(message));
  const loading = Date.now();
  await page.goto(`${origin}/kit.html`);
  await page.waitForFunction(() => window.genbeyaKit !== undefined);
  return { page, messages, requests, violations, send, loaded: Date.now() - loading, close: () => browserContext.close() };
}

const until = async (predicate, timeout = 15000) => {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    if (predicate()) return true;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  return false;
};

const browser = await chromium.launch();
try {
  // ---- Rendering ----
  const kit = await open(browser, { viewport: { width: 412, height: 915 } });
  await until(() => kit.messages.some((message) => message.type === "ready"));
  const ready = kit.messages.find((message) => message.type === "ready");
  check("ready names protocol 1 and Genbeya's version", ready?.protocol === 1 && typeof ready.genbeya === "string", JSON.stringify(ready));
  timings.loadToReady = kit.loaded;

  await kit.send({ type: "theme", theme: "light" });
  await kit.send({ type: "context", parts: context });
  let start = Date.now();
  await kit.send({ type: "preview", document: references });
  await kit.page.waitForSelector(".md-ref-task");
  timings.referencesRendered = Date.now() - start;
  const refs = await kit.page.evaluate(() => ({
    tasks: [...document.querySelectorAll(".md-ref-task")].map((element) => element.textContent),
    pages: document.querySelectorAll(".md-ref-page").length,
    missing: document.querySelectorAll(".md-ref-missing, .md-missing").length,
    files: document.querySelectorAll(".md-ref-file").length,
    pinned: document.querySelectorAll(".md-ref-pinned").length,
  }));
  const task9 = tasks.find((task) => task.id === "GENBEYA-9");
  check(
    "task references show their live title and state",
    refs.tasks.some((text) => task9 && text.includes(task9.title) && /in progress/i.test(text)),
    `${refs.tasks.length} task references, e.g. "${refs.tasks[0]}"`,
  );
  check("page, file and pinned references render; a missing page is marked", refs.pages > 0 && refs.files > 0 && refs.pinned > 0 && refs.missing > 0, JSON.stringify(refs));
  await until(() => kit.messages.some((message) => message.type === "fileAt"));
  await kit.page.waitForSelector(".md-embed pre, .md-embed code", { timeout: 10000 }).catch(() => null);
  const embeds = await kit.page.evaluate(() => [...document.querySelectorAll(".md-embed")].map((element) => element.textContent.slice(0, 40)));
  check("embeds ask for files and show their lines", kit.messages.some((m) => m.type === "file") && embeds.some((text) => text.includes("statuses:")), embeds.join(" | "));
  check("repository images are asked for with their path", kit.messages.some((m) => m.type === "image" && m.path === "docs/images/wiki-references.png"));

  start = Date.now();
  await kit.send({ type: "preview", document: planPage });
  await kit.page.waitForSelector(".md-ref-task");
  timings.planPageText = Date.now() - start;
  const drawn = await kit.page
    .waitForFunction(() => document.querySelectorAll(".md-diagram img").length >= 4, null, { timeout: 30000 })
    .then(() => true)
    .catch(() => false);
  timings.planPageDiagrams = Date.now() - start;
  const page2 = await kit.page.evaluate(() => ({
    diagrams: document.querySelectorAll(".md-diagram img").length,
    errors: [...document.querySelectorAll(".md-diagram.is-error, .md-diagram-error")].map((element) => element.textContent.slice(0, 120)),
    math: document.querySelectorAll("math").length,
    tables: document.querySelectorAll("table").length,
    mention: document.querySelector(".md-mention, [class*=mention]")?.textContent ?? null,
    images: [...document.querySelectorAll("img")].filter((image) => image.src.startsWith("data:image/png")).length,
  }));
  check("Mermaid, PlantUML, the GANTT timeline and the BURNDOWN chart draw as images", drawn && page2.errors.length === 0, `${page2.diagrams} diagrams${page2.errors.length ? `, errors: ${page2.errors.join("; ")}` : ""}`);
  check("math renders as MathML", page2.math > 0);
  check("EFFORT renders a table", page2.tables > 0);
  check("a mention renders as a person", page2.mention?.includes("Ada") ?? false, String(page2.mention));
  check("BURNDOWN asks for the plan's history", kit.messages.some((m) => m.type === "planHistory"));
  check("the image of the page arrives as a data URL", page2.images > 0);
  check("the rendered height is reported", kit.messages.some((m) => m.type === "height" && m.height > 200), `last height ${kit.messages.filter((m) => m.type === "height").at(-1)?.height}`);

  await kit.page.screenshot({ path: path.join(shots, "page-light.png"), fullPage: true });
  await kit.send({ type: "theme", theme: "dark" });
  await kit.page.waitForTimeout(1500);
  await kit.page.screenshot({ path: path.join(shots, "page-dark.png"), fullPage: true });

  // ---- Checkbox ----
  await kit.page.click(".md-check.is-interactive");
  await until(() => kit.messages.some((m) => m.type === "toggle"));
  const toggle = kit.messages.find((m) => m.type === "toggle");
  const offsetOk = toggle && planPage.source.slice(toggle.offset).startsWith("- [ ]");
  check("ticking a checkbox sends toggle with the hash and the item's offset", toggle?.hash === "h-plan" && offsetOk, JSON.stringify(toggle));

  // ---- Links ----
  await kit.page.click(".md-ref-page");
  await until(() => kit.messages.some((m) => m.type === "follow"));
  check("following a page reference sends follow with its path", kit.messages.find((m) => m.type === "follow")?.link?.kind === "file", JSON.stringify(kit.messages.find((m) => m.type === "follow")));

  // ---- Isolation ----
  const blocked = await kit.page.evaluate(async () => {
    const script = document.createElement("script");
    script.textContent = "window.__inline = true";
    document.head.append(script);
    const image = document.createElement("img");
    image.src = "https://example.com/tracker.png";
    document.body.append(image);
    let fetched = "blocked";
    try {
      await fetch("https://example.com/");
      fetched = "fetched";
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 300));
    return { inline: window.__inline === true, fetched, violations: window.__violations ?? [] };
  });
  check("the content security policy refuses inline scripts, remote images and fetches", !blocked.inline && blocked.fetched === "blocked" && blocked.violations.length >= 2, blocked.violations.join(" | "));
  const outside = kit.requests.filter((url) => !url.startsWith(origin) && !url.startsWith("data:") && !url.startsWith("blob:"));
  const allowedProbe = outside.every((url) => url.startsWith("https://example.com"));
  check("no request leaves the kit's own files (apart from the refused probes)", allowedProbe, outside.length ? outside.join(", ") : "none");

  await kit.send({ type: "preview", document: { kind: "page", path: "../etc/passwd", title: "x", source: "x", hash: "x" } });
  await kit.page.evaluate(() => window.genbeyaKit.receive("{not json"));
  await until(() => kit.messages.filter((m) => m.type === "error").length >= 2);
  check("invalid messages are refused with an error message", kit.messages.filter((m) => m.type === "error").length >= 2, kit.messages.filter((m) => m.type === "error").map((m) => m.message).join(" | "));

  // ---- Editor, desktop-sized ----
  start = Date.now();
  await kit.send({ type: "edit", area: "wiki", path: "docs/Notes.md", text: "# Notes\n\n", hash: "h-notes" });
  await kit.page.waitForSelector(".cm-content");
  timings.editorOpen = Date.now() - start;
  await kit.page.click(".cm-content");
  await kit.page.keyboard.press("Control+End");
  await kit.page.keyboard.type("See [[GENBEYA-4");
  const listed = await kit.page.waitForSelector(".cm-tooltip-autocomplete li", { timeout: 5000 }).then(() => true).catch(() => false);
  const options = await kit.page.evaluate(() => [...document.querySelectorAll(".cm-tooltip-autocomplete li")].slice(0, 3).map((item) => item.textContent));
  await kit.page.keyboard.press("Enter");
  await kit.page.keyboard.type(" with @ad");
  await kit.page.waitForSelector(".cm-tooltip-autocomplete li", { timeout: 5000 }).catch(() => null);
  await kit.page.keyboard.press("Enter");
  await kit.page.keyboard.type(" by //tom");
  await kit.page.waitForSelector(".cm-tooltip-autocomplete li", { timeout: 5000 }).catch(() => null);
  await kit.page.keyboard.press("Enter");
  const text = await kit.page.evaluate(() => document.querySelector(".cm-content").innerText);
  check("[[ completes task references in the editor", listed && /\[\[GENBEYA-4\d*\]\]/.test(text), `offered ${options.join(" / ")}; text: ${JSON.stringify(text.split("\n").at(-1))}`);
  check("@ completes people and // completes dates", /@ada\b/.test(text) && /\d{4}-\d{2}-\d{2}/.test(text), JSON.stringify(text.split("\n").at(-1)));
  await kit.send({ type: "editorCommand", command: "checkbox" });
  await kit.send({ type: "editorCommand", command: "bold" });
  await kit.send({ type: "editorCommand", command: "undo" });
  await kit.send({ type: "editorCommand", command: "save" });
  await until(() => kit.messages.some((m) => m.type === "save"));
  const save = kit.messages.find((m) => m.type === "save");
  check("toolbar commands edit, undo works, save sends the text with its base hash", save?.hash === "h-notes" && save.text.includes("- [ ] See [[GENBEYA-") && !save.text.includes("**bold**"), JSON.stringify(save?.text));
  if (process.env.DEBUG) console.log(kit.messages.slice(-40).map((m) => m.type + (m.dirty !== undefined ? `:${m.dirty}:${m.selection.from}` : "") + (m.text !== undefined ? `:${JSON.stringify(m.text)}` : "")).join("\n"));
  const state = kit.messages.filter((m) => m.type === "editorState").at(-1);
  check("editorState reports dirty and the selection", state?.dirty === true && Number.isInteger(state.selection?.from), JSON.stringify(state));
  await kit.page.keyboard.type(" more");
  await until(() => kit.messages.some((m) => m.type === "draft"), 4000);
  check("drafts reach the host while typing", kit.messages.some((m) => m.type === "draft" && m.hash === "h-notes"));
  await kit.close();

  // ---- Editor on phones (emulated: Chromium with the device's size, touch and user agent) ----
  for (const name of ["Pixel 7", "iPhone 15"]) {
    const { defaultBrowserType, ...device } = devices[name];
    const phone = await open(browser, device);
    await phone.send({ type: "theme", theme: "dark" });
    await phone.send({ type: "context", parts: context });
    await phone.send({ type: "edit", area: "wiki", path: "docs/Notes.md", text: "# Notes\n\nFirst line\n", hash: "h" });
    await phone.page.waitForSelector(".cm-content");
    await phone.page.tap(".cm-line:last-child");
    await phone.page.keyboard.press("End");
    await phone.page.keyboard.insertText(" and [[GENBEYA-1");
    const offered = await phone.page.waitForSelector(".cm-tooltip-autocomplete li", { timeout: 5000 }).then(() => true).catch(() => false);
    if (offered) await phone.page.tap(".cm-tooltip-autocomplete li");
    await phone.page.keyboard.down("Shift");
    for (let i = 0; i < 5; i++) await phone.page.keyboard.press("ArrowLeft");
    await phone.page.keyboard.up("Shift");
    const selected = await phone.page.evaluate(() => window.getSelection()?.toString() ?? "");
    await phone.send({ type: "editorCommand", command: "undo" });
    const after = await phone.page.evaluate(() => document.querySelector(".cm-content").innerText);
    check(
      `${name} (emulated): tap to place the cursor, type, complete by tapping, select, undo`,
      offered && selected.length > 0 && !after.includes("[[GENBEYA-1"),
      `selected ${JSON.stringify(selected)}; after undo ${JSON.stringify(after.split("\n").filter(Boolean).at(-1))}`,
    );
    if (name === "Pixel 7") await phone.page.screenshot({ path: path.join(shots, "editor-dark.png") });
    await phone.close();
  }
} finally {
  await browser.close();
  server.close();
}

console.log(`\nTimings (headless Chromium, ms): ${JSON.stringify(timings)}`);
const failed = results.filter((result) => !result.ok);
console.log(`${results.length - failed.length} of ${results.length} checks passed`);
process.exit(failed.length ? 1 : 0);
