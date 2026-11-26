// Puts Genbeya's kit (its Markdown renderer and editor for web views; docs/Architecture/Kit.md in
// Genbeya) into kit/dist, and checks it before the app may ship it.
//
//   node build.mjs                 the release in kit/GENBEYA_KIT: genbeya-kit-<version>.zip,
//                                  downloaded once into .cache, its SHA-256 as pinned there
//   node build.mjs --source <ref>  Genbeya's own `npm run build:kit` at a branch, tag or commit
//                                  (the nightly drift job builds develop this way)
//   GENBEYA_SOURCE                 where to clone Genbeya from (default https://github.com/genbeya/genbeya.git)
//
// Either way the result must match its manifest.json file by file (SHA-256 and size, nothing
// missing, nothing more) and speak the protocol this app does (lib/access/kit/kit_protocol.dart).
// A release must also come from the commit in kit/GENBEYA_REF, which the conformance cases use,
// so that the renderer and the engines are of one Genbeya version.
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../..");
const kit = path.join(repo, "kit");
const dist = path.join(kit, "dist");
const cacheRoot = path.join(here, ".cache");
const PROTOCOL = protocolOfApp();

const run = (command, args, options = {}) => execFileSync(command, args, { stdio: "inherit", ...options });
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

const sourceAt = process.argv.indexOf("--source");
const started = Date.now();
fs.rmSync(dist, { recursive: true, force: true });
// The app declares these folders as assets; the placeholders keep them in Git.
process.on("exit", () => {
  for (const folder of [dist, path.join(dist, "chunks"), path.join(dist, "fonts")]) {
    fs.mkdirSync(folder, { recursive: true });
    fs.writeFileSync(path.join(folder, ".gitkeep"), "");
  }
});

let from;
if (sourceAt >= 0) {
  const ref = process.argv[sourceAt + 1];
  if (!ref || ref.startsWith("-")) throw new Error("--source needs a branch, tag or commit of Genbeya.");
  from = buildFromSource(ref);
} else {
  from = await downloadRelease();
}
const manifest = verify(dist);
if (sourceAt < 0) {
  const pinned = fs.readFileSync(path.join(kit, "GENBEYA_REF"), "utf8").trim();
  if (manifest.commit !== pinned)
    throw new Error(`The kit comes from ${manifest.commit}, but kit/GENBEYA_REF pins ${pinned}: pin both to the same release.`);
}
const bytes = manifest.files.reduce((sum, file) => sum + file.bytes, 0);
console.log(
  `Kit of Genbeya ${manifest.genbeya} (${manifest.commit.slice(0, 7)}), protocol ${manifest.protocol}, ${from}: ` +
    `${manifest.files.length} files, ${(bytes / 1024 / 1024).toFixed(1)} MB, checked against its manifest in ${Date.now() - started} ms`,
);

/** The release zip named in kit/GENBEYA_KIT, from the cache or downloaded, unpacked into kit/dist. */
async function downloadRelease() {
  const pin = JSON.parse(fs.readFileSync(path.join(kit, "GENBEYA_KIT"), "utf8"));
  for (const key of ["version", "url", "sha256"]) if (typeof pin[key] !== "string") throw new Error(`kit/GENBEYA_KIT needs "${key}".`);
  if (!/^[0-9a-f]{64}$/.test(pin.sha256)) throw new Error("kit/GENBEYA_KIT: sha256 must be 64 hex digits.");
  if (!pin.url.startsWith("https://github.com/genbeya/genbeya/releases/download/"))
    throw new Error("kit/GENBEYA_KIT: the kit comes from a Genbeya release.");
  fs.mkdirSync(cacheRoot, { recursive: true });
  const zip = path.join(cacheRoot, `genbeya-kit-${pin.version}.zip`);
  const valid = () => fs.existsSync(zip) && sha256(fs.readFileSync(zip)) === pin.sha256;
  if (!valid()) {
    const response = await fetch(pin.url, { redirect: "follow" });
    if (!response.ok) throw new Error(`Downloading ${pin.url}: ${response.status} ${response.statusText}`);
    fs.writeFileSync(zip, Buffer.from(await response.arrayBuffer()));
    if (!valid()) {
      const got = sha256(fs.readFileSync(zip));
      fs.rmSync(zip);
      throw new Error(`${pin.url} has SHA-256 ${got}, not ${pin.sha256} as kit/GENBEYA_KIT pins: refused.`);
    }
  }
  fs.mkdirSync(dist, { recursive: true });
  // unzip refuses entries that would land outside the folder; verify() then refuses anything unlisted.
  run("unzip", ["-q", "-o", zip, "-d", dist]);
  return `release ${pin.version}`;
}

