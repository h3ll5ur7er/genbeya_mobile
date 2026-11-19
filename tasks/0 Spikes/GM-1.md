---
id: GM-1
title: Set up the Flutter project and CI
type: chore
status: todo
priority: high
estimate: 2d
remaining: 2d
milestone: M0
---

An empty app that builds, tests and runs on an Android phone and an iPhone, with CI on every push.

- [ ] `flutter create` for Android and iOS (phones and tablets), app ID and name *Genbeya Mobile*, Genbeya's icon
- [ ] Folders as in [[Architecture#repository-layout]], Riverpod and go_router wired up
- [ ] CI: `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`, an Android build and an iOS build without signing
- [ ] Light and dark theme from Genbeya's colour tokens
- [ ] License chosen (FSL-1.1-ALv2 like Genbeya, or other) and README
