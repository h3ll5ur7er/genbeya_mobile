/**
 * A repository laid out by Genbeya desktop itself ([[GM-15]]): its own
 * ContentStore, from the checkout generate.mjs points the `genbeya` alias at,
 * moves the tasks and the wiki onto the content branch, edits both there
 * and syncs, as a user does in the app. What the remote then holds is
 * written out with `git fast-export`, for test/sync_flow_test.dart to import
 * and give the phone.
 *
 * Every commit's author, committer and date are fixed, so the export, and
 * the commit IDs `git fast-import` makes of it, are the same on every run.
 */
import { ContentStore } from "genbeya/src/access/content/content-store";
import { FileStore } from "genbeya/src/access/files/file-store";
import { Git } from "genbeya/src/access/git/git";
import { LocalHost } from "genbeya/src/access/hosts/local-host";
import { nodeMachine } from "genbeya/src/platforms/node/node-machine";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

/** The checked-out branch's files before anything moves. */
export const DESKTOP_FILES: Readonly<Record<string, string>> = {
  ".genbeya.yml": "name: Desk Project\ntaskPrefix: DP\n",
  "docs/Home.md": "# Home\n\nWelcome.\n",
  "docs/Guide.md": "# Guide\n\n- [ ] Read it\n",
  "tasks/DP-1.md": "---\nid: DP-1\ntitle: First\nstatus: todo\n---\n\nDo it.\n",
  "tasks/Auth/DP-2.md": "---\nid: DP-2\ntitle: Sign in\nstatus: todo\n---\n",
  "src/app.ts": "export const app = 1;\n",
};

/** Each step's commits are made at the next of these times. */
let step = 0;
function at() {
  const date = new Date(Date.UTC(2026, 10, 20, 9, step++)).toISOString();
  process.env.GIT_AUTHOR_DATE = date;
  process.env.GIT_COMMITTER_DATE = date;
}

export async function desktopRepository(): Promise<string> {
  const saved = { ...process.env };
  const tmp = mkdtempSync(join(tmpdir(), "desktop-layout-"));
  try {
    // Who commits, for every git call desktop makes as well as these.
    Object.assign(process.env, {
      GIT_AUTHOR_NAME: "Desk",
      GIT_AUTHOR_EMAIL: "desk@example.com",
      GIT_COMMITTER_NAME: "Desk",
      GIT_COMMITTER_EMAIL: "desk@example.com",
      GIT_CONFIG_GLOBAL: "/dev/null",
      GIT_CONFIG_NOSYSTEM: "1",
    });
    const remote = join(tmp, "remote.git");
    const desk = join(tmp, "desk");
    const git = (cwd: string, ...args: string[]) => execFileSync("git", args, { cwd, encoding: "utf8" });
    mkdirSync(desk);
    git(tmp, "init", "-q", "--bare", "-b", "main", remote);
    git(desk, "init", "-q", "-b", "main");
    git(desk, "config", "core.autocrlf", "false");
    for (const [path, text] of Object.entries(DESKTOP_FILES)) {
      mkdirSync(dirname(join(desk, path)), { recursive: true });
      writeFileSync(join(desk, path), text);
    }
    at();
    git(desk, "add", "-A");
    git(desk, "commit", "-q", "-m", "Initial commit");
    git(desk, "remote", "add", "origin", remote);
    git(desk, "push", "-q", "-u", "origin", "main");

    // As the app's Settings does it: the tasks, then the wiki, onto the content branch.
    const host = new LocalHost(nodeMachine());
    const root = host.paths.normalize(desk);
    const store = new ContentStore(host, new Git(host, root), new FileStore(host, root));
    at();
    await store.setStorage("tasks", "branch", "tasks");
    at();
    await store.setStorage("wiki", "branch", "docs");

    // Edits where the areas live now, recorded as the app records them.
    const edit = async (area: "tasks" | "wiki", path: string, text: string, message: string) => {
      const { files } = await store.locate(area);
      await files.write(path, text, await files.versionOf(path));
      at();
      await store.record(area, [path], message);
    };
    await edit("tasks", "tasks/DP-1.md", DESKTOP_FILES["tasks/DP-1.md"].replace("status: todo", "status: in-progress"), "Update DP-1: First");
    await edit("wiki", "docs/Home.md", "# Home\n\nWelcome, from the content branch.\n", "Edit docs/Home.md");
    at();
    await store.sync();

    return git(remote, "fast-export", "--all", "--signed-tags=strip");
  } finally {
    for (const key of Object.keys(process.env)) if (!(key in saved)) delete process.env[key];
    Object.assign(process.env, saved);
    rmSync(tmp, { recursive: true, force: true });
  }
}
