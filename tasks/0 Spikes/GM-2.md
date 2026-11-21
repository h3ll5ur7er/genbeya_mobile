---
id: GM-2
title: "Spike: Git on the device with a Rust core"
type: spike
status: in-progress
priority: urgent
estimate: 4d
remaining: 4d
milestone: M0
depends_on: [GM-1]
---

Prove that a phone can do what the app needs from Git, before anything is built on it. See [[Architecture#git-on-the-device]].

Done when, on a real Android phone and a real iPhone, a test screen can do each step against a private GitHub repository over HTTPS and over SSH:

- [ ] Rust crate `native/genbeya_core` with `git2` (vendored libgit2, OpenSSL, libssh2), bound with flutter_rust_bridge
- [ ] Shallow single-branch clone of genbeya/genbeya; time and size noted
- [ ] Commit a changed file without a staging step
- [ ] Fetch, rebase the local commit onto the remote, push
- [ ] Commit onto another branch's tree without checking it out (for the content branch)
- [ ] `log` for one path, `diff` from a merge base, `merge-tree` style conflict check
- [ ] In-memory rebase that leaves the working tree alone until it succeeds
- [ ] `core.symlinks=false`, no submodules or LFS; stale lock files after the app is killed
- [ ] Note the build steps and what broke; if the Rust core doesn't clone, commit and push on both platforms within 2 days, switch to `git2dart` (D3 in [[Decisions]])
