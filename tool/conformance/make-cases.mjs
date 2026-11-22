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

// Names and titles sorted as Genbeya sorts them (localeCompare, numeric,
// base strength): the file and wiki trees of real repositories and edge
// cases, and lists of strings that probe the collation table.
const lines = (name) => read(join(here, "fixtures/files", name)).split("\n").filter(Boolean);
for (const name of readdirSync(join(here, "fixtures/files")).sort()) {
  const files = lines(name);
  const set = name.replace(/\.txt$/, "");
  add(`files-${set}-tree`, "file.tree", { files });
  for (const [wikiRoot, wikiHome] of [["docs", "Home.md"], ["docs/Guide", "Install.md"], ["", "README.md"], [".", "README.md"]]) {
    add(`wiki-${set}-${wikiRoot.replace(/\W/g, "_") || "root"}`, "wiki.tree", { files, wikiRoot, wikiHome });
  }
}
let seed = 20261122;
const random = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
const pool = [
  ..." _-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$0123456789",
  ..."aAbBcCeEoOsSzZ", ..."éèêëÉàäÄöÖüÜçñÑøØåÅ", ..."ßæÆœŒĳﬁ", ..."ΩωαΑЖжЯя", ..."日本語한국",
  ..."０１２²①", "\u0301", "\u200b", "\u00ad", "🎉", "😀", "\t",
];
const pick = () => pool[Math.floor(random() * pool.length)];
const word = () => Array.from({ length: 1 + Math.floor(random() * 6) }, pick).join("");
const titles = [...lines("genbeya.txt"), ...lines("mobile.txt")].filter((f) => f.startsWith("docs/")).map((f) => f.slice(f.lastIndexOf("/") + 1));
add("collate-titles", "collate", { strings: titles });
add("collate-edge", "collate", {
  strings: ["Step 10", "Step 2", "Step 02", "step 1", "v1.10", "v1.2", "a", "A", "á", "b", "_a", "-a", " a", "a b", "a-b", "ab", "Ab",
    "Straße", "Strasse", "strasse", "Æther", "aether", "ﬁle", "file", "Ωmega", "omega", "Жук", "日本", "🎉", "", "0", "00", "007", "7",
    "x\u0301", "x", "\u200bx", "co\u00adop", "coop", "１２", "12", "①", "1", "²", "2"],
});
for (let n = 0; n < 40; n++) add(`collate-random-${n}`, "collate", { strings: Array.from({ length: 40 }, word) });

