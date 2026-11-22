//! The Git operations the app needs, as whole tasks rather than libgit2's
//! building blocks: each function opens the repository, does one complete
//! thing and leaves the repository consistent (see docs/Architecture.md,
//! "Git on the device", and docs/Architecture/Call-chains.md).
//!
//! Nothing here knows about Dart; `api` wraps these for flutter_rust_bridge.

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, SystemTime};

use git2::build::{CheckoutBuilder, TreeUpdateBuilder};
use git2::{
    BranchType, CertificateCheckStatus, Cred, CredentialType, Delta, DiffFindOptions, DiffFormat,
    DiffOptions, ErrorCode, FetchOptions, FileMode, Oid, ProxyOptions, PushOptions, RebaseOptions,
    RemoteCallbacks, Repository, Signature, Sort,
};

const REMOTE: &str = "origin";

// ---------- Types ----------

/// Who commits: the repository's Git identity.
#[derive(Debug, Clone)]
pub struct Identity {
    pub name: String,
    pub email: String,
}

/// How to authenticate to the remote.
#[derive(Debug, Clone, Default)]
pub enum Auth {
    #[default]
    None,
    /// HTTPS with a token (GitHub: any user name; GitLab: `oauth2`).
    Token { username: String, token: String },
    /// SSH with a key kept by the app (OpenSSH or PEM private key text).
    SshKey {
        username: String,
        public_key: Option<String>,
        private_key: String,
        passphrase: Option<String>,
    },
}

