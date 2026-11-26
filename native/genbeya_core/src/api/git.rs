//! What Dart can call, through flutter_rust_bridge. Each function is one
//! whole task from `crate::git`; flutter_rust_bridge runs it off the UI
//! thread and returns a Future. Paths are absolute folders in the app's
//! storage; repository paths inside them follow Genbeya's path rules.

use std::path::Path;
use std::time::Duration;

use flutter_rust_bridge::frb;

use crate::frb_generated::StreamSink;
use crate::git::{self, Operation};
pub use crate::git::{
    Auth, AuthorCount, BranchStatus, ChangedFile, CommitInfo, Conflict, CoreError, DiffSummary,
    FileChange, FileHistory, FileRevision, GrepFile, GrepLine, GrepQuery, GrepRange, HeadInfo,
    Identity, Progress, PushOutcome, RebaseOutcome, RemoteBranches, RemoteOptions, Resolution,
    SshKeyPair, TreeFile,
};

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

fn finish(
    events: &StreamSink<TransferEvent>,
    result: Result<(), CoreError>,
) -> Result<(), CoreError> {
    let _ = events.add(match result {
        Ok(()) => TransferEvent::Done,
        Err(error) => TransferEvent::Failed(error),
    });
    Ok(())
}

/// Clones into the new folder `dir`. The stream reports progress and ends
/// with `Done` or `Failed`; read `head` afterwards.
#[allow(clippy::too_many_arguments)]
pub fn clone_repository(
    url: String,
    dir: String,
    branch: Option<String>,
    extra_branches: Vec<String>,
    depth: Option<i32>,
    remote: RemoteOptions,
    operation_id: u64,
    events: StreamSink<TransferEvent>,
) -> Result<(), CoreError> {
    let operation = Operation::start(operation_id);
    let mut report = |p: Progress| {
        let _ = events.add(TransferEvent::Progress(p));
    };
    let result = git::clone(
        &url,
        Path::new(&dir),
        branch.as_deref(),
        &extra_branches,
        depth,
        &remote,
        Some(&operation),
        Some(&mut report),
    )
    .map(|_| ());
    finish(&events, result)
}

/// The branches of a remote, without cloning.
pub fn remote_branches(url: String, remote: RemoteOptions) -> Result<RemoteBranches, CoreError> {
    git::remote_branches(&url, &remote)
}

/// Makes a new Ed25519 SSH key on the device.
pub fn generate_ssh_key(comment: String) -> Result<SshKeyPair, CoreError> {
    git::generate_ssh_key(&comment)
}

pub fn head(dir: String) -> Result<HeadInfo, CoreError> {
    git::head(Path::new(&dir))
}

/// The commit a revision names, or None.
pub fn resolve_commit(dir: String, revision: String) -> Result<Option<String>, CoreError> {
    git::resolve_commit(Path::new(&dir), &revision)
}

/// Every file of a commit's tree, with blob IDs and sizes.
pub fn list_files(dir: String, commit: String) -> Result<Vec<TreeFile>, CoreError> {
    git::list_files(Path::new(&dir), &commit)
}

/// A blob's bytes, refused when larger than `max_bytes`.
pub fn read_blob(dir: String, blob: String, max_bytes: u64) -> Result<Vec<u8>, CoreError> {
    git::read_blob(Path::new(&dir), &blob, max_bytes)
}

/// Many blobs at once: each one's bytes, or None when larger than `max_bytes`.
pub fn read_blobs(
    dir: String,
    blobs: Vec<String>,
    max_bytes: u64,
) -> Result<Vec<Option<Vec<u8>>>, CoreError> {
    git::read_blobs(Path::new(&dir), &blobs, max_bytes)
}

/// A file as committed, or None.
pub fn read_file_at(
    dir: String,
    commit: String,
    path: String,
    max_bytes: u64,
) -> Result<Option<Vec<u8>>, CoreError> {
    git::read_file_at(Path::new(&dir), &commit, &path, max_bytes)
}

/// The paths that differ between two commits.
pub fn changed_paths(dir: String, from: String, to: String) -> Result<Vec<String>, CoreError> {
    git::changed_paths(Path::new(&dir), &from, &to)
}

/// Sets (or with None removes) a value of the clone's own Git configuration.
pub fn set_config_value(dir: String, key: String, value: Option<String>) -> Result<(), CoreError> {
    git::set_config_value(Path::new(&dir), &key, value.as_deref())
}

/// The newest commits from `start` that changed `path`, following renames,
/// with the file before and after each.
pub fn file_history(
    dir: String,
    start: String,
    path: String,
    limit: u32,
    max_bytes: u64,
) -> Result<FileHistory, CoreError> {
    git::file_history(Path::new(&dir), &start, &path, limit as usize, max_bytes)
}

