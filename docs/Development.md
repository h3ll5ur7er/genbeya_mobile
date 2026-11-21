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
| Node.js | 22 or 24 | Building the kit ([[GM-3]]) and the conformance cases ([[GM-5]]) |

## Commands

```bash
flutter pub get
dart format lib test          # CI fails on unformatted code
flutter analyze
flutter test
flutter build apk --debug     # Android
flutter build ios --debug --no-codesign   # iOS, on macOS
```

## Tests

- `test/layers_test.dart` keeps Flutter out of `lib/contracts`, `lib/engines`, `lib/access` and `lib/managers`, so they can run headless and mirror Genbeya's engines ([[Architecture]]).
- `test/widget_test.dart` opens the app.

## CI

`.github/workflows/ci.yml` runs on every push: format, analysis and tests on Linux, then a debug Android build (kept as an artifact) and an iOS build without signing on macOS.