/// What a network operation needs besides the repository.
#[derive(Debug, Clone, Default)]
pub struct RemoteOptions {
    pub auth: Auth,
    /// SSH host key fingerprints the user trusts, as `SHA256:<base64>`.
    pub trusted_host_keys: Vec<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Progress {
    pub received_objects: u32,
    pub total_objects: u32,
    pub indexed_deltas: u32,
    pub total_deltas: u32,
    pub received_bytes: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct HeadInfo {
    /// The checked-out branch, or None when HEAD is detached.
    pub branch: Option<String>,
    pub commit: String,
    pub upstream: Option<String>,
    pub ahead: u32,
    pub behind: u32,
    /// Paths with changes not committed, which the app should never leave behind.
    pub dirty: Vec<String>,
    pub shallow: bool,
}

/// A file to write in a commit: new content, or None to delete it.
#[derive(Debug, Clone)]
pub struct FileChange {
    pub path: String,
    pub content: Option<Vec<u8>>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Conflict {
    pub path: String,
    pub ancestor: Option<Vec<u8>>,
    pub ours: Option<Vec<u8>>,
    pub theirs: Option<Vec<u8>>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum RebaseOutcome {
    /// Nothing upstream that the branch lacks.
    UpToDate,
    /// No local commits: the branch moved to upstream.
    FastForwarded { commit: String },
    /// Local commits replayed on top of upstream.
    Rebased { commit: String, commits: u32 },
    /// A local commit conflicts; nothing changed. `commit` is the local commit
    /// being replayed, so resolutions can be passed back for it.
    Conflicts {
        commit: String,
        conflicts: Vec<Conflict>,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub enum PushOutcome {
    Pushed,
    UpToDate,
    /// The remote has commits the branch lacks (or refused the update): fetch,
    /// rebase and try again. Never forced.
    Rejected {
        reason: String,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub struct CommitInfo {
    pub id: String,
    pub author: String,
    pub email: String,
    pub time: i64,
    pub summary: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ChangedFile {
    /// A, M, D, R, C or T, as `git diff --name-status`.
    pub status: String,
    pub path: String,
    pub old_path: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct DiffSummary {
    pub base: String,
    pub head: String,
    pub files: Vec<ChangedFile>,
    pub patch: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum CoreError {
    /// The SSH server's key isn't trusted yet: ask the user, then retry with
    /// the fingerprint in `RemoteOptions::trusted_host_keys`.
    HostKeyUnknown {
        host: String,
        fingerprint: String,
    },
    AuthFailed {
        message: String,
    },
    Cancelled,
    InvalidPath {
        path: String,
    },
    InvalidArgument {
        message: String,
    },
    Git {
        code: i32,
        class: i32,
        message: String,
    },
    Io {
        message: String,
    },
}

impl std::fmt::Display for CoreError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CoreError::HostKeyUnknown { host, fingerprint } => {
                write!(f, "unknown host key for {host}: {fingerprint}")
            }
            CoreError::AuthFailed { message } => write!(f, "authentication failed: {message}"),
            CoreError::Cancelled => write!(f, "cancelled"),
            CoreError::InvalidPath { path } => write!(f, "invalid path: {path}"),
            CoreError::InvalidArgument { message } => write!(f, "{message}"),
            CoreError::Git { message, .. } => write!(f, "{message}"),
            CoreError::Io { message } => write!(f, "{message}"),
        }
    }
}

impl std::error::Error for CoreError {}

impl From<git2::Error> for CoreError {
    fn from(e: git2::Error) -> Self {
        match e.code() {
            ErrorCode::User => CoreError::Cancelled,
            ErrorCode::Auth => CoreError::AuthFailed {
                message: e.message().to_string(),
            },
            // A server that refuses the credentials it got (a token without
            // write access answers a push with 403) is an auth failure too,
            // though libgit2 reports it as a generic HTTP error.
            _ if e.class() == git2::ErrorClass::Http && refused_status(e.message()) => {
                CoreError::AuthFailed {
                    message: e.message().to_string(),
                }
            }
            _ => CoreError::Git {
                code: e.raw_code(),
                class: e.raw_class() as i32,
                message: e.message().to_string(),
            },
        }
    }
}

fn refused_status(message: &str) -> bool {
    message
        .strip_prefix("unexpected http status code: ")
        .is_some_and(|code| code == "401" || code == "403")
}

#[cfg(test)]
mod error_tests {
    use super::*;

    fn http(message: &str) -> git2::Error {
        git2::Error::new(ErrorCode::GenericError, git2::ErrorClass::Http, message)
    }

    #[test]
    fn refused_credentials_are_auth_failures() {
        for code in ["401", "403"] {
            let message = format!("unexpected http status code: {code}");
            assert_eq!(
                CoreError::from(http(&message)),
                CoreError::AuthFailed { message }
            );
        }
    }

    #[test]
    fn other_http_errors_stay_git_errors() {
        let message = "unexpected http status code: 404";
        assert!(matches!(
            CoreError::from(http(message)),
            CoreError::Git { class: 34, .. }
        ));
    }
}

impl From<std::io::Error> for CoreError {
    fn from(e: std::io::Error) -> Self {
        CoreError::Io {
            message: e.to_string(),
        }
    }
}

pub type Result<T> = std::result::Result<T, CoreError>;

// ---------- Setup and cancellation ----------

/// Where OpenSSL finds trusted CA certificates. Android has no default the
/// vendored OpenSSL knows: pass `dir = /system/etc/security/cacerts` there.
pub fn set_ca_locations(file: Option<&str>, dir: Option<&str>) -> Result<()> {
    unsafe {
        if let Some(file) = file {
            git2::opts::set_ssl_cert_file(file)?;
        }
        if let Some(dir) = dir {
            git2::opts::set_ssl_cert_dir(dir)?;
        }
    }
    Ok(())
}

/// Adds trusted CA certificates, each DER-encoded, to OpenSSL's store in
/// memory, and returns how many it added; ones OpenSSL can't read are
/// skipped. On Android the vendored OpenSSL is built without file access
/// (`no-stdio`), so `set_ca_locations` can't work there: this is the way.
pub fn add_ca_certificates(certificates: &[Vec<u8>]) -> Result<u32> {
    libgit2_sys::init();
    let mut added = 0;
    for der in certificates {
        let Ok(length) = libc::c_long::try_from(der.len()) else {
            continue;
        };
        // SAFETY: d2i_X509 reads at most `length` bytes from `der`, which
        // outlives the call; the certificate it returns is freed below, after
        // libgit2 added it to the store (which takes its own reference).
        unsafe {
            let mut bytes = der.as_ptr();
            let certificate = openssl_sys::d2i_X509(std::ptr::null_mut(), &mut bytes, length);
            if certificate.is_null() {
                continue;
            }
            let code = libgit2_sys::git_libgit2_opts(
                libgit2_sys::GIT_OPT_ADD_SSL_X509_CERT as libc::c_int,
                certificate,
            );
            openssl_sys::X509_free(certificate);
            if code < 0 {
                return Err(git2::Error::last_error(code).into());
            }
        }
        added += 1;
    }
    Ok(added)
}

fn cancel_flags() -> &'static Mutex<HashMap<u64, Arc<AtomicBool>>> {
    static FLAGS: OnceLock<Mutex<HashMap<u64, Arc<AtomicBool>>>> = OnceLock::new();
    FLAGS.get_or_init(|| Mutex::new(HashMap::new()))
}

/// A cancellation flag for one running operation, removed when dropped.
pub struct Operation {
    id: u64,
    flag: Arc<AtomicBool>,
}

impl Operation {
    pub fn start(id: u64) -> Self {
        let flag = Arc::new(AtomicBool::new(false));
        cancel_flags().lock().unwrap().insert(id, flag.clone());
        Operation { id, flag }
    }
    pub fn cancelled(&self) -> bool {
        self.flag.load(Ordering::Relaxed)
    }
}

impl Drop for Operation {
    fn drop(&mut self) {
        cancel_flags().lock().unwrap().remove(&self.id);
    }
}

/// Asks a running clone or fetch to stop; it ends with `CoreError::Cancelled`.
pub fn cancel(id: u64) {
    if let Some(flag) = cancel_flags().lock().unwrap().get(&id) {
        flag.store(true, Ordering::Relaxed);
    }
}

// ---------- Paths ----------

/// Genbeya's path rules for repository paths: relative, no `..`, nothing in `.git`.
pub fn check_path(path: &str) -> Result<()> {
    let bad = path.is_empty()
        || path.starts_with('/')
        || path.contains('\\')
        || path.contains('\0')
        || path.split('/').any(|part| {
            let lower = part.to_ascii_lowercase();
            part.is_empty()
                || part == "."
                || part == ".."
                || lower == ".git"
                || lower.starts_with(".git.")
                || lower == "git~1"
        });
    if bad {
        Err(CoreError::InvalidPath {
            path: path.to_string(),
        })
    } else {
        Ok(())
    }
}

// ---------- Callbacks ----------

/// Callbacks for every network operation: credentials once per kind (libgit2
/// asks again on failure, which would loop), SSH host keys checked against the
/// trusted list, progress and cancellation.
struct Network {
    options: RemoteOptions,
    unknown_host: Arc<Mutex<Option<(String, String)>>>,
    rejected: Arc<Mutex<Vec<String>>>,
}

/// Network timeouts, set once before the first network operation: without
/// them libgit2 waits on a stalled connection for days (seen when a TLS
/// handshake failed behind a proxy that stopped reading), with no progress
/// callback in which a cancel could take effect.
const CONNECT_TIMEOUT_MS: libc::c_int = 15_000;
const SERVER_TIMEOUT_MS: libc::c_int = 60_000;

fn apply_network_timeouts() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        // SAFETY: these only set libgit2's global options, before any
        // network operation reads them; `Once` keeps it to one thread.
        unsafe {
            let _ = git2::opts::set_server_connect_timeout_in_milliseconds(CONNECT_TIMEOUT_MS);
            let _ = git2::opts::set_server_timeout_in_milliseconds(SERVER_TIMEOUT_MS);
        }
    });
}

impl Network {
    fn new(options: &RemoteOptions) -> Self {
        apply_network_timeouts();
        Network {
            options: options.clone(),
            unknown_host: Arc::new(Mutex::new(None)),
            rejected: Arc::new(Mutex::new(vec![])),
        }
    }

    fn callbacks<'cb>(
        &self,
        operation: Option<&Operation>,
        mut progress: Option<&'cb mut (dyn FnMut(Progress) + 'cb)>,
    ) -> RemoteCallbacks<'cb> {
        let cancelled = operation.map(|op| op.flag.clone());
        let mut callbacks = RemoteCallbacks::new();
        let auth = self.options.auth.clone();
        let mut tried = Vec::<CredentialType>::new();
        callbacks.credentials(move |_url, username_from_url, allowed| {
            let kind = if allowed.contains(CredentialType::SSH_KEY) {
                CredentialType::SSH_KEY
            } else if allowed.contains(CredentialType::USER_PASS_PLAINTEXT) {
                CredentialType::USER_PASS_PLAINTEXT
            } else if allowed.contains(CredentialType::USERNAME) {
                CredentialType::USERNAME
            } else {
                return Err(git2::Error::from_str("no supported credential type"));
            };
            if tried.contains(&kind) {
                return Err(git2::Error::new(
                    ErrorCode::Auth,
                    git2::ErrorClass::Net,
                    "credentials rejected",
                ));
            }
            tried.push(kind);
            match (&auth, kind) {
                (Auth::Token { username, token }, CredentialType::USER_PASS_PLAINTEXT) => {
                    Cred::userpass_plaintext(username, token)
                }
                (Auth::SshKey { username, .. }, CredentialType::USERNAME) => {
                    Cred::username(username)
                }
                (
                    Auth::SshKey {
                        username,
                        public_key,
                        private_key,
                        passphrase,
                    },
                    CredentialType::SSH_KEY,
                ) => {
                    let user = username_from_url.unwrap_or(username);
                    Cred::ssh_key_from_memory(
                        user,
                        public_key.as_deref(),
                        private_key,
                        passphrase.as_deref(),
                    )
                }
                _ => Err(git2::Error::new(
                    ErrorCode::Auth,
                    git2::ErrorClass::Net,
                    "no credentials for this remote",
                )),
            }
        });

        let trusted = self.options.trusted_host_keys.clone();
        let unknown = self.unknown_host.clone();
        callbacks.certificate_check(move |cert, host| {
            if let Some(key) = cert.as_hostkey() {
                let Some(hash) = key.hash_sha256() else {
                    return Err(git2::Error::from_str("host key without SHA-256 hash"));
                };
                let fingerprint = format!("SHA256:{}", base64_no_pad(hash));
                if trusted.iter().any(|t| t == &fingerprint) {
                    Ok(CertificateCheckStatus::CertificateOk)
                } else {
                    *unknown.lock().unwrap() = Some((host.to_string(), fingerprint));
                    Err(git2::Error::from_str("host key not trusted"))
                }
            } else {
                // HTTPS: libgit2 and OpenSSL validate the certificate chain.
                Ok(CertificateCheckStatus::CertificatePassthrough)
            }
        });

        callbacks.transfer_progress(move |stats| {
            if let Some(report) = progress.as_mut() {
                report(Progress {
                    received_objects: stats.received_objects() as u32,
                    total_objects: stats.total_objects() as u32,
                    indexed_deltas: stats.indexed_deltas() as u32,
                    total_deltas: stats.total_deltas() as u32,
                    received_bytes: stats.received_bytes() as u64,
                });
            }
            !cancelled
                .as_ref()
                .is_some_and(|flag| flag.load(Ordering::Relaxed))
        });

        let rejected = self.rejected.clone();
        callbacks.push_update_reference(move |refname, status| {
            if let Some(status) = status {
                rejected
                    .lock()
                    .unwrap()
                    .push(format!("{refname}: {status}"));
            }
            Ok(())
        });
        callbacks
    }

    /// Turns a failure into what caused it: a cancelled operation (libgit2
    /// reports an aborted transfer as a callback error) or an untrusted host key.
    fn explain(&self, error: git2::Error, operation: Option<&Operation>) -> CoreError {
        if operation.is_some_and(|op| op.cancelled()) {
            return CoreError::Cancelled;
        }
        if let Some((host, fingerprint)) = self.unknown_host.lock().unwrap().take() {
            return CoreError::HostKeyUnknown { host, fingerprint };
        }
        error.into()
    }
}

fn base64_no_pad(bytes: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();
    for chunk in bytes.chunks(3) {
        let n = chunk
            .iter()
            .enumerate()
            .fold(0u32, |n, (i, b)| n | (*b as u32) << (16 - 8 * i));
        for i in 0..=chunk.len() {
            out.push(TABLE[(n >> (18 - 6 * i) & 63) as usize] as char);
        }
    }
    out
}

fn fetch_options<'cb>(
    network: &Network,
    operation: Option<&Operation>,
    progress: Option<&'cb mut (dyn FnMut(Progress) + 'cb)>,
    depth: Option<i32>,
) -> FetchOptions<'cb> {
    let mut proxy = ProxyOptions::new();
    proxy.auto();
    let mut options = FetchOptions::new();
    options.remote_callbacks(network.callbacks(operation, progress));
    options.proxy_options(proxy);
    options.download_tags(git2::AutotagOption::None);
    if let Some(depth) = depth {
        options.depth(depth);
    }
    options
}

