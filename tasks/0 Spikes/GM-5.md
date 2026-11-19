---
id: GM-5
title: Build the conformance harness
type: chore
status: todo
priority: high
estimate: 2d
remaining: 2d
milestone: M0
depends_on: [GM-1]
---

The check that keeps the Dart engines writing exactly what Genbeya writes. See [[Architecture#conformance]].

- [ ] `tool/conformance/cases/`: fixture files and edits as JSON
- [ ] A Node script that runs each case through Genbeya's engines at `kit/GENBEYA_REF` and writes the expected output
- [ ] A Dart test that runs the same cases and compares, byte for byte for files
- [ ] First cases: read `.genbeya.yml` with defaults; change one task field in a file with YAML comments, CRLF and a BOM
- [ ] CI runs it on push; a nightly job runs it against Genbeya's `develop` and reports drift