// People merged from the settings, commit authors (made up: no real emails
// in the fixtures), assignees and comment authors; and who "me" is.
const peopleSets = Object.fromEntries(
  readdirSync(join(here, "fixtures/people")).sort().map((name) => [name.replace(/\.json$/, ""), JSON.parse(read(join(here, "fixtures/people", name)))]),
);
{
  const first = ["Ada", "Alex", "Sam", "Zoë", "José", "Grace", "Lin", "Noor", "Émile", "Ola", "Kai", "Mia"];
  const last = ["Chen", "Rivera", "Núñez", "O'Brien", "Stone", "Park", "Østergård", "Kim", "Ng", "Smith"];
  const any = (list) => list[Math.floor(random() * list.length)];
  const authors = Array.from({ length: 120 }, (_, n) => {
    const name = `${any(first)} ${any(last)}`;
    const email = random() < 0.15 ? "" : `${handleLike(name)}${random() < 0.3 ? "+dev" : ""}@${any(["example.com", "example.org", "users.noreply.github.com"])}`;
    return { name: random() < 0.2 ? name.toLowerCase() : name, email, commits: 1 + Math.floor(random() * 50) + (n % 3) };
  });
  const names = authors.map((author) => author.name);
  peopleSets.random = {
    configured: [{ handle: "ada", name: "Ada Chen", email: "ada.chen@example.com", aliases: ["Ada C."] }],
    authors,
    assignees: Array.from({ length: 20 }, () => (random() < 0.5 ? any(names) : `${any(first)} ${any(last)}`)),
    commenters: Array.from({ length: 20 }, () => any(names)),
    identities: authors.slice(0, 5).map(({ name, email }) => ({ name, email })),
  };
}
function handleLike(name) {
  return name.toLowerCase().normalize("NFD").replace(/\p{M}/gu, "").replace(/[^a-z]+/g, ".");
}
for (const [name, data] of Object.entries(peopleSets)) {
  const { identities, ...sources } = data;
  add(`people-${name}`, "people.merge", { sources, identities });
}
// A plain localeCompare, as people are sorted: accents and case decide ties.
const fullPool = [..." -_.'0123456789aAbBeEéÉèêëoOóÓöÖøØsSßzZæÆœŒçÇñÑåÅ", "e\u0301", "E\u0301", "o\u0308", ..."ΩωЖж日🎉", "\u200b"];
const fullWord = () => Array.from({ length: 1 + Math.floor(random() * 5) }, () => fullPool[Math.floor(random() * fullPool.length)]).join("");
add("collate-full-names", "collate.full", { strings: ["Ada", "ada", "ADA", "Adá", "adà", "Zoë", "Zoe", "zoe", "Ægir", "aegir", "Aegir", "Straße", "strasse", "Strasse", "o\u0308", "ö", "Ö", "Øystein", "Oystein", "Óscar", "Oscar"] });
for (let n = 0; n < 20; n++) add(`collate-full-random-${n}`, "collate.full", { strings: Array.from({ length: 40 }, fullWord) });
add("collate-base-epics", "collate.base", { strings: ["10 Launch", "2 Build", "1 Plan", "Spikes", "spikes", "Épics", "epics", "0 Spikes", "02 Two", "2a", "2 b", "Ünder", "under", "_misc", "Misc"] });
for (let n = 0; n < 10; n++) add(`collate-base-random-${n}`, "collate.base", { strings: Array.from({ length: 40 }, word) });
add("people-slugs", "handle.slug", {
  texts: ["Ada Lovelace", "Zoë.O'Brien", "  --Ada--  ", "李雷", "Ægir", "Straße", "José Núñez", "ÅSA", "x".repeat(50), "a-".repeat(30), "Ⅻ", "ﬁle", "İstanbul", "ǅemal"],
});

// The content branch's .genbeya-content, read as Genbeya reads it: through
// `git config --list`, then its areas rule. Null is a branch without the file.
const areaFiles = {
  written: '# Where Genbeya keeps each area: "branch" is this content branch,\n# "checkout" is the checked-out code branch of every clone.\n[areas]\n\twiki = branch\n\ttasks = branch\n\tsettings = checkout\n\tpulls = checkout\n',
  missing: null,
  empty: "",
  crlf: "[areas]\r\n\twiki = branch\r\n\ttasks = checkout\r\n",
  "upper-case": "[AREAS]\n  WIKI = branch\n  Tasks = branch\n",
  "upper-value": "[areas]\nwiki = Branch\n",
  quoted: '[areas]\nwiki = "branch"\ntasks = "bra"nch\nsettings = " branch"\n',
  comments: "; a comment\n[areas] # trailing\nwiki = branch ; why\ntasks = branch# no space\n",
  "last-wins": "[areas]\nwiki = branch\nwiki = checkout\ntasks = checkout\ntasks = branch\n",
  subsection: '[areas "x"]\nwiki = branch\n[areas]\ntasks = branch\n',
  "old-subsection": "[areas.x]\nwiki = branch\n",
  "no-value": "[areas]\nwiki\ntasks = branch\n",
  "other-section": "[core]\nwiki = branch\n",
  continued: "[areas]\nwiki = bra\\\nnch\n",
  escapes: '[areas]\nwiki = "br\\anch"\ntasks = b\\tranch\n',
  "garbage-line": "[areas]\nwiki = branch\nthis is not config\n",
  "before-section": "wiki = branch\n[areas]\ntasks = branch\n",
  "unclosed-section": "[areas\nwiki = branch\n",
  "unclosed-quote": '[areas]\nwiki = "branch\n',
  "bad-key": "[areas]\n1wiki = branch\n",
  "spaces-in-value": "[areas]\nwiki =   branch   \ntasks = branch  thing\n",
  bom: "\ufeff[areas]\nwiki = branch\n",
  "no-newline": "[areas]\nwiki = branch",
  "section-same-line": "[areas] wiki = branch\n",
};
for (const [name, file] of Object.entries(areaFiles)) add(`areas-${name}`, "areas.parse", { file });