// ---------- Clone ----------

/// Clones `url` into the new folder `dir`: one branch (the remote's default
/// when `branch` is None), `depth` commits deep, symbolic links checked out as
/// plain files, no submodules. A failed or cancelled clone leaves no folder.
pub fn clone(
    url: &str,
    dir: &Path,
    branch: Option<&str>,
    depth: Option<i32>,
    remote: &RemoteOptions,
    operation: Option<&Operation>,
    progress: Option<&mut dyn FnMut(Progress)>,
) -> Result<HeadInfo> {
    if dir.exists() && fs::read_dir(dir)?.next().is_some() {
        return Err(CoreError::InvalidArgument {
            message: format!("{} is not empty", dir.display()),
        });
    }
    let result = clone_into(url, dir, branch, depth, remote, operation, progress);
    if result.is_err() {
        let _ = fs::remove_dir_all(dir);
    }
    result
}

fn clone_into(
    url: &str,
    dir: &Path,
    branch: Option<&str>,
    depth: Option<i32>,
    options: &RemoteOptions,
    operation: Option<&Operation>,
    progress: Option<&mut dyn FnMut(Progress)>,
) -> Result<HeadInfo> {
    let repo = Repository::init(dir)?;
    {
        let mut config = repo.config()?;
        config.set_bool("core.symlinks", false)?;
    }
    let network = Network::new(options);
    let branch = match branch {
        Some(b) => b.to_string(),
        None => default_branch(&repo, url, &network)?,
    };
    if branch.is_empty() || branch.contains("..") || branch.starts_with('-') {
        return Err(CoreError::InvalidArgument {
            message: format!("invalid branch {branch}"),
        });
    }
    let refspec = format!("+refs/heads/{branch}:refs/remotes/{REMOTE}/{branch}");
    let mut remote = repo.remote_with_fetch(REMOTE, url, &refspec)?;
    let mut fetch = fetch_options(&network, operation, progress, depth);
    remote
        .fetch(&[refspec.as_str()], Some(&mut fetch), None)
        .map_err(|e| network.explain(e, operation))?;
    drop(remote);

    let tracking = repo.find_reference(&format!("refs/remotes/{REMOTE}/{branch}"))?;
    let commit = tracking.peel_to_commit()?;
    let mut local = repo.branch(&branch, &commit, false)?;
    local.set_upstream(Some(&format!("{REMOTE}/{branch}")))?;
    repo.set_head(&format!("refs/heads/{branch}"))?;
    repo.checkout_head(Some(CheckoutBuilder::new().force()))?;
    head_of(&repo)
}

