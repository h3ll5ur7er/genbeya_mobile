---
id: GM-6
title: Repositories, cloning and signing in
type: feature
status: in-progress
priority: high
estimate: 4d
remaining: 4d
milestone: M1
depends_on: [GM-2]
---

The start screen and everything needed to get a repository onto the phone. See [[Experience#navigation]] and [[Experience#signing-in]].

- [x] Repositories screen: clones with branch, unsynced edits, last sync, size; **Remove clone** (warns when unsynced commits would go)
- [x] Clone from a URL; choose the branch; shallow by default; fetch the content branch (`genbeya` or `genbeya.branch`) too when the remote has it, which a single-branch clone otherwise leaves out (`genbeya`: a clone can't read `genbeya.branch` before it exists)
- [x] HTTPS token in the keychain; SSH key made on the device with the public key to copy; host key trust on first use
- [ ] GitHub and GitLab device-flow sign-in, ending in a token
- [x] Git name and email per repository (the last one used fills in the next clone; from the forge account once signing in exists)

Built (2026-11-22): the core lists a remote's branches before cloning, clones extra branches the remote has (the content branch) at the same depth, writes a clone's config, and makes Ed25519 keys; a flow test clones and pushes over SSH against a local `sshd` with such a key (unknown host key asked about with its fingerprint, a changed one refused, a stranger's key an auth failure). `RepositoriesManager` keeps clones in the app's storage (`repositories.json`; tokens and the private key in the keychain; trusted host keys and the public key in `remote-settings.json`), checks addresses with Genbeya's `parseRemote` (61 conformance cases) and strips credentials from them. Screens: **Repositories** (pull to refresh, remove, Git identity, the phone's SSH key, the spikes), **Add a repository** (address; public, token or SSH key; branch, depth, identity; progress and cancel; host key prompt), and an interim repository summary from the model until [[GM-8]] and [[GM-9]]. Left: device-flow sign-in, which needs an OAuth app registered at GitHub and GitLab.