/** Genbeya's own kit build at `ref`, copied into kit/dist. */
function buildFromSource(ref) {
  const source = process.env.GENBEYA_SOURCE ?? "https://github.com/genbeya/genbeya.git";
  const checkout = path.join(cacheRoot, "genbeya-source");
  if (!fs.existsSync(path.join(checkout, ".git"))) run("git", ["clone", "--quiet", "--no-checkout", source, checkout]);
  run("git", ["-C", checkout, "fetch", "--quiet", "--tags", source, ref]);
  run("git", ["-C", checkout, "checkout", "--quiet", "--detach", "FETCH_HEAD"]);
  const env = { ...process.env, ELECTRON_SKIP_BINARY_DOWNLOAD: "1" };
  run("npm", ["ci", "--ignore-scripts", "--no-audit", "--no-fund"], { cwd: checkout, env });
  run("npm", ["run", "build:kit"], { cwd: checkout, env });
  fs.cpSync(path.join(checkout, "dist", "kit"), dist, { recursive: true });
  return `built from ${ref}`;
}

/** kit/dist as its manifest describes it, or an error saying what differs. */
function verify(dir) {
  const manifest = JSON.parse(fs.readFileSync(path.join(dir, "manifest.json"), "utf8"));
  if (manifest.name !== "genbeya-kit") throw new Error("manifest.json is not a Genbeya kit's.");
  if (manifest.protocol !== PROTOCOL) throw new Error(`The kit speaks protocol ${manifest.protocol}; this app speaks ${PROTOCOL}.`);
  if (!/^[0-9a-f]{40}$/.test(manifest.commit ?? "")) throw new Error("manifest.json names no commit.");
  const listed = new Map(manifest.files.map((file) => [file.path, file]));
  const present = listFiles(dir).filter((file) => file !== "manifest.json" && !file.endsWith(".gitkeep"));
  const problems = [];
  for (const file of present) {
    const entry = listed.get(file);
    if (!entry) {
      problems.push(`${file} is not in the manifest`);
      continue;
    }
    const content = fs.readFileSync(path.join(dir, file));
    if (content.length !== entry.bytes || sha256(content) !== entry.sha256) problems.push(`${file} differs from the manifest`);
    listed.delete(file);
  }
  for (const file of listed.keys()) problems.push(`${file} is missing`);
  for (const required of ["kit.html", "kit.js", "kit.css"]) if (!present.includes(required)) problems.push(`${required} is missing`);
  if (problems.length) throw new Error(`The kit doesn't match its manifest:\n  ${problems.slice(0, 20).join("\n  ")}`);
  return manifest;
}

/** The protocol the app's host speaks, read from its source, so the two can't drift apart. */
function protocolOfApp() {
  const source = fs.readFileSync(path.join(repo, "lib/access/kit/kit_protocol.dart"), "utf8");
  const match = /^const kitProtocol = (\d+);/m.exec(source);
  if (!match) throw new Error("lib/access/kit/kit_protocol.dart has no kitProtocol.");
  return Number(match[1]);
}

function listFiles(dir, prefix = "") {
  return fs
    .readdirSync(dir, { withFileTypes: true })
    .flatMap((entry) => (entry.isDirectory() ? listFiles(path.join(dir, entry.name), `${prefix}${entry.name}/`) : [`${prefix}${entry.name}`]))
    .sort();
}