fn default_branch(repo: &Repository, url: &str, network: &Network) -> Result<String> {
    let mut remote = repo.remote_anonymous(url)?;
    let mut proxy = ProxyOptions::new();
    proxy.auto();
    let connection = remote
        .connect_auth(
            git2::Direction::Fetch,
            Some(network.callbacks(None, None)),
            Some(proxy),
        )
        .map_err(|e| network.explain(e, None))?;
    let name = connection.default_branch()?;
    let name = name.as_str().unwrap_or("").to_string();
    Ok(name
        .strip_prefix("refs/heads/")
        .unwrap_or(&name)
        .to_string())
}

// ---------- State ----------

pub fn head(dir: &Path) -> Result<HeadInfo> {
    head_of(&Repository::open(dir)?)
}

fn head_of(repo: &Repository) -> Result<HeadInfo> {
    let head = repo.head()?;
    let commit = head.peel_to_commit()?.id();
    let branch = if head.is_branch() {
        head.shorthand().ok().map(str::to_string)
    } else {
        None
    };
    let (mut upstream, mut ahead, mut behind) = (None, 0, 0);
    if let Some(name) = &branch {
        if let Ok(up) = repo
            .find_branch(name, BranchType::Local)
            .and_then(|b| b.upstream())
        {
            if let Some(target) = up.get().target() {
                let (a, b) = repo.graph_ahead_behind(commit, target)?;
                ahead = a as u32;
                behind = b as u32;
            }
            upstream = up.name()?.map(str::to_string);
        }
    }
    let mut options = git2::StatusOptions::new();
    options
        .include_untracked(true)
        .recurse_untracked_dirs(true)
        .exclude_submodules(true);
    let dirty = repo
        .statuses(Some(&mut options))?
        .iter()
        .filter(|s| !s.status().is_ignored())
        .filter_map(|s| s.path().ok().map(str::to_string))
        .collect();
    Ok(HeadInfo {
        branch,
        commit: commit.to_string(),
        upstream,
        ahead,
        behind,
        dirty,
        shallow: repo.is_shallow(),
    })
}

fn signature(identity: &Identity) -> Result<Signature<'static>> {
    Ok(Signature::now(&identity.name, &identity.email)?)
}

// ---------- Objects ----------
//
// The repository model reads every area from Git's objects: the checked-out
// commit and the content branch alike, parsed files cached by blob ID.

/// A file of a commit's tree.
#[derive(Debug, Clone, PartialEq)]
pub struct TreeFile {
    pub path: String,
    /// The blob's ID: the same content always has the same ID.
    pub blob: String,
    pub size: u64,
    /// A symbolic link, whose blob is the link's target.
    pub link: bool,
}

