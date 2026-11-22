// Writes fixtures/activity/<repository>.json: consecutive versions of task
// files from real history (contents only), for the task.changes cases.
// Run once when refreshing fixtures:
//
//   node make-activity-fixtures.mjs <genbeya checkout at kit/GENBEYA_REF>
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const git = (dir, ...args) => execFileSync("git", ["-C", dir, ...args], { encoding: "utf8", maxBuffer: 64 << 20 });
const show = (dir, spec) => {
  try {
    return git(dir, "show", spec);
  } catch {
    return null;
  }
};

function pairs(dir, root, perFile, total) {
  const files = git(dir, "ls-tree", "-r", "--name-only", "HEAD", "--", root).split("\n").filter((f) => f.endsWith(".md") && !f.includes("/.templates/"));
  const out = [];
  for (const file of files) {
    // Commit, then the path at that commit (renames followed).
    const log = git(dir, "log", "--follow", "--no-merges", "--format=%H", "--name-status", "-M", "--", file).split("\n");
    const versions = [];
    let commit = null;
    for (const line of log) {
      if (/^[0-9a-f]{40}$/.test(line)) commit = line;
      else if (commit && line.trim()) {
        const parts = line.split("\t");
        const status = parts[0];
        const path = parts.at(-1);
        const oldPath = status.startsWith("R") ? parts[1] : status === "A" ? null : path;
        versions.push({ commit, path, oldPath });
        commit = null;
      }
    }
    for (const version of versions.slice(0, perFile)) {
      const after = show(dir, `${version.commit}:${version.path}`);
      if (after === null) continue;
      const before = version.oldPath === null ? null : show(dir, `${version.commit}^:${version.oldPath}`);
      out.push({ before: version.oldPath === null ? null : { path: version.oldPath, content: before }, after: { path: version.path, content: after } });
      if (out.length >= total) return out;
    }
  }
  return out;
}

const genbeya = process.argv[2];
if (!genbeya) throw new Error("Pass a Genbeya checkout.");
mkdirSync(join(here, "fixtures/activity"), { recursive: true });
const sets = { genbeya: pairs(genbeya, "tasks", 3, 120), mobile: pairs(join(here, "../.."), "tasks", 4, 80) };
for (const [name, list] of Object.entries(sets)) {
  writeFileSync(join(here, "fixtures/activity", `${name}.json`), JSON.stringify(list, null, 1) + "\n");
  console.log(`${name}: ${list.length} pairs`);
}
