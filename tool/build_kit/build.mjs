// Builds the kit (docs/Upstream/Kit-build.md) into kit/dist from Genbeya's sources at the
// commit in kit/GENBEYA_REF, with Genbeya's own esbuild and the settings of its VS Code
// webview bundle. Usage: node build.mjs [--check]
//   GENBEYA_SOURCE  where to clone Genbeya from (default https://github.com/genbeya/genbeya.git)
//   --check         also type-check kit/src with Genbeya's TypeScript
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";
import zlib from "node:zlib";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../..");
const kit = path.join(repo, "kit");
const dist = path.join(kit, "dist");
const ref = fs.readFileSync(path.join(kit, "GENBEYA_REF"), "utf8").trim();
if (!/^[0-9a-f]{40}$/.test(ref)) throw new Error(`kit/GENBEYA_REF must hold a full commit ID, not "${ref}".`);
const source = process.env.GENBEYA_SOURCE ?? "https://github.com/genbeya/genbeya.git";
const cache = path.join(here, ".cache", `genbeya-${ref.slice(0, 12)}`);

const run = (command, args, options = {}) => execFileSync(command, args, { stdio: "inherit", ...options });
const quiet = (command, args) => {
  try {
    execFileSync(command, args, { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
};

// 1. Genbeya at the pinned commit, with its dependencies installed without scripts
//    (Electron's binary and node-pty aren't needed to bundle the kit).
if (!fs.existsSync(path.join(cache, ".git"))) run("git", ["clone", "--quiet", "--no-checkout", source, cache]);
if (!quiet("git", ["-C", cache, "cat-file", "-e", `${ref}^{commit}`])) run("git", ["-C", cache, "fetch", "--quiet", source, ref]);
run("git", ["-C", cache, "checkout", "--quiet", "--detach", ref]);
const lock = createHash("sha256").update(fs.readFileSync(path.join(cache, "package-lock.json"))).digest("hex");
const stamp = path.join(cache, "node_modules", ".kit-lock");
if (!fs.existsSync(stamp) || fs.readFileSync(stamp, "utf8") !== lock) {
  run("npm", ["ci", "--ignore-scripts", "--no-audit", "--no-fund"], { cwd: cache, env: { ...process.env, ELECTRON_SKIP_BINARY_DOWNLOAD: "1" } });
  fs.writeFileSync(stamp, lock);
}

const requireGenbeya = createRequire(path.join(cache, "package.json"));
const esbuild = requireGenbeya("esbuild");
const genbeya = JSON.parse(fs.readFileSync(path.join(cache, "package.json"), "utf8"));
const policy = await contentSecurityPolicy();

// 2. Optional type check of kit/src against Genbeya's sources.
if (process.argv.includes("--check")) typeCheck();

// 3. The bundle, with the esbuild settings of vscodeWebviewBundle in Genbeya's scripts/bundles.mjs.
fs.rmSync(dist, { recursive: true, force: true });
const started = Date.now();
const result = await esbuild.build({
  bundle: true,
  logLevel: "warning",
  legalComments: "none",
  platform: "browser",
  format: "esm",
  target: "es2022",
  splitting: true,
  minify: true,
  loader: { ".woff2": "file", ".woff": "file" },
  entryPoints: [
    { in: path.join(kit, "src/kit.ts"), out: "kit" },
    { in: path.join(kit, "src/kit.css"), out: "kit" },
  ],
  outdir: dist,
  chunkNames: "chunks/[name]-[hash]",
  assetNames: "fonts/[name]-[hash]",
  alias: { genbeya: path.join(cache, "src") },
  nodePaths: [path.join(cache, "node_modules")],
  define: { GENBEYA_VERSION: JSON.stringify(genbeya.version) },
  metafile: true,
  plugins: [angularFreeEditor()],
});
const elapsed = Date.now() - started;

// 4. PlantUML's engine, the page, the licenses and the manifest.
fs.copyFileSync(path.join(cache, "node_modules/@rockuml/core/rockuml.wasm"), path.join(dist, "rockuml.wasm"));
fs.writeFileSync(path.join(dist, "kit.html"), page(policy));
fs.writeFileSync(path.join(dist, "LICENSES.txt"), licenses(result.metafile));
const files = listFiles(dist).map((file) => {
  const bytes = fs.readFileSync(path.join(dist, file));
  return { path: file, sha256: createHash("sha256").update(bytes).digest("hex"), bytes: bytes.length };
});
const manifest = { name: "genbeya-kit", genbeya: genbeya.version, commit: ref, protocol: protocolVersion(), files };
fs.writeFileSync(path.join(dist, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);

// 5. What it weighs.
const size = (list) => list.reduce((sum, file) => sum + file.bytes, 0);
const gzip = (list) => list.reduce((sum, file) => sum + zlib.gzipSync(fs.readFileSync(path.join(dist, file.path)), { level: 9 }).length, 0);
// What the first page loads: kit.html, kit.css, kit.js and the chunks it imports statically.
const loaded = new Set(["kit.html", "kit.css"]);
const follow = (output) => {
  const name = path.relative(dist, path.resolve(output));
  if (loaded.has(name)) return;
  loaded.add(name);
  for (const { path: next, kind } of result.metafile.outputs[output]?.imports ?? []) if (kind === "import-statement") follow(next);
};
follow(path.relative(process.cwd(), path.join(dist, "kit.js")));
const initial = files.filter((file) => loaded.has(file.path));
const kb = (bytes) => `${(bytes / 1024).toFixed(0)} kB`;
console.log(`Kit for Genbeya ${genbeya.version} (${ref.slice(0, 7)}), protocol ${manifest.protocol}, built in ${elapsed} ms`);
console.log(`  first load (${initial.length} files: kit.html, kit.css, kit.js and its static imports): ${kb(size(initial))}, ${kb(gzip(initial))} gzipped`);
console.log(`  everything (${files.length} files): ${kb(size(files))}, ${kb(gzip(files))} gzipped`);

/** Genbeya's editor modules reach Angular only through two helpers; the kit gets plain versions of them. */
function angularFreeEditor() {
  const shims = { "core/hotkeys": "hotkeys.ts", "ui/icon": "icon.ts" };
  return {
    name: "angular-free-editor",
    setup(build) {
      build.onResolve({ filter: /\/(core\/hotkeys|ui\/icon)$/ }, (args) => {
        if (!args.importer.startsWith(path.join(cache, "src", "client", "app", "editor"))) return undefined;
        const name = Object.keys(shims).find((key) => args.path.endsWith(key));
        return { path: path.join(kit, "src", "shims", shims[name]) };
      });
    },
  };
}

/** CONTENT_SECURITY_POLICY of src/shells/content-security-policy.ts, read from the source itself. */
async function contentSecurityPolicy() {
  const ts = fs.readFileSync(path.join(cache, "src/shells/content-security-policy.ts"), "utf8");
  const { code } = await esbuild.transform(ts, { loader: "ts", format: "esm" });
  const module = await import(`data:text/javascript;base64,${Buffer.from(code).toString("base64")}`);
  // frame-ancestors only works as a header; browsers ignore it, with a warning, in a meta tag.
  return module.CONTENT_SECURITY_POLICY.split("; ")
    .filter((directive) => !directive.startsWith("frame-ancestors"))
    .join("; ");
}

function protocolVersion() {
  const match = /export const PROTOCOL = (\d+);/.exec(fs.readFileSync(path.join(kit, "src/protocol.ts"), "utf8"));
  if (!match) throw new Error("kit/src/protocol.ts has no PROTOCOL.");
  return Number(match[1]);
}

function page(csp) {
  return `<!doctype html>
<html lang="en" data-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta http-equiv="Content-Security-Policy" content="${csp}">
<title>Genbeya kit</title>
<link rel="stylesheet" href="kit.css">
<script type="module" src="kit.js"></script>
</head>
<body data-rockuml="rockuml.wasm">
<main id="preview"></main>
<div id="editor" hidden></div>
</body>
</html>
`;
}

/** Genbeya's license, and the license of every package the bundle holds code of. */
function licenses(metafile) {
  const packages = new Map();
  for (const input of Object.keys(metafile.inputs)) {
    const match = /node_modules\/((?:@[^/]+\/)?[^/]+)\//.exec(input);
    if (match) packages.set(match[1], path.join(cache, "node_modules", match[1]));
  }
  const sections = [
    `Genbeya ${genbeya.version} (${ref})\nhttps://github.com/genbeya/genbeya\n\n${fs.readFileSync(path.join(cache, "LICENSE.md"), "utf8").trim()}`,
  ];
  for (const [name, dir] of [...packages].sort(([a], [b]) => a.localeCompare(b))) {
    const meta = JSON.parse(fs.readFileSync(path.join(dir, "package.json"), "utf8"));
    const file = fs.readdirSync(dir).find((entry) => /^(licen[cs]e|copying)(\.|$)/i.test(entry));
    const text = file ? fs.readFileSync(path.join(dir, file), "utf8").trim() : `License: ${meta.license ?? "unknown"} (no license file in the package)`;
    sections.push(`${name} ${meta.version}\n\n${text}`);
  }
  return `${sections.join(`\n\n${"-".repeat(72)}\n\n`)}\n`;
}

function listFiles(dir, prefix = "") {
  return fs
    .readdirSync(dir, { withFileTypes: true })
    .flatMap((entry) => (entry.isDirectory() ? listFiles(path.join(dir, entry.name), `${prefix}${entry.name}/`) : [`${prefix}${entry.name}`]))
    .filter((file) => file !== "manifest.json")
    .sort();
}

function typeCheck() {
  const config = path.join(here, ".cache", "tsconfig.kit.json");
  fs.writeFileSync(
    config,
    JSON.stringify(
      {
        extends: path.join(cache, "tsconfig.json"),
        compilerOptions: {
          noEmit: true,
          paths: { "genbeya/*": [path.join(cache, "src/*")], "@rockuml/core": [path.join(cache, "node_modules/@rockuml/core/rockuml.d.ts")], "*": [path.join(cache, "node_modules/*"), path.join(cache, "node_modules/@types/*")] },
          typeRoots: [path.join(cache, "node_modules/@types")],
          types: [],
          lib: ["es2022", "dom", "dom.iterable"],
        },
        include: [path.join(kit, "src/**/*.ts")],
        files: [],
      },
      null,
      2,
    ),
  );
  run(process.execPath, [requireGenbeya.resolve("typescript/bin/tsc"), "-p", config]);
}