/// The commit `revision` names (a branch, a remote-tracking branch, `HEAD`,
/// an ID), or None when it names none.
pub fn resolve_commit(dir: &Path, revision: &str) -> Result<Option<String>> {
    let repo = Repository::open(dir)?;
    let found = repo.revparse_single(revision);
    match found {
        Ok(object) => Ok(object.peel_to_commit().ok().map(|c| c.id().to_string())),
        Err(e) if e.code() == ErrorCode::NotFound || e.code() == ErrorCode::InvalidSpec => Ok(None),
        Err(e) => Err(e.into()),
    }
}

/// Every file in `commit`'s tree, depth first; submodules are left out.
pub fn list_files(dir: &Path, commit: &str) -> Result<Vec<TreeFile>> {
    let repo = Repository::open(dir)?;
    let tree = repo.find_commit(git2::Oid::from_str(commit)?)?.tree()?;
    let odb = repo.odb()?;
    let mut files = Vec::new();
    let mut failure = None;
    tree.walk(git2::TreeWalkMode::PreOrder, |folder, entry| {
        if entry.kind() != Some(git2::ObjectType::Blob) {
            return git2::TreeWalkResult::Ok;
        }
        let Ok(name) = std::str::from_utf8(entry.name_bytes()) else {
            return git2::TreeWalkResult::Ok;
        };
        match odb.read_header(entry.id()) {
            Ok((size, _)) => files.push(TreeFile {
                path: format!("{folder}{name}"),
                blob: entry.id().to_string(),
                size: size as u64,
                link: entry.filemode() == 0o120000,
            }),
            Err(e) => {
                failure = Some(e);
                return git2::TreeWalkResult::Abort;
            }
        }
        git2::TreeWalkResult::Ok
    })?;
    if let Some(e) = failure {
        return Err(e.into());
    }
    Ok(files)
}

/// A blob's bytes, refused when larger than `max_bytes`.
pub fn read_blob(dir: &Path, blob: &str, max_bytes: u64) -> Result<Vec<u8>> {
    let repo = Repository::open(dir)?;
    let id = git2::Oid::from_str(blob)?;
    let (size, _) = repo.odb()?.read_header(id)?;
    if size as u64 > max_bytes {
        return Err(CoreError::InvalidArgument {
            message: format!("The file is larger than {max_bytes} bytes."),
        });
    }
    let bytes = repo.find_blob(id)?.content().to_vec();
    Ok(bytes)
}

/// The bytes of `path` in `commit`, None when it has no such file.
pub fn read_file_at(
    dir: &Path,
    commit: &str,
    path: &str,
    max_bytes: u64,
) -> Result<Option<Vec<u8>>> {
    check_path(path)?;
    let repo = Repository::open(dir)?;
    let tree = repo.find_commit(git2::Oid::from_str(commit)?)?.tree()?;
    let entry = match tree.get_path(Path::new(path)) {
        Ok(entry) => entry,
        Err(e) if e.code() == ErrorCode::NotFound => return Ok(None),
        Err(e) => return Err(e.into()),
    };
    if entry.kind() != Some(git2::ObjectType::Blob) {
        return Ok(None);
    }
    drop(tree);
    read_blob(dir, &entry.id().to_string(), max_bytes).map(Some)
}

/// The paths that differ between two commits: added, changed or removed (a
/// rename is both of its paths). What a sync must parse again.
pub fn changed_paths(dir: &Path, from: &str, to: &str) -> Result<Vec<String>> {
    let repo = Repository::open(dir)?;
    let tree = |id: &str| -> Result<git2::Tree<'_>> {
        Ok(repo.find_commit(git2::Oid::from_str(id)?)?.tree()?)
    };
    let (old, new) = (tree(from)?, tree(to)?);
    let diff = repo.diff_tree_to_tree(Some(&old), Some(&new), None)?;
    let mut paths = std::collections::BTreeSet::new();
    for delta in diff.deltas() {
        for file in [delta.old_file(), delta.new_file()] {
            if let Some(path) = file.path().and_then(|p| p.to_str()) {
                paths.insert(path.to_string());
            }
        }
    }
    Ok(paths.into_iter().collect())
}

/// A value of the repository's Git configuration, such as `genbeya.branch`.
pub fn config_value(dir: &Path, key: &str) -> Result<Option<String>> {
    let config = Repository::open(dir)?.config()?;
    match config.get_string(key) {
        Ok(value) => Ok(Some(value)),
        Err(e) if e.code() == ErrorCode::NotFound => Ok(None),
        Err(e) => Err(e.into()),
    }
}

// ---------- Commits ----------

/// Commits the working tree's state of `paths` on the checked-out branch:
/// changed and new files are added, missing ones removed. No staging step.
pub fn commit_files(
    dir: &Path,
    paths: &[String],
    message: &str,
    identity: &Identity,
) -> Result<String> {
    for path in paths {
        check_path(path)?;
    }
    let repo = Repository::open(dir)?;
    let mut index = repo.index()?;
    for path in paths {
        let full = dir.join(path);
        if fs::symlink_metadata(&full).is_ok() {
            index.add_path(Path::new(path))?;
        } else {
            index.remove_path(Path::new(path))?;
        }
    }
    index.write()?;
    let tree = repo.find_tree(index.write_tree()?)?;
    let parent = repo.head()?.peel_to_commit()?;
    let sig = signature(identity)?;
    let id = repo.commit(Some("HEAD"), &sig, &sig, message, &tree, &[&parent])?;
    Ok(id.to_string())
}

