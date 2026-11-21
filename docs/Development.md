# Development

How to build, test and run the app. The plan behind it is in [[Architecture]] and [[Roadmap]].

[TOC]

## Requirements

| Tool | Version | For |
| --- | --- | --- |
| Flutter | 3.50.1 (Dart 3.14) | The app |
| Android SDK | Platform 36, build tools 36.0.0, NDK 28.2.13676358 (Flutter's default) | Android builds |
| Java | 21 | Gradle 9.5 and the Android Gradle plugin 9.3 |
| Xcode | Current, on macOS | iOS builds |
| Rust | Stable | The Git core ([[GM-2]]) |
| Node.js | 22 or 24 | Building the kit ([[GM-3]]), which the app needs, and the conformance cases ([[GM-5]]) |

## Commands

```bash
(cd tool/build_kit && node build.mjs)   # the kit, into kit/dist; `node test.mjs` checks it
flutter pub get
dart format lib test          # CI fails on unformatted code
flutter analyze
flutter test
flutter build apk --debug     # Android
flutter build ios --debug --no-codesign   # iOS, on macOS
```

## Tests

- `test/conformance_test.dart` runs every case in `tool/conformance/cases/` through the Dart engines and compares with what Genbeya's own engines produced, byte for byte for files ([[Architecture#conformance]]).
- `test/layers_test.dart` keeps Flutter out of `lib/contracts`, `lib/engines`, `lib/access` and `lib/managers`, so they can run headless and mirror Genbeya's engines ([[Architecture]]).
- `test/widget_test.dart` opens the app.

## Conformance

`tool/conformance/` keeps the Dart engines writing exactly what Genbeya writes:

| Path | Holds |
| --- | --- |
| `fixtures/` | Real files: every task of Genbeya and of this repository at the time, both `.genbeya.yml`, and hand-made edge cases (BOM, CRLF, YAML comments, quoting, block lists, comments, time logs) |
| `make-cases.mjs` | Turns the fixtures into `cases/`: settings parsed; tasks parsed, their status moved, and for the edge cases and every fourth task also priority, a field, a list field, a label, no type and a new title |
| `runner.ts`, `generate.mjs` | Run each case through Genbeya's engines at the commit in `kit/GENBEYA_REF` (with its `yaml` 2.9.1) and write `expected/` |

```bash
cd tool/conformance && npm ci
node make-cases.mjs                                   # after changing fixtures
GENBEYA_SRC=/path/to/genbeya-at-that-commit node generate.mjs   # or let it clone Genbeya
cd ../.. && flutter test test/conformance_test.dart
```

Add a case before changing an engine, and never change `expected/` by hand. To follow a newer Genbeya, bump `kit/GENBEYA_REF`, regenerate, and make the Dart side pass.

## CI

`.github/workflows/ci.yml` runs on every push: format, analysis and tests (the conformance cases included) on Linux; a check that `tool/conformance/expected/` is what Genbeya at `kit/GENBEYA_REF` produces; then a debug Android build (kept as an artifact) and an iOS build without signing on macOS.

`.github/workflows/drift.yml` runs every night against Genbeya's `develop`: a failure means Genbeya changed a format the Dart engines don't follow yet.