// Remote URLs as Genbeya reads them: which repository, without secrets.
const remotes = [
  "https://github.com/genbeya/genbeya.git", "https://github.com/genbeya/genbeya", "https://GitHub.com/Genbeya/Genbeya/",
  "http://git.example.com/team/repo.git", "https://user:secret@github.com/a/b.git?x=1#frag", "https://token@gitlab.com/group/sub/repo.git",
  "https://github.com:443/a/b", "https://github.com:8443/a/b", "https://host:99999/a/b", "https://host:abc/a/b", "https://",
  "ssh://git@github.com/genbeya/genbeya.git", "ssh://git@github.com:22/genbeya/genbeya.git", "ssh://GIT@Example.COM:2222/~/repo.git",
  "git+ssh://git@host/x/y", "ssh+git://host/x/y", "git://host.example/x.git", "ssh://[::1]:2222/srv/repo.git", "https://[2001:db8::1]/a/b",
  "git@github.com:genbeya/genbeya.git", "git@github.com:/genbeya/genbeya.git", "user@host.example:path/to/repo", "host.example:repo.git",
  "c:/Users/me/repo", "C:\\Users\\me", "/srv/repo.git", "./repo", "../repo", "file:///srv/repo.git", "ftp://host/repo",
  "ext::sh -c touch% /tmp/pwned", "transport::address", "-oProxyCommand=evil", "ssh://-oProxyCommand=evil/x",
  "https://host/a%20b/c.git", "https://host/a%zz/c", "https://host/", "https://host", "ssh://host", "git@host:", "",
  " https://github.com/a/b.git ", "https://dev.azure.com/org/project/_git/repo", "git@ssh.dev.azure.com:v3/org/project/repo",
  "https://org.visualstudio.com/DefaultCollection/project/_git/repo", "https://org.visualstudio.com/project/_git/repo",
  "ssh://vs-ssh.visualstudio.com/v3/org/project/repo", "https://bitbucket.org/team/repo.git", "https://host/a.git.git",
  "https://xn--bcher-kva.example/a/b", "https://host/a?b", "https://host/a#b", "https://user:pa:ss@host/a",
  "git@github.com:a/b.git?x", "user:pass@host:a/b", "a:b@c:d", "https://host/" + "x".repeat(2100),
];
add("remote-urls", "remote.parse", { urls: remotes });
add("remote-same", "remote.same", {
  pairs: [["https://github.com/a/b.git", "git@github.com:a/b"], ["https://github.com/A/B", "ssh://git@github.com/a/b.git"],
    ["https://github.com/a/b", "https://gitlab.com/a/b"], ["https://dev.azure.com/o/p/_git/r", "git@ssh.dev.azure.com:v3/o/p/r"],
    ["/local", "/local"], ["https://github.com/a/b", "https://github.com/a/c"]],
});

// Which content area a path belongs to (settings-engine.ts contentAreaOf).
add("areas-of-paths", "area.of", {
  settings: [{ wikiRoot: "docs", taskRoot: "tasks", pullRoot: "pulls" }, { wikiRoot: "", taskRoot: "work/tasks", pullRoot: "pulls" }, { wikiRoot: ".", taskRoot: "tasks", pullRoot: "docs/pulls" }],
  paths: [".genbeya.yml", "docs/.genbeya.yml", "docs/Home.md", "docs/images/a.png", "docsx/Home.md", "tasks/GM-1.md", "tasks/.templates/bug.md", "tasks", "pulls/PR-1.md", "pulls/.images/PR-1/a.png", "work/tasks/X-1.md", "docs/pulls/PR-2.md", "src/main.dart", "README.md"],
});