/// Commits `changes` onto `branch` without checking it out: the branch's tree
/// is updated in memory and the branch moves to the new commit. Used for the
/// content branch and for pull request replies on a source branch. A branch
/// that exists only on the remote is created from it, tracking it.
pub fn commit_onto_branch(
    dir: &Path,
    branch: &str,
    changes: &[FileChange],
    message: &str,
    identity: &Identity,
) -> Result<String> {
    for change in changes {
        check_path(&change.path)?;
    }
    let repo = Repository::open(dir)?;
    let head = repo.head()?;
    if head.is_branch() && head.shorthand().ok() == Some(branch) {
        return Err(CoreError::InvalidArgument {
            message: format!("{branch} is checked out: commit the files instead"),
        });
    }
    let parent = match repo.find_branch(branch, BranchType::Local) {
        Ok(b) => b.get().peel_to_commit()?,
        Err(_) => {
            let remote = repo
                .find_reference(&format!("refs/remotes/{REMOTE}/{branch}"))?
                .peel_to_commit()?;
            let mut created = repo.branch(branch, &remote, false)?;
            created.set_upstream(Some(&format!("{REMOTE}/{branch}")))?;
            remote
        }
    };
    let mut update = TreeUpdateBuilder::new();
    for change in changes {
        match &change.content {
            Some(bytes) => {
                let blob = repo.blob(bytes)?;
                update.upsert(&change.path, blob, FileMode::Blob);
            }
            None => {
                update.remove(&change.path);
            }
        }
    }
    let tree_id = update.create_updated(&repo, &parent.tree()?)?;
    let tree = repo.find_tree(tree_id)?;
    let sig = signature(identity)?;
    let id = repo.commit(
        Some(&format!("refs/heads/{branch}")),
        &sig,
        &sig,
        message,
        &tree,
        &[&parent],
    )?;
    Ok(id.to_string())
}

// ---------- Fetch, rebase, push ----------

/// Fetches the configured branches, plus `extra` branches (such as the
/// content branch `genbeya`) into their remote-tracking refs.
pub fn fetch(
    dir: &Path,
    extra: &[String],
    remote_options: &RemoteOptions,
    operation: Option<&Operation>,
    progress: Option<&mut dyn FnMut(Progress)>,
) -> Result<()> {
    let repo = Repository::open(dir)?;
    let remote = repo.find_remote(REMOTE)?;
    let configured = remote.fetch_refspecs()?;
    let mut refspecs: Vec<String> = (0..configured.len())
        .filter_map(|i| configured.get(i).ok().flatten().map(str::to_string))
        .collect();
    // Extra branches join the remote's configuration, so they are fetched
    // from now on and local branches can track them.
    for branch in extra {
        let spec = format!("+refs/heads/{branch}:refs/remotes/{REMOTE}/{branch}");
        if !refspecs.contains(&spec) {
            repo.remote_add_fetch(REMOTE, &spec)?;
            refspecs.push(spec);
        }
    }
    let mut remote = repo.find_remote(REMOTE)?;
    let network = Network::new(remote_options);
    let mut options = fetch_options(&network, operation, progress, None);
    let refs: Vec<&str> = refspecs.iter().map(String::as_str).collect();
    remote
        .fetch(&refs, Some(&mut options), None)
        .map_err(|e| network.explain(e, operation))?;
    Ok(())
}

/// Puts the checked-out branch's local commits on top of its upstream, in
/// memory: the working tree and the branch change only once every commit
/// applied. `resolutions` settle conflicts a previous call reported, by path,
/// for the local commit it named; anything else conflicting is reported and
/// nothing changes.
pub fn rebase_onto_upstream(
    dir: &Path,
    identity: &Identity,
    resolutions: &[FileChange],
) -> Result<RebaseOutcome> {
    for change in resolutions {
        check_path(&change.path)?;
    }
    let repo = Repository::open(dir)?;
    let head = repo.head()?;
    let branch_name = head.shorthand().map_err(CoreError::from)?.to_string();
    let local = head.peel_to_commit()?;
    let upstream_ref = repo
        .find_branch(&branch_name, BranchType::Local)?
        .upstream()?;
    let upstream = upstream_ref.get().peel_to_commit()?;
    let base = repo.merge_base(local.id(), upstream.id())?;
    if base == upstream.id() {
        return Ok(RebaseOutcome::UpToDate);
    }
    if base == local.id() {
        move_branch_and_checkout(&repo, &branch_name, local.id(), upstream.id())?;
        return Ok(RebaseOutcome::FastForwarded {
            commit: upstream.id().to_string(),
        });
    }

    let local_annotated = repo.find_annotated_commit(local.id())?;
    let upstream_annotated = repo.find_annotated_commit(upstream.id())?;
    let mut options = RebaseOptions::new();
    options.inmemory(true);
    let mut rebase = repo.rebase(
        Some(&local_annotated),
        Some(&upstream_annotated),
        None,
        Some(&mut options),
    )?;
    let sig = signature(identity)?;
    let mut last = upstream.id();
    let mut count = 0;
    while let Some(op) = rebase.next() {
        let op = op?;
        let replayed = op.id();
        let mut index = rebase.inmemory_index()?;
        if index.has_conflicts() {
            let mut remaining = Vec::new();
            let conflicts: Vec<_> = index.conflicts()?.collect::<std::result::Result<_, _>>()?;
            for conflict in conflicts {
                let entry = conflict
                    .our
                    .as_ref()
                    .or(conflict.their.as_ref())
                    .or(conflict.ancestor.as_ref())
                    .unwrap();
                let path = String::from_utf8_lossy(&entry.path).to_string();
                if let Some(resolution) = resolutions.iter().find(|r| r.path == path) {
                    index.conflict_remove(Path::new(&path))?;
                    if let Some(bytes) = &resolution.content {
                        let stage0 = git2::IndexEntry {
                            ctime: entry.ctime,
                            mtime: entry.mtime,
                            dev: entry.dev,
                            ino: entry.ino,
                            mode: entry.mode,
                            uid: entry.uid,
                            gid: entry.gid,
                            file_size: bytes.len() as u32,
                            id: repo.blob(bytes)?,
                            flags: entry.flags & !0x3000, // stage 0
                            flags_extended: entry.flags_extended,
                            path: entry.path.clone(),
                        };
                        index.add(&stage0)?;
                    }
                } else {
                    let blob = |e: &Option<git2::IndexEntry>| -> Result<Option<Vec<u8>>> {
                        Ok(match e {
                            Some(e) => Some(repo.find_blob(e.id)?.content().to_vec()),
                            None => None,
                        })
                    };
                    remaining.push(Conflict {
                        path,
                        ancestor: blob(&conflict.ancestor)?,
                        ours: blob(&conflict.our)?,
                        theirs: blob(&conflict.their)?,
                    });
                }
            }
            if !remaining.is_empty() {
                rebase.abort()?;
                return Ok(RebaseOutcome::Conflicts {
                    commit: replayed.to_string(),
                    conflicts: remaining,
                });
            }
            // In-memory rebases commit what the index holds; write the resolved index back.
            let tree = index.write_tree_to(&repo)?;
            let original = repo.find_commit(replayed)?;
            let parent = repo.find_commit(last)?;
            last = repo.commit(
                None,
                &original.author(),
                &sig,
                original.message().unwrap_or(""),
                &repo.find_tree(tree)?,
                &[&parent],
            )?;
            count += 1;
            continue;
        }
        match rebase.commit(None, &sig, None) {
            Ok(id) => {
                last = id;
                count += 1;
            }
            // The commit's changes are already upstream: nothing to replay.
            Err(e) if e.code() == ErrorCode::Applied => {}
            Err(e) => {
                rebase.abort()?;
                return Err(e.into());
            }
        }
    }
    rebase.finish(Some(&sig))?;
    move_branch_and_checkout(&repo, &branch_name, local.id(), last)?;
    Ok(RebaseOutcome::Rebased {
        commit: last.to_string(),
        commits: count,
    })
}

