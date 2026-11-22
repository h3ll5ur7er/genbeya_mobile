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

- [ ] Repositories screen: clones with branch, unsynced edits, last sync, size; **Remove clone**
- [ ] Clone from a URL; choose the branch; shallow by default; fetch the content branch (`genbeya` or `genbeya.branch`) too when the remote has it, which a single-branch clone otherwise leaves out
- [ ] HTTPS token in the keychain; SSH key made on the device with the public key to copy; host key trust on first use
- [ ] GitHub and GitLab device-flow sign-in, ending in a token
- [ ] Git name and email per repository
