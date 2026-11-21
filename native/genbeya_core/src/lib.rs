//! Genbeya Mobile's Git core. `git` holds the operations; `api` exposes them
//! to Dart through flutter_rust_bridge.
pub mod api;
mod frb_generated;
pub mod git;