/// Moves the checked-out branch from `from` to `to` and updates the working
/// tree, refusing to overwrite changes that aren't committed.
fn move_branch_and_checkout(repo: &Repository, branch: &str, from: Oid, to: Oid) -> Result<()> {
    let target = repo.find_commit(to)?;
    let mut checkout = CheckoutBuilder::new();
    checkout.safe();
    repo.checkout_tree(target.as_object(), Some(&mut checkout))?;
    repo.reference_matching(
        &format!("refs/heads/{branch}"),
        to,
        true,
        from,
        "genbeya: sync",
    )?;
    repo.set_head(&format!("refs/heads/{branch}"))?;
    Ok(())
}

/// Pushes `branch` to the same name on the remote. Never forced: a remote
/// that has commits the branch lacks answers `Rejected`.
pub fn push(dir: &Path, branch: &str, remote_options: &RemoteOptions) -> Result<PushOutcome> {
    let repo = Repository::open(dir)?;
    let local = repo
        .find_branch(branch, BranchType::Local)?
        .get()
        .peel_to_commit()?
        .id();
    if let Ok(tracking) = repo.find_reference(&format!("refs/remotes/{REMOTE}/{branch}")) {
        if tracking.target() == Some(local) {
            return Ok(PushOutcome::UpToDate);
        }
    }
    let mut remote = repo.find_remote(REMOTE)?;
    let network = Network::new(remote_options);
    let mut proxy = ProxyOptions::new();
    proxy.auto();
    let mut options = PushOptions::new();
    options.remote_callbacks(network.callbacks(None, None));
    options.proxy_options(proxy);
    let refspec = format!("refs/heads/{branch}:refs/heads/{branch}");
    match remote.push(&[refspec.as_str()], Some(&mut options)) {
        Ok(()) => {}
        Err(e) if e.code() == ErrorCode::NotFastForward => {
            return Ok(PushOutcome::Rejected {
                reason: e.message().to_string(),
            });
        }
        Err(e) => return Err(network.explain(e, None)),
    }
    let rejected = network.rejected.lock().unwrap().clone();
    if !rejected.is_empty() {
        return Ok(PushOutcome::Rejected {
            reason: rejected.join("; "),
        });
    }
    // Keep the remote-tracking branch where the remote now is.
    repo.reference(
        &format!("refs/remotes/{REMOTE}/{branch}"),
        local,
        true,
        "genbeya: push",
    )?;
    Ok(PushOutcome::Pushed)
}

// ---------- History and diffs ----------

/// The newest `max` commits of HEAD that changed `path`, newest first. At a
/// shallow clone's boundary the file counts as added.
pub fn log_path(dir: &Path, path: &str, max: usize) -> Result<Vec<CommitInfo>> {
    check_path(path)?;
    let repo = Repository::open(dir)?;
    let mut walk = repo.revwalk()?;
    walk.push_head()?;
    walk.set_sorting(Sort::TOPOLOGICAL | Sort::TIME)?;
    let mut out = Vec::new();
    for id in walk {
        let commit = repo.find_commit(id?)?;
        let entry = |c: &git2::Commit| {
            c.tree()
                .ok()
                .and_then(|t| t.get_path(Path::new(path)).ok())
                .map(|e| e.id())
        };
        let mine = entry(&commit);
        let parent = commit.parents().next();
        let theirs = parent.as_ref().and_then(entry);
        if mine != theirs {
            let author = commit.author();
            out.push(CommitInfo {
                id: commit.id().to_string(),
                author: author.name().unwrap_or("").to_string(),
                email: author.email().unwrap_or("").to_string(),
                time: commit.time().seconds(),
                summary: commit.summary().ok().flatten().unwrap_or("").to_string(),
            });
            if out.len() == max {
                break;
            }
        }
    }
    Ok(out)
}