/// The files of a commit with a match, as `git grep -l` would list them.
pub fn grep_files(dir: String, commit: String, query: GrepQuery) -> Result<Vec<String>, CoreError> {
    git::grep_files(Path::new(&dir), &commit, &query)
}

/// The matching lines of some files of a commit, with the lines around them.
pub fn grep_lines(
    dir: String,
    commit: String,
    paths: Vec<String>,
    query: GrepQuery,
    max_matches: u32,
) -> Result<Vec<GrepFile>, CoreError> {
    git::grep_lines(
        Path::new(&dir),
        &commit,
        &paths,
        &query,
        max_matches as usize,
    )
}

/// The authors of HEAD's newest commits, as .mailmap names them.
pub fn commit_authors(dir: String, limit: u32) -> Result<Vec<AuthorCount>, CoreError> {
    git::commit_authors(Path::new(&dir), limit as usize)
}

/// A value of the repository's Git configuration.
pub fn config_value(dir: String, key: String) -> Result<Option<String>, CoreError> {
    git::config_value(Path::new(&dir), &key)
}

pub fn commit_files(
    dir: String,
    paths: Vec<String>,
    message: String,
    identity: Identity,
) -> Result<String, CoreError> {
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
    let result = git::fetch(
        Path::new(&dir),
        &extra_branches,
        &remote,
        Some(&operation),
        Some(&mut report),
    )
    .map(|_| ());
    finish(&events, result)
}

/// Replays the local commits of `branch` (the checked-out one when None)
/// onto its upstream in memory; resolutions per replayed commit and path.
pub fn rebase_branch(
    dir: String,
    branch: Option<String>,
    identity: Identity,
    resolutions: Vec<Resolution>,
) -> Result<RebaseOutcome, CoreError> {
    git::rebase_branch(Path::new(&dir), branch.as_deref(), &identity, &resolutions)
}

/// Where a branch stands against its upstream.
pub fn branch_status(dir: String, branch: String) -> Result<BranchStatus, CoreError> {
    git::branch_status(Path::new(&dir), &branch)
}

/// The commits of a branch its upstream doesn't have, newest first.
pub fn unpushed_commits(
    dir: String,
    branch: String,
    max: u32,
) -> Result<Vec<CommitInfo>, CoreError> {
    git::unpushed_commits(Path::new(&dir), &branch, max as usize)
}

/// Checks out a local branch, safely.
pub fn switch_branch(dir: String, branch: String) -> Result<(), CoreError> {
    git::switch_branch(Path::new(&dir), &branch)
}

/// Points a branch at a commit (creating it), refused when it isn't at
/// `expected`; the working tree follows when it is checked out.
pub fn set_branch(
    dir: String,
    branch: String,
    commit: String,
    expected: Option<String>,
) -> Result<(), CoreError> {
    git::set_branch(Path::new(&dir), &branch, &commit, expected.as_deref())
}

/// Deletes a branch that isn't checked out, on the remote too when given
/// how to reach it (a rescue branch once its commits are upstream).
pub fn delete_branch(
    dir: String,
    branch: String,
    remote: Option<RemoteOptions>,
) -> Result<(), CoreError> {
    git::delete_branch(Path::new(&dir), &branch, remote.as_ref())
}

/// Whether `commit` is on `branch`, local or else the remote's.
pub fn branch_contains(dir: String, branch: String, commit: String) -> Result<bool, CoreError> {
    git::branch_contains(Path::new(&dir), &branch, &commit)
}

pub fn push(dir: String, branch: String, remote: RemoteOptions) -> Result<PushOutcome, CoreError> {
    git::push(Path::new(&dir), &branch, &remote)
}

pub fn log_path(dir: String, path: String, max: u32) -> Result<Vec<CommitInfo>, CoreError> {
    git::log_path(Path::new(&dir), &path, max as usize)
}

pub fn diff_from_merge_base(
    dir: String,
    source: String,
    target: String,
) -> Result<DiffSummary, CoreError> {
    git::diff_from_merge_base(Path::new(&dir), &source, &target)
}

pub fn merge_conflicts(
    dir: String,
    source: String,
    target: String,
) -> Result<Vec<String>, CoreError> {
    git::merge_conflicts(Path::new(&dir), &source, &target)
}

pub fn clear_stale_locks(dir: String, older_than_seconds: u64) -> Result<Vec<String>, CoreError> {
    git::clear_stale_locks(Path::new(&dir), Duration::from_secs(older_than_seconds))
}
