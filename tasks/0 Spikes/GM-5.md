---
id: GM-5
title: Build the conformance harness
type: chore
status: review
priority: high
estimate: 2d
remaining: 2d
milestone: M0
depends_on: [GM-1]
---

The check that keeps the Dart engines writing exactly what Genbeya writes. See [[Architecture#conformance]].

- [x] `tool/conformance/cases/`: fixture files and edits as JSON
- [x] A Node script that runs each case through Genbeya's engines at `kit/GENBEYA_REF` and writes the expected output
- [x] A Dart test that runs the same cases and compares, byte for byte for files
- [x] First cases: read `.genbeya.yml` with defaults; change one task field in a file with YAML comments, CRLF and a BOM
- [x] CI runs it on push (passed on GitHub, with Genbeya checked out at the pinned commit)
- [x] A nightly job runs it against Genbeya's `develop` and reports drift (`.github/workflows/drift.yml`; first night 2026-11-22: no drift)

Result: 425 cases (settings, task parsing, seven kinds of task update over 101 real and hand-made task files) pass byte for byte against Genbeya `82e9002`. The writer is a port of the `yaml` library's (`lib/engines/yaml/yaml_document.dart`). The harness also found what Genbeya's updates change beyond the edited field: see [[Upstream]].