fn resolve(repo: &Repository, rev: &str) -> Result<Oid> {
    if rev.starts_with('-') || rev.contains("..") || rev.contains(':') {
        return Err(CoreError::InvalidArgument {
            message: format!("invalid revision {rev}"),
        });
    }
    Ok(repo.revparse_single(rev)?.peel_to_commit()?.id())
}

/// What merging `source` into `target` brings: the diff from where they meet
/// to `source`, with the options Genbeya's desktop uses (Myers, indent
/// heuristic, renames found).
pub fn diff_from_merge_base(dir: &Path, source: &str, target: &str) -> Result<DiffSummary> {
    let repo = Repository::open(dir)?;
    let head = resolve(&repo, source)?;
    let base = repo.merge_base(head, resolve(&repo, target)?)?;
    let mut options = DiffOptions::new();
    options.indent_heuristic(true).id_abbrev(40);
    let mut diff = repo.diff_tree_to_tree(
        Some(&repo.find_commit(base)?.tree()?),
        Some(&repo.find_commit(head)?.tree()?),
        Some(&mut options),
    )?;
    diff.find_similar(Some(DiffFindOptions::new().renames(true)))?;
    let files = diff
        .deltas()
        .map(|d| {
            let status = match d.status() {
                Delta::Added => "A",
                Delta::Deleted => "D",
                Delta::Renamed => "R",
                Delta::Copied => "C",
                Delta::Typechange => "T",
                _ => "M",
            };
            let path = d
                .new_file()
                .path()
                .or(d.old_file().path())
                .map(|p| p.to_string_lossy().to_string())
                .unwrap_or_default();
            let old_path = matches!(d.status(), Delta::Renamed | Delta::Copied)
                .then(|| d.old_file().path().map(|p| p.to_string_lossy().to_string()))
                .flatten();
            ChangedFile {
                status: status.to_string(),
                path,
                old_path,
            }
        })
        .collect();
    let mut patch = String::new();
    diff.print(DiffFormat::Patch, |_, _, line| {
        if matches!(line.origin(), '+' | '-' | ' ') {
            patch.push(line.origin());
        }
        patch.push_str(&String::from_utf8_lossy(line.content()));
        true
    })?;
    Ok(DiffSummary {
        base: base.to_string(),
        head: head.to_string(),
        files,
        patch,
    })
}

/// The paths that would conflict if `source` were merged into `target`,
/// worked out in memory without touching the working tree.
pub fn merge_conflicts(dir: &Path, source: &str, target: &str) -> Result<Vec<String>> {
    let repo = Repository::open(dir)?;
    let ours = repo.find_commit(resolve(&repo, target)?)?;
    let theirs = repo.find_commit(resolve(&repo, source)?)?;
    let index = repo.merge_commits(&ours, &theirs, None)?;
    let mut paths: Vec<String> = index
        .conflicts()?
        .filter_map(|c| c.ok())
        .filter_map(|c| c.our.or(c.their).or(c.ancestor))
        .map(|e| String::from_utf8_lossy(&e.path).to_string())
        .collect();
    paths.sort();
    paths.dedup();
    Ok(paths)
}

// ---------- Housekeeping ----------

/// Removes lock files left by a sync the operating system killed: `*.lock` in
/// the Git directory older than `older_than`. Call only while no operation on
/// this repository runs.
pub fn clear_stale_locks(dir: &Path, older_than: Duration) -> Result<Vec<String>> {
    let repo = Repository::open(dir)?;
    let git_dir = repo.path().to_path_buf();
    let mut removed = Vec::new();
    let now = SystemTime::now();
    let mut stack: Vec<PathBuf> = vec![git_dir.clone()];
    while let Some(folder) = stack.pop() {
        for entry in fs::read_dir(&folder)? {
            let entry = entry?;
            let path = entry.path();
            let kind = entry.file_type()?;
            if kind.is_dir() {
                if path.file_name().is_some_and(|n| n != "objects") {
                    stack.push(path);
                }
            } else if path.extension().is_some_and(|e| e == "lock") {
                let age = now
                    .duration_since(entry.metadata()?.modified()?)
                    .unwrap_or_default();
                if age >= older_than {
                    fs::remove_file(&path)?;
                    removed.push(
                        path.strip_prefix(&git_dir)
                            .unwrap_or(&path)
                            .to_string_lossy()
                            .to_string(),
                    );
                }
            }
        }
    }
    removed.sort();
    Ok(removed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base64_matches_openssh_style() {
        assert_eq!(base64_no_pad(b"hello"), "aGVsbG8");
        assert_eq!(base64_no_pad(b"hi!"), "aGkh");
    }

    #[test]
    fn path_rules() {
        for ok in [
            "tasks/GM-1.md",
            "docs/Home.md",
            ".genbeya.yml",
            "tasks/.images/GM-1/a.png",
        ] {
            assert!(check_path(ok).is_ok(), "{ok}");
        }
        for bad in [
            "",
            "/etc/passwd",
            "../x",
            "a/../b",
            ".git/config",
            "a/.GIT/x",
            "GIT~1/x",
            "a//b",
            "a\\b",
        ] {
            assert!(check_path(bad).is_err(), "{bad}");
        }
    }
}
