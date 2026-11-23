// Writes expected/<case>.json: what Genbeya's engines, at the commit in
// kit/GENBEYA_REF, produce for each case in cases/. The Dart tests in
// test/conformance_test.dart must produce the same.
//
//   GENBEYA_SRC=/path/to/genbeya-checkout node generate.mjs
//
// Without GENBEYA_SRC, Genbeya is cloned into .cache/ at that commit.
// Comments are signed in local time: the cases are written in UTC.
process.env.TZ = "UTC";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { build } from "esbuild";

const here = dirname(fileURLToPath(import.meta.url));
// `--ref develop` runs the cases against another Genbeya commit or branch,
// for the nightly drift check; expected/ is then written but not committed.
const refArg = process.argv.indexOf("--ref");
const ref = refArg > 0 ? process.argv[refArg + 1] : readFileSync(join(here, "../../kit/GENBEYA_REF"), "utf8").trim();
const git = (...args) => execFileSync("git", args, { encoding: "utf8" }).trim();

function source() {
  if (process.env.GENBEYA_SRC) {
    const head = git("-C", process.env.GENBEYA_SRC, "rev-parse", "HEAD");
    if (refArg < 0 && head !== ref) throw new Error(`GENBEYA_SRC is at ${head}, kit/GENBEYA_REF names ${ref}.`);
    return resolve(process.env.GENBEYA_SRC);
  }
  const dir = join(here, ".cache", `genbeya-${ref}`);
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
    git("-C", dir, "init", "-q");
    git("-C", dir, "fetch", "-q", "--depth", "1", "https://github.com/genbeya/genbeya.git", ref);
    git("-C", dir, "checkout", "-q", "FETCH_HEAD");
  }
  return dir;
}

const src = source();
const bundle = join(here, ".cache", "runner.cjs");
await build({
  entryPoints: [join(here, "runner.ts")],
  bundle: true,
  platform: "node",
  format: "cjs",
  outfile: bundle,
  alias: { genbeya: src },
  nodePaths: [join(here, "node_modules")],
  logLevel: "warning",
  plugins: [angularStub()],
});

// The runner imports one plain function from a client module that also uses
// Angular, rxjs and (through it) @noble/hashes, none of which that function
// needs: they are replaced by a stub whose every export is a no-op. Anything
// else a case needs and can't resolve still fails the build.
function angularStub() {
  return {
    name: "angular-stub",
    setup(build) {
      build.onResolve({ filter: /^(@angular\/|rxjs($|\/)|@noble\/hashes\/)/ }, (args) => ({ path: args.path, namespace: "angular-stub" }));
      build.onLoad({ filter: /.*/, namespace: "angular-stub" }, () => ({
        // esbuild's interop copies a module's own names and keeps its prototype,
        // so the stub answers every name through its prototype.
        contents:
          "function noop() { return noop; } const any = new Proxy({}, { get: () => noop });" +
          "module.exports = new Proxy({}, { get: () => noop, getPrototypeOf: () => any });",
        loader: "js",
      }));
    },
  };
}
const { runCase } = createRequire(import.meta.url)(bundle);

const out = join(here, "expected");
rmSync(out, { recursive: true, force: true });
mkdirSync(out);
let count = 0;
for (const name of readdirSync(join(here, "cases")).filter((n) => n.endsWith(".json")).sort()) {
  const c = JSON.parse(readFileSync(join(here, "cases", name), "utf8"));
  writeFileSync(join(out, name), JSON.stringify({ genbeya: refArg > 0 ? `${ref}` : ref, ...runCase(c) }, null, 2) + "\n");
  count++;
}
console.log(`${count} cases from Genbeya ${ref.slice(0, 7)}`);
