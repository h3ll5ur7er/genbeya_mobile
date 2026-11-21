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

- [x] Rust crate `native/genbeya_core` with `git2` (vendored libgit2, OpenSSL, libssh2), bound with flutter_rust_bridge
- [x] Shallow single-branch clone of genbeya/genbeya; time and size noted
- [x] Commit a changed file without a staging step
- [x] Fetch, rebase the local commit onto the remote, push
- [x] Commit onto another branch's tree without checking it out (for the content branch)
- [x] `log` for one path, `diff` from a merge base, `merge-tree` style conflict check
- [x] In-memory rebase that leaves the working tree alone until it succeeds
- [x] `core.symlinks=false`, no submodules or LFS; stale lock files after the app is killed
- [x] Note the build steps and what broke (`native/genbeya_core/README.md`); the Rust core works, so it stays (D3 in [[Decisions]])
- [x] On a real Android phone (Pixel 9 Pro XL, 2026-11-21): 120 CA certificates from Android's store; HTTPS clone of genbeya/genbeya at depth 50 in 2.8 s over 5G (2.5 MB received, 7.3 MB on disk); commits in 48–259 ms; Sync without a token fails as it should, with the typed `authFailed` error
- [ ] Push with a token (a throwaway repository), then SSH against a real server, on the phone
- [ ] The same on an iPhone (waits for a Mac)

On this Linux container: 11 flow tests (two clones playing teammates against a bare remote, shallow clones over `git daemon`) and the bridge test from Dart pass; a real depth-1 HTTPS clone of genbeya/genbeya took 1.1 s (1.8 MB received, 8.4 MB on disk). The Android app builds with `libgenbeya_core.so` for arm64-v8a, armeabi-v7a and x86_64, about 7 MB each in release (+7.6 MB to an arm64 release APK, mostly OpenSSL). In CI the app also builds for iOS with the Rust core, OpenSSL and libssh2 (unsigned; it needed `-lz -liconv` in the plugin's pod, since libgit2 uses the system's zlib and iconv on Apple platforms). Not run yet: a real phone, SSH against a real server, HTTPS push with a token.

First run on a Pixel 9 Pro XL (2026-11-21): the clone failed, and the screen showed `head()`'s "failed to resolve path" instead of the clone's own error, because flutter_rust_bridge drops what a streaming function returns. Clone and fetch now end their stream with `Done` or `Failed` carrying the typed error (`runTransfer` in `lib/access/native/transfers.dart`). The likely cause of the failure itself: OpenSSL was pointed at Android's CA folder, whose files are named by OpenSSL's old hash and which, since Android 14, lives in the Conscrypt module; the app now writes the system's certificates into one PEM file (`lib/access/native/ca_bundle.dart`). The first version of that hung the app at the splash screen: it ran before `runApp`, and an exception from listing the certificate folder ended `main`. Now the certificates come from Android's own store (`AndroidCAStore`, through a channel in `MainActivity.kt`), with the folders as fallback; the setup runs after the app is up, never throws, and the Git core screen shows what it found. On the phone that showed the real cause: OpenSSL failed to load the bundle ("BIO lib"), because the vendored OpenSSL is built with `no-stdio` on Android and can't open files at all. The certificates now go to the core in memory, DER-encoded (`add_ca_certificates`, libgit2's `GIT_OPT_ADD_SSL_X509_CERT`), tested with the machine's CA bundle. To try again on the phone.

Proven on Linux with OpenSSL's own locations emptied: a real HTTPS clone trusting only the 121 certificates added from memory succeeds (`tests/certificates.rs`, ignored test).

Found on the way, in libgit2 1.9.7: when a TLS certificate check fails behind an HTTP proxy, `http_client_connect` frees the proxy stream before closing the TLS stream that runs over it, and the TLS shutdown then writes into the freed stream (`transports/httpclient.c`, `on_error`). Here it hung for good; it could crash. Phones connect directly unless a proxy is set, and there a bad certificate fails cleanly (226 ms on the Pixel). To do: report it to libgit2; if we keep libgit2, patch the order (close the server stream before the proxy). The core now sets network timeouts (15 s to connect, 60 s per read or write), which libgit2 has none of by default.
