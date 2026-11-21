//! What Dart can call, through flutter_rust_bridge. Each function is one
//! whole task from `crate::git`; flutter_rust_bridge runs it off the UI
//! thread and returns a Future. Paths are absolute folders in the app's
//! storage; repository paths inside them follow Genbeya's path rules.

use std::path::Path;
use std::time::Duration;

use flutter_rust_bridge::frb;

use crate::frb_generated::StreamSink;
pub use crate::git::{
    Auth, ChangedFile, CommitInfo, Conflict, CoreError, DiffSummary, FileChange, HeadInfo, Identity, Progress,
    PushOutcome, RebaseOutcome, RemoteOptions,
};
use crate::git::{self, Operation};

/// The versions inside the core, for the spike screen and bug reports.
#[frb(sync)]
pub fn core_version() -> String {
    let v = git2::Version::get();
    let (major, minor, patch) = v.libgit2_version();
    format!(
        "genbeya_core {} · libgit2 {major}.{minor}.{patch} · https {} · ssh {}",
        env!("CARGO_PKG_VERSION"),
        v.https(),
        v.ssh()
    )
}

/// Where OpenSSL finds CA certificates; on Android pass `dir: /system/etc/security/cacerts`.
pub fn set_ca_locations(file: Option<String>, dir: Option<String>) -> Result<(), CoreError> {
    git::set_ca_locations(file.as_deref(), dir.as_deref())
}

/// Adds trusted CA certificates (each DER-encoded) in memory; returns how many.
/// The way on Android, where the vendored OpenSSL can't read files.
pub fn add_ca_certificates(certificates: Vec<Vec<u8>>) -> Result<u32, CoreError> {
    git::add_ca_certificates(&certificates)
}

/// Stops the clone or fetch started with this operation id.
#[frb(sync)]
pub fn cancel_operation(operation_id: u64) {
    git::cancel(operation_id)
}

/// What a clone or fetch streams: progress while it runs, then how it ended.
/// The outcome travels on the stream because flutter_rust_bridge drops the
/// return value of functions that stream; a failure keeps its typed error,
/// such as an SSH host key to confirm.
pub enum TransferEvent {
    Progress(Progress),
    Done,
    Failed(CoreError),
}

fn finish(events: &StreamSink<TransferEvent>, result: Result<(), CoreError>) -> Result<(), CoreError> {
    let _ = events.add(match result {
        Ok(()) => TransferEvent::Done,
        Err(error) => TransferEvent::Failed(error),
    });
    Ok(())
}

/// Clones into the new folder `dir`. The stream reports progress and ends
/// with `Done` or `Failed`; read `head` afterwards.
pub fn clone_repository(
    url: String,
    dir: String,
    branch: Option<String>,
    depth: Option<i32>,
    remote: RemoteOptions,
    operation_id: u64,
    events: StreamSink<TransferEvent>,
) -> Result<(), CoreError> {
    let operation = Operation::start(operation_id);
    let mut report = |p: Progress| {
        let _ = events.add(TransferEvent::Progress(p));
    };
    let result = git::clone(&url, Path::new(&dir), branch.as_deref(), depth, &remote, Some(&operation), Some(&mut report))
        .map(|_| ());
    finish(&events, result)
}

pub fn head(dir: String) -> Result<HeadInfo, CoreError> {
    git::head(Path::new(&dir))
}

pub fn commit_files(dir: String, paths: Vec<String>, message: String, identity: Identity) -> Result<String, CoreError> {
    git::commit_files(Path::new(&dir), &paths, &message, &identity)
}

pub fn commit_onto_branch(
    dir: String,
    branch: String,
    changes: Vec<FileChange>,
    message: String,
    identity: Identity,
) -> Result<String, CoreError> {
    git::commit_onto_branch(Path::new(&dir), &branch, &changes, &message, &identity)
}

/// Fetches. The stream reports progress and ends with `Done` or `Failed`.
pub fn fetch(
    dir: String,
    extra_branches: Vec<String>,
    remote: RemoteOptions,
    operation_id: u64,
    events: StreamSink<TransferEvent>,
) -> Result<(), CoreError> {
    let operation = Operation::start(operation_id);
    let mut report = |p: Progress| {
        let _ = events.add(TransferEvent::Progress(p));
    };
    let result = git::fetch(Path::new(&dir), &extra_branches, &remote, Some(&operation), Some(&mut report)).map(|_| ());
    finish(&events, result)
}

pub fn rebase_onto_upstream(dir: String, identity: Identity, resolutions: Vec<FileChange>) -> Result<RebaseOutcome, CoreError> {
    git::rebase_onto_upstream(Path::new(&dir), &identity, &resolutions)
}

pub fn push(dir: String, branch: String, remote: RemoteOptions) -> Result<PushOutcome, CoreError> {
    git::push(Path::new(&dir), &branch, &remote)
}

pub fn log_path(dir: String, path: String, max: u32) -> Result<Vec<CommitInfo>, CoreError> {
    git::log_path(Path::new(&dir), &path, max as usize)
}

pub fn diff_from_merge_base(dir: String, source: String, target: String) -> Result<DiffSummary, CoreError> {
    git::diff_from_merge_base(Path::new(&dir), &source, &target)
}

pub fn merge_conflicts(dir: String, source: String, target: String) -> Result<Vec<String>, CoreError> {
    git::merge_conflicts(Path::new(&dir), &source, &target)
}

pub fn clear_stale_locks(dir: String, older_than_seconds: u64) -> Result<Vec<String>, CoreError> {
    git::clear_stale_locks(Path::new(&dir), Duration::from_secs(older_than_seconds))
}