// What changed between versions of a task, for its activity: real
// consecutive versions from both repositories' history, and edge cases.
for (const set of readdirSync(join(here, "fixtures/activity")).sort()) {
  JSON.parse(read(join(here, "fixtures/activity", set))).forEach((pair, n) =>
    add(`activity-${set.replace(/\.json$/, "")}-${n}`, "task.changes", { ...pair, taskRoot: "tasks" }),
  );
}
{
  const t = (extra = "", body = "\nDo it.\n") => `---\nid: A-1\ntitle: First\nstatus: todo\n${extra}---\n${body}`;
  const comments = (...list) => `\n## Comments\n\n${list.map(([who, when, text]) => `### ${who} — ${when}\n\n${text}`).join("\n\n")}\n`;
  const log = (...lines) => `\nDo it.\n\n## Time log\n\n${lines.map((l) => `- ${l}`).join("\n")}\n`;
  const edges = {
    status: [t(), t().replace("status: todo", "status: done")],
    "priority-default": [t("priority: none\n"), t()],
    labels: [t("labels: [a, b]\n"), t("labels: [b, c, d]\n")],
    "labels-string": [t("labels: a, b\n"), t("labels: [a]\n")],
    description: [t(), t("", "\nDo it twice.\n")],
    "crlf-only": [t(), t().replace(/\n/g, "\r\n")],
    "comments-added": [t(), t("", "\nDo it.\n" + comments(["Ada", "2026-11-21 10:00", "Hi"]))],
    "comments-edited-removed": [
      t("", "\nDo it.\n" + comments(["Ada", "2026-11-21 10:00", "Hi"], ["Sam", "2026-11-21 10:00", "Yo"], ["Ada", "2026-11-21 10:00", "Again"])),
      t("", "\nDo it.\n" + comments(["Ada", "2026-11-21 10:00", "Hi!"], ["Ada", "2026-11-21 10:00", "Again"])),
    ],
    "time-log": [t("", log("2026-11-20 — Ada — 2h — Start")), t("", log("2026-11-20 — Ada — 2h — Start", "2026-11-21 — Ada — 1h — More", "2026-11-21 — Ada — 1h — More"))],
    "time-log-in-code": [t("", "\n```\n## Time log\n- x\n```\n"), t("", "\n```\n## Time log\n- y\n```\n")],
    custom: [t("estimate: 2d\ndepends_on: [A-2]\n"), t("estimate: 3d\ndepends_on: [A-2, A-3]\nmilestone: M1\n")],
    other: [t("meta:\n  a: 1\n"), t("meta:\n  a: 2\nStatus: odd\n")],
    "broken-before": [`---\nid: [oops\n---\nBody\n`, t()],
    "broken-after": [t(), `---\ntitle: [oops\n---\nDo it.\n`],
    numbers: [t("estimate: 8\n"), t("estimate: 8.5\n")],
  };
  for (const [name, [before, after]] of Object.entries(edges)) {
    add(`activity-edge-${name}`, "task.changes", { before: { path: "tasks/A-1.md", content: before }, after: { path: "tasks/A-1.md", content: after }, taskRoot: "tasks" });
  }
  add("activity-edge-created", "task.changes", { before: null, after: { path: "tasks/A-1.md", content: t() }, taskRoot: "tasks" });
  add("activity-edge-moved", "task.changes", { before: { path: "tasks/1 Plan/A-1.md", content: null }, after: { path: "tasks/2 Build/A-1.md", content: null }, taskRoot: "tasks" });
  add("activity-edge-renamed-same-epic", "task.changes", { before: { path: "tasks/A-1.md", content: null }, after: { path: "tasks/A-2.md", content: null }, taskRoot: "tasks" });
  add("activity-edge-moved-and-edited", "task.changes", { before: { path: "tasks/A-1.md", content: t() }, after: { path: "tasks/Epic/A-1.md", content: t().replace("First", "Second") }, taskRoot: "tasks" });
}

// Search: which list a file shows in, and long lines shortened around a match.
add("search-areas", "search.area", {
  settings: [{ wikiRoot: "docs", taskRoot: "tasks", pullRoot: "pulls" }, { wikiRoot: ".", taskRoot: "work/tasks", pullRoot: "docs/pulls" }],
  paths: ["docs/Home.md", "docs/a/B.MD", "docs/images/x.png", "tasks/GM-1.md", "tasks/Epic/GM-2.md", "tasks/.templates/bug.md", "tasks/notes.txt", "pulls/PR-1.md", "pulls/sub/PR-2.md", "pulls/.images/PR-1/a.png", "work/tasks/X-1.md", "docs/pulls/PR-3.md", "README.md", "src/main.dart"],
});
{
  const long = (n, c = "a") => c.repeat(n);
  const lines = [
    ["short line with board", [[16, 21]]],
    [long(300), [[0, 5]]],
    [long(300), [[150, 155]]],
    [long(300), [[290, 300]]],
    [long(300), [[10, 20], [100, 120], [250, 260]]],
    [long(300), []],
    ["😀".repeat(150) + " board", [[301, 306]]],
    [long(199) + "b", [[199, 200]]],
    [long(201), [[195, 201]]],
  ];
  add("search-excerpts", "search.excerpt", { lines: lines.map(([line, ranges]) => ({ line, ranges: ranges.map(([start, end]) => ({ start, end })) })) });
}

