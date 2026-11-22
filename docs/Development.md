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
| Rust | Stable, with the Android targets (`aarch64-linux-android`, `armv7-linux-androideabi`, `x86_64-linux-android`, `i686-linux-android`) and on macOS the iOS ones | The Git core ([[GM-2]]), built by Flutter's build through cargokit; see `native/genbeya_core/README.md` |
| Node.js | 22 or 24 | Building the kit ([[GM-3]]), which the app needs, and the conformance cases ([[GM-5]]) |

## Commands

```bash
(cd tool/build_kit && node build.mjs)   # the kit, into kit/dist; `node test.mjs` checks it
flutter pub get
dart format lib test          # CI fails on unformatted code
flutter analyze
flutter test
(cd native/genbeya_core && cargo test)   # the Git core's flow tests
flutter build apk --debug     # Android
flutter build ios --debug --no-codesign   # iOS, on macOS
```

## Tests

- `test/conformance_test.dart` runs every case in `tool/conformance/cases/` through the Dart engines and compares with what Genbeya's own engines produced, byte for byte for files ([[Architecture#conformance]]).
- `test/kit_host_test.dart` covers the host's side of the kit: what it sends when, and what it refuses from the kit (other versions, other files, offsets where no checkbox item starts, oversized or non-image reads).
- `test/layers_test.dart` keeps Flutter out of `lib/contracts`, `lib/engines`, `lib/access` and `lib/managers`, so they can run headless and mirror Genbeya's engines ([[Architecture]]).
- `test/native_bridge_test.dart` clones, commits and pushes through the Rust core from Dart; it skips unless the library is built (`cargo build --release --lib` in `native/genbeya_core`).
- `test/widget_test.dart` opens the app.

## Conformance

`tool/conformance/` keeps the Dart engines writing exactly what Genbeya writes:

| Path | Holds |
| --- | --- |
| `fixtures/` | Real files: every task of Genbeya and of this repository at the time, both `.genbeya.yml`, wiki pages with checkboxes, and hand-made edge cases (BOM, CRLF, YAML comments, quoting, block lists, comments, time logs; frontmatter, nested, ordered and quoted lists, wide characters for pages) |
| `make-cases.mjs` | Turns the fixtures into `cases/`: settings parsed; tasks parsed, their status moved, and for the edge cases and every fourth task also priority, a field, a list field, a label, no type and a new title; checkboxes ticked in pages and task descriptions, at items and at offsets where none starts (which the app refuses) |
| `runner.ts`, `generate.mjs` | Run each case through Genbeya's code at the commit in `kit/GENBEYA_REF` (with its `yaml` 2.9.1) and write `expected/`. Checkbox toggles use the client's own `toggleCheckboxAt` and `stripFrontmatter`; the module of the latter imports Angular, which the bundle replaces with a stub |

```bash
cd tool/conformance && npm ci
node make-cases.mjs                                   # after changing fixtures
GENBEYA_SRC=/path/to/genbeya-at-that-commit node generate.mjs   # or let it clone Genbeya
cd ../.. && flutter test test/conformance_test.dart
```

**Sorting.** Genbeya sorts names and titles with ICU (`localeCompare` with numeric, base-strength comparison), and Dart has no ICU. `lib/engines/collation.dart` sorts the same way with a table of ICU's root weights that `make-collation.mjs` writes from Node's ICU into `lib/engines/collation_table.dart`: the scripts and symbols names use, with expansions (`ß` is `ss`), decimal digits of every script compared by value, a block for Hangul, and Han after everything in ICU's implicit order. The `collate` cases, among them 40 lists of random strings, check it against ICU; CI regenerates the table and fails if it differs. Run `node make-collation.mjs` after updating Node.

Add a case before changing an engine, and never change `expected/` by hand. To follow a newer Genbeya, bump `kit/GENBEYA_REF`, regenerate, and make the Dart side pass.

## CI

`.github/workflows/ci.yml` runs on every push: format, analysis and tests (the conformance cases included) on Linux; a check that `tool/conformance/expected/` is what Genbeya at `kit/GENBEYA_REF` produces; then a debug Android build (kept as an artifact) and an iOS build without signing on macOS.

`.github/workflows/drift.yml` runs every night against Genbeya's `develop`: a failure means Genbeya changed a format the Dart engines don't follow yet.

After changing the Rust API in `native/genbeya_core/src/api/`, run `flutter_rust_bridge_codegen generate` (2.13.0) at the root; the generated Dart is in `lib/src/rust/`.
