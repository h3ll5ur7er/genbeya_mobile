---
id: GM-1
title: Set up the Flutter project and CI
type: chore
status: done
priority: high
estimate: 2d
remaining: 2d
milestone: M0
---

An empty app that builds, tests and runs on an Android phone and an iPhone, with CI on every push.

- [x] `flutter create` for Android and iOS (phones and tablets), app ID and name *Genbeya Mobile*, Genbeya's icon
- [x] Folders as in [[Architecture#repository-layout]], Riverpod and go_router wired up
- [x] CI: `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`, an Android build and an iOS build without signing
- [x] Light and dark theme from Genbeya's colour tokens
- [x] License: FSL-1.1-ALv2, as Genbeya (D1 in [[Decisions]]), and README
- [x] Managers and engines import no Flutter, so they can run headless later (checked by `test/layers_test.dart`)

CI passed on GitHub from the first push: Linux checks, the Android build and the unsigned iOS build on macOS.