// Genbeya links, parsed strictly and formatted; web links per forge.
add("links-parse", "link.parse", {
  texts: [
    "genbeya://open?remote=https://github.com/genbeya/genbeya.git&task=GENBEYA-12",
    "genbeya://open/?remote=git@github.com:genbeya/genbeya.git&page=docs/Home.md",
    "GENBEYA://OPEN?remote=https%3A%2F%2Fgithub.com%2Fa%2Fb&file=src%2Fmain.ts",
    "genbeya://open?remote=https://github.com/a/b&commit=1A2B3C4D",
    " genbeya://open?remote=https://github.com/a/b&task=A-1 ",
    "genbeya://open?remote=https://github.com/a/b&page=docs/Home.txt",
    "genbeya://open?remote=https://github.com/a/b&file=../etc/passwd",
    "genbeya://open?remote=https://github.com/a/b&file=.git/config",
    "genbeya://open?remote=/srv/repo.git&task=A-1",
    "genbeya://open?remote=ext::sh%20-c%20x&task=A-1",
    "genbeya://open?remote=https://github.com/a/b&task=A-1&task=A-2",
    "genbeya://open?remote=https://github.com/a/b&task=A-1&page=docs/x.md",
    "genbeya://open?remote=https://github.com/a/b&task=-rf",
    "genbeya://open?remote=https://github.com/a/b&commit=xyz",
    "genbeya://open?remote=https://github.com/a/b&task",
    "genbeya://open?remote=https://github.com/a/b&task=A%2",
    "genbeya://open?remote=https://github.com/a/b&task=A%FF",
    "genbeya://open?remote=https://github.com/a/b&task=A-1#frag",
    "genbeya://open?task=A-1",
    "genbeya://open?remote=https://github.com/a/b",
    "genbeya://app/index.html",
    "https://github.com/a/b",
    "genbeya://open?remote=https://github.com/a/b&unknown=x",
    "genbeya://open?remote=https://github.com/a/b&file=docs/a%20b.png",
    "genbeya://open?remote=https://github.com/a/b&task=A+1",
    "genbeya://open?remote=https://github.com/a/b&page=docs/%C3%9Cber.md",
    "genbeya://open?" + "a".repeat(9000),
    "",
  ],
});
add("links-format", "link.format", {
  links: [
    { remote: "https://user:secret@github.com/a/b.git", item: { kind: "task", id: "GENBEYA-12" } },
    { remote: "git@github.com:a/b.git", item: { kind: "page", path: "docs/Getting started.md" } },
    { remote: "https://github.com/a/b", item: { kind: "file", path: "src/ä ö/x?.ts" } },
    { remote: "https://github.com/a/b", item: { kind: "commit", hash: "1a2b3c4d5e" } },
  ],
});
add("web-urls", "web.url", {
  files: [
    ["https://github.com/a/b.git", "docs/Home.md", "main"],
    ["git@gitlab.com:group/sub/repo.git", "src/a b.ts", "feature/x"],
    ["https://bitbucket.org/team/repo", "README.md", "develop"],
    ["https://dev.azure.com/org/proj/_git/repo", "docs/Home.md", "main"],
    ["http://gitlab.example.com/a/b", "x.md", "main"],
    ["https://example.com/a/b", "x.md", "main"],
    ["/srv/repo", "x.md", "main"],
  ],
  commits: [["https://github.com/a/b", "abc123"], ["git@gitlab.com:a/b", "abc123"], ["https://bitbucket.org/a/b", "abc"], ["https://dev.azure.com/o/p/_git/r", "abc"], ["https://example.com/a/b", "abc"]],
});

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
