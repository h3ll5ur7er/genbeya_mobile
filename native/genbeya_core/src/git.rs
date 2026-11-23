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
    extra: &[String],
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
    let result = clone_into(url, dir, branch, extra, depth, remote, operation, progress);
    if result.is_err() {
        let _ = fs::remove_dir_all(dir);
    }
    result
}

#[allow(clippy::too_many_arguments)]
fn clone_into(
    url: &str,
    dir: &Path,
    branch: Option<&str>,
    extra: &[String],
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
    let listed = list_remote(&repo, url, &network)?;
    let branch = match branch {
        Some(b) => b.to_string(),
        None => listed.default_branch.clone().unwrap_or_default(),
    };
    if branch.is_empty() || branch.contains("..") || branch.starts_with('-') {
        return Err(CoreError::InvalidArgument {
            message: format!("invalid branch {branch}"),
        });
    }
    if !listed.branches.contains(&branch) {
        return Err(CoreError::InvalidArgument {
            message: format!("The remote has no branch {branch}."),
        });
    }
    let spec = |name: &str| format!("+refs/heads/{name}:refs/remotes/{REMOTE}/{name}");
    let refspec = spec(&branch);
    let mut remote = repo.remote_with_fetch(REMOTE, url, &refspec)?;
    drop(remote);
    // Extra branches the remote has (the content branch) come along, at the
    // same depth, and stay in the remote's configuration for later fetches.
    let mut refspecs = vec![refspec];
    for name in extra {
        if name != &branch && listed.branches.contains(name) {
            repo.remote_add_fetch(REMOTE, &spec(name))?;
            refspecs.push(spec(name));
        }
    }
    remote = repo.find_remote(REMOTE)?;
    let mut fetch = fetch_options(&network, operation, progress, depth);
    let refs: Vec<&str> = refspecs.iter().map(String::as_str).collect();
    remote
        .fetch(&refs, Some(&mut fetch), None)
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

/// What a remote offers: its default branch and every branch.
#[derive(Debug, Clone, PartialEq)]
pub struct RemoteBranches {
    pub default_branch: Option<String>,
    pub branches: Vec<String>,
}

fn list_remote(repo: &Repository, url: &str, network: &Network) -> Result<RemoteBranches> {
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
    let default_branch = connection
        .default_branch()
        .ok()
        .and_then(|name| name.as_str().ok().map(str::to_string))
        .map(|name| {
            name.strip_prefix("refs/heads/")
                .unwrap_or(&name)
                .to_string()
        })
        .filter(|name| !name.is_empty());
    let mut branches: Vec<String> = connection
        .list()?
        .iter()
        .filter_map(|head| head.name().strip_prefix("refs/heads/").map(str::to_string))
        .collect();
    branches.sort();
    branches.dedup();
    Ok(RemoteBranches {
        default_branch,
        branches,
    })
}

/// The branches of the remote at `url`, without cloning: for choosing what
/// to clone, and whether it has a content branch.
pub fn remote_branches(url: &str, options: &RemoteOptions) -> Result<RemoteBranches> {
    let dir = tempdir_for_listing()?;
    let repo = Repository::init_bare(&dir)?;
    let network = Network::new(options);
    let listed = list_remote(&repo, url, &network);
    drop(repo);
    let _ = fs::remove_dir_all(&dir);
    listed
}

/// An empty bare repository to list a remote from, in the system's temporary folder.
fn tempdir_for_listing() -> Result<PathBuf> {
    let dir = std::env::temp_dir().join(format!(
        "genbeya-ls-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0)
    ));
    fs::create_dir_all(&dir)?;
    Ok(dir)
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

// ---------- SSH keys ----------

/// An SSH key made on the device.
#[derive(Debug, Clone, PartialEq)]
pub struct SshKeyPair {
    /// The private key in OpenSSH's format, for the keychain only.
    pub private_key: String,
    /// The public key line to add to the forge: `ssh-ed25519 AAAA… comment`.
    pub public_key: String,
    /// `SHA256:…`, as `ssh-keygen -l` shows it.
    pub fingerprint: String,
}

/// Makes a new Ed25519 key, labelled with `comment` (the device's name).
pub fn generate_ssh_key(comment: &str) -> Result<SshKeyPair> {
    let mut key = ssh_key::PrivateKey::random(&mut rand_core::OsRng, ssh_key::Algorithm::Ed25519)
        .map_err(key_error)?;
    key.set_comment(comment);
    let private_key = key
        .to_openssh(ssh_key::LineEnding::LF)
        .map_err(key_error)?
        .to_string();
    let public = key.public_key();
    Ok(SshKeyPair {
        private_key,
        public_key: public.to_openssh().map_err(key_error)?,
        fingerprint: public.fingerprint(ssh_key::HashAlg::Sha256).to_string(),
    })
}

fn key_error(error: ssh_key::Error) -> CoreError {
    CoreError::InvalidArgument {
        message: format!("Couldn't make an SSH key: {error}"),
    }
}

// ---------- Search ----------
//
// Full-text search over a commit's files, as Genbeya searches a working tree
// with `git grep`: text or a regular expression, case-insensitive unless
// asked, whole words optionally; binary files left out.

/// What to search for.
#[derive(Debug, Clone)]
pub struct GrepQuery {
    pub text: String,
    pub case_sensitive: bool,
    pub regex: bool,
    pub whole_word: bool,
}

/// A part of a line that matched, in UTF-16 code units, as Dart counts.
#[derive(Debug, Clone, PartialEq)]
pub struct GrepRange {
    pub start: u32,
    pub end: u32,
}

/// A line of a file: a match, or a line next to one.
#[derive(Debug, Clone, PartialEq)]
pub struct GrepLine {
    /// From 1.
    pub line: u32,
    pub text: String,
    pub ranges: Vec<GrepRange>,
    pub is_match: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct GrepFile {
    pub path: String,
    pub lines: Vec<GrepLine>,
}

/// Files larger than this are not searched, as the phone reads no larger text.
const GREP_FILE_LIMIT: u64 = 2 * 1024 * 1024;

fn grep_matcher(query: &GrepQuery) -> Result<regex::Regex> {
    if query.text.trim().is_empty() || query.text.contains(['\r', '\n', '\0']) {
        return Err(CoreError::InvalidArgument {
            message: "Search for text within one line.".into(),
        });
    }
    let pattern = if query.regex {
        query.text.clone()
    } else {
        regex::escape(&query.text)
    };
    regex::RegexBuilder::new(&pattern)
        .case_insensitive(!query.case_sensitive)
        .size_limit(1 << 20)
        .build()
        .map_err(|e| CoreError::InvalidArgument {
            message: format!("Not a valid regular expression: {e}"),
        })
}

fn is_word(c: char) -> bool {
    c.is_alphanumeric() || c == '_'
}

/// Where `matcher` matches `line`, as byte ranges; with `whole_word`, only
/// matches with no letter, digit or underscore right before or after.
fn grep_ranges(matcher: &regex::Regex, line: &str, whole_word: bool) -> Vec<(usize, usize)> {
    let mut ranges = Vec::new();
    let mut at = 0;
    while at <= line.len() {
        let Some(found) = matcher.find_at(line, at) else {
            break;
        };
        let next = |i: usize| {
            line[i..]
                .chars()
                .next()
                .map_or(line.len() + 1, |c| i + c.len_utf8())
        };
        let fits = !whole_word
            || (!line[..found.start()]
                .chars()
                .next_back()
                .is_some_and(is_word)
                && !line[found.end()..].chars().next().is_some_and(is_word));
        if fits && found.end() > found.start() {
            ranges.push((found.start(), found.end()));
            at = found.end();
        } else {
            at = next(found.start());
        }
    }
    ranges
}

fn utf16_at(line: &str, byte: usize) -> u32 {
    line[..byte].chars().map(|c| c.len_utf16() as u32).sum()
}

/// A blob's text, or None for binary files and those over the limit.
fn grep_text(odb: &git2::Odb, id: Oid) -> Result<Option<String>> {
    let (size, _) = odb.read_header(id)?;
    if size as u64 > GREP_FILE_LIMIT {
        return Ok(None);
    }
    let object = odb.read(id)?;
    let data = object.data();
    // Git's own test: a NUL in the first 8000 bytes makes a file binary.
    if data[..data.len().min(8000)].contains(&0) {
        return Ok(None);
    }
    Ok(Some(String::from_utf8_lossy(data).into_owned()))
}

/// The files of `commit` with a match, in the tree's order.
pub fn grep_files(dir: &Path, commit: &str, query: &GrepQuery) -> Result<Vec<String>> {
    let matcher = grep_matcher(query)?;
    let files = list_files(dir, commit)?;
    let repo = Repository::open(dir)?;
    let odb = repo.odb()?;
    let mut found = Vec::new();
    for file in files {
        let Some(text) = grep_text(&odb, Oid::from_str(&file.blob)?)? else {
            continue;
        };
        // Line by line, as git grep matches: `^` and `$` are a line's ends,
        // and a CRLF line keeps its CR, so `$` doesn't match before it.
        let matches = text.split('\n').any(|line| {
            if query.whole_word {
                !grep_ranges(&matcher, line, true).is_empty()
            } else {
                matcher.is_match(line)
            }
        });
        if matches {
            found.push(file.path);
        }
    }
    Ok(found)
}

/// The matching lines of `paths` in `commit`, at most `max_matches` per
/// file, each with the line before and after it.
pub fn grep_lines(
    dir: &Path,
    commit: &str,
    paths: &[String],
    query: &GrepQuery,
    max_matches: usize,
) -> Result<Vec<GrepFile>> {
    let matcher = grep_matcher(query)?;
    let repo = Repository::open(dir)?;
    let tree = repo.find_commit(Oid::from_str(commit)?)?.tree()?;
    let odb = repo.odb()?;
    let mut out = Vec::new();
    for path in paths {
        check_path(path)?;
        let Ok(entry) = tree.get_path(Path::new(path)) else {
            continue;
        };
        let Some(text) = grep_text(&odb, entry.id())? else {
            continue;
        };
        // Matched with their CR, as git grep does; shown without it.
        let lines: Vec<&str> = text.split('\n').collect();
        let shown = |line: &str| line.strip_suffix('\r').unwrap_or(line).to_string();
        let mut picked: std::collections::BTreeMap<usize, GrepLine> = Default::default();
        let mut matched = 0;
        for (index, line) in lines.iter().enumerate() {
            if matched == max_matches {
                break;
            }
            let ranges = grep_ranges(&matcher, line, query.whole_word);
            if ranges.is_empty() {
                continue;
            }
            matched += 1;
            picked.insert(
                index,
                GrepLine {
                    line: index as u32 + 1,
                    text: shown(line),
                    ranges: ranges
                        .iter()
                        .map(|&(start, end)| GrepRange {
                            start: utf16_at(line, start),
                            end: utf16_at(line, end),
                        })
                        .collect(),
                    is_match: true,
                },
            );
        }
        let matches: Vec<usize> = picked.keys().copied().collect();
        for index in matches {
            for near in [index.wrapping_sub(1), index + 1] {
                if near < lines.len()
                    && !picked.contains_key(&near)
                    && !(near + 1 == lines.len() && lines[near].is_empty())
                {
                    picked.insert(
                        near,
                        GrepLine {
                            line: near as u32 + 1,
                            text: shown(lines[near]),
                            ranges: vec![],
                            is_match: false,
                        },
                    );
                }
            }
        }
        out.push(GrepFile {
            path: path.clone(),
            lines: picked.into_values().collect(),
        });
    }
    Ok(out)
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

/// Many blobs at once, opening the repository once: each one's bytes, or
/// None when it is larger than `max_bytes`.
pub fn read_blobs(dir: &Path, blobs: &[String], max_bytes: u64) -> Result<Vec<Option<Vec<u8>>>> {
    let repo = Repository::open(dir)?;
    let odb = repo.odb()?;
    blobs
        .iter()
        .map(|blob| {
            let id = git2::Oid::from_str(blob)?;
            let (size, _) = odb.read_header(id)?;
            if size as u64 > max_bytes {
                return Ok(None);
            }
            Ok(Some(odb.read(id)?.data().to_vec()))
        })
        .collect()
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

/// A commit that changed a file, with the file before and after.
#[derive(Debug, Clone, PartialEq)]
pub struct FileRevision {
    pub commit: String,
    pub author: String,
    pub email: String,
    pub time: i64,
    pub subject: String,
    /// The file's path at this commit.
    pub path: String,
    /// Its path before: None when this commit created it.
    pub old_path: Option<String>,
    /// The contents before and after; None where there is none, or it is
    /// larger than the limit.
    pub before: Option<Vec<u8>>,
    pub after: Option<Vec<u8>>,
}

/// The newest commits that changed a file, as `git log --follow --no-merges`.
#[derive(Debug, Clone, PartialEq)]
pub struct FileHistory {
    pub revisions: Vec<FileRevision>,
    /// The history goes further back than this shallow clone has.
    pub truncated: bool,
}

/// The newest `limit` commits from `start` that changed `path`, following
/// renames, without merges; each with the file before and after unless a
/// version is larger than `max_bytes`.
pub fn file_history(
    dir: &Path,
    start: &str,
    path: &str,
    limit: usize,
    max_bytes: u64,
) -> Result<FileHistory> {
    check_path(path)?;
    let repo = Repository::open(dir)?;
    let shallow: std::collections::HashSet<Oid> = fs::read_to_string(repo.path().join("shallow"))
        .unwrap_or_default()
        .lines()
        .filter_map(|line| Oid::from_str(line.trim()).ok())
        .collect();
    let mailmap = repo.mailmap()?;
    let odb = repo.odb()?;
    let content = |id: Option<Oid>| -> Result<Option<Vec<u8>>> {
        let Some(id) = id else { return Ok(None) };
        let (size, _) = odb.read_header(id)?;
        if size as u64 > max_bytes {
            return Ok(None);
        }
        Ok(Some(odb.read(id)?.data().to_vec()))
    };
    let blob_at = |tree: &git2::Tree, path: &str| -> Option<Oid> {
        tree.get_path(Path::new(path))
            .ok()
            .filter(|entry| entry.kind() == Some(git2::ObjectType::Blob))
            .map(|entry| entry.id())
    };
    let mut walk = repo.revwalk()?;
    walk.push(Oid::from_str(start)?)?;
    // Children before parents, which following a path needs; newest first among equals.
    walk.set_sorting(Sort::TOPOLOGICAL | Sort::TIME)?;
    let mut current = path.to_string();
    let mut revisions = Vec::new();
    let mut truncated = false;
    for id in walk {
        if revisions.len() >= limit {
            break;
        }
        let commit = repo.find_commit(id?)?;
        if commit.parent_count() > 1 {
            continue;
        }
        let tree = commit.tree()?;
        let Some(after_id) = blob_at(&tree, &current) else {
            continue;
        };
        if commit.parent_count() == 0 && shallow.contains(&commit.id()) {
            // The clone ends here: older history isn't on the phone.
            truncated = true;
            break;
        }
        let parent_tree = match commit.parent_count() {
            1 => Some(commit.parent(0)?.tree()?),
            _ => None,
        };
        let before_id = parent_tree.as_ref().and_then(|t| blob_at(t, &current));
        if before_id == Some(after_id) {
            continue;
        }
        let (old_path, before) = if before_id.is_some() {
            (Some(current.clone()), content(before_id)?)
        } else {
            match parent_tree
                .as_ref()
                .map(|parent| rename_source(&repo, parent, &tree, &current))
                .transpose()?
                .flatten()
            {
                Some((old, old_id)) => (Some(old), content(Some(old_id))?),
                None => (None, None),
            }
        };
        let author = commit.author_with_mailmap(&mailmap)?;
        revisions.push(FileRevision {
            commit: commit.id().to_string(),
            author: String::from_utf8_lossy(author.name_bytes()).into_owned(),
            email: String::from_utf8_lossy(author.email_bytes()).into_owned(),
            time: author.when().seconds(),
            subject: commit.summary().ok().flatten().unwrap_or("").to_string(),
            path: current.clone(),
            old_path: old_path.clone(),
            before,
            after: content(Some(after_id))?,
        });
        match old_path {
            Some(old) => current = old,
            // Created here: nothing older to follow.
            None => break,
        }
    }
    Ok(FileHistory {
        revisions,
        truncated,
    })
}

/// The file `path` in `tree` was renamed from, by Git's rename detection.
fn rename_source(
    repo: &Repository,
    parent: &git2::Tree,
    tree: &git2::Tree,
    path: &str,
) -> Result<Option<(String, Oid)>> {
    let mut diff = repo.diff_tree_to_tree(Some(parent), Some(tree), None)?;
    let mut find = DiffFindOptions::new();
    find.renames(true);
    diff.find_similar(Some(&mut find))?;
    for delta in diff.deltas() {
        if delta.status() == Delta::Renamed
            && delta.new_file().path().and_then(|p| p.to_str()) == Some(path)
        {
            if let Some(old) = delta.old_file().path().and_then(|p| p.to_str()) {
                return Ok(Some((old.to_string(), delta.old_file().id())));
            }
        }
    }
    Ok(None)
}

/// Sets a value of the repository's own Git configuration (`user.name`,
/// `user.email`, `genbeya.branch`); None removes it.
pub fn set_config_value(dir: &Path, key: &str, value: Option<&str>) -> Result<()> {
    let repo = Repository::open(dir)?;
    let mut config = repo.config()?.open_level(git2::ConfigLevel::Local)?;
    match value {
        Some(value) => config.set_str(key, value)?,
        None => match config.remove(key) {
            Ok(()) => {}
            Err(e) if e.code() == ErrorCode::NotFound => {}
            Err(e) => return Err(e.into()),
        },
    }
    Ok(())
}

/// Commits by one name and email.
#[derive(Debug, Clone, PartialEq)]
pub struct AuthorCount {
    pub name: String,
    pub email: String,
    pub commits: u32,
}

/// The authors of the newest `limit` commits of HEAD, with their number of
/// commits, as .mailmap names them (`git log --format=%aN%x00%aE`), in the
/// order they first appear; empty on an unborn branch.
pub fn commit_authors(dir: &Path, limit: usize) -> Result<Vec<AuthorCount>> {
    let repo = Repository::open(dir)?;
    let mut walk = repo.revwalk()?;
    if let Err(e) = walk.push_head() {
        if e.code() == ErrorCode::UnbornBranch || e.code() == ErrorCode::NotFound {
            return Ok(Vec::new());
        }
        return Err(e.into());
    }
    walk.set_sorting(Sort::TIME)?;
    let mailmap = repo.mailmap()?;
    let mut counts: Vec<AuthorCount> = Vec::new();
    let mut index: HashMap<(String, String), usize> = HashMap::new();
    for id in walk.take(limit) {
        let commit = repo.find_commit(id?)?;
        let author = commit.author_with_mailmap(&mailmap)?;
        let name = String::from_utf8_lossy(author.name_bytes()).into_owned();
        let email = String::from_utf8_lossy(author.email_bytes()).into_owned();
        if name.trim().is_empty() && email.trim().is_empty() {
            continue;
        }
        match index.get(&(name.clone(), email.clone())) {
            Some(&at) => counts[at].commits += 1,
            None => {
                index.insert((name.clone(), email.clone()), counts.len());
                counts.push(AuthorCount {
                    name,
                    email,
                    commits: 1,
                });
            }
        }
    }
    Ok(counts)
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
/// A conflict resolved: the content of `path` when the local commit
/// `commit` is replayed (None removes the file).
#[derive(Debug, Clone)]
pub struct Resolution {
    pub commit: String,
    pub path: String,
    pub content: Option<Vec<u8>>,
}

/// Replays the local commits of `branch` (the checked-out branch when None)
/// onto its upstream, in memory. A branch that isn't checked out (the
/// content branch) only has its ref moved; the checked-out one also its
/// working tree, once the result is known. A conflict without a resolution
/// stops it, changing nothing.
pub fn rebase_branch(
    dir: &Path,
    branch: Option<&str>,
    identity: &Identity,
    resolutions: &[Resolution],
) -> Result<RebaseOutcome> {
    for resolution in resolutions {
        check_path(&resolution.path)?;
    }
    let repo = Repository::open(dir)?;
    let head = repo.head()?;
    let checked_out = head.shorthand().ok().map(str::to_string);
    let branch_name = match branch {
        Some(name) => name.to_string(),
        None => checked_out
            .clone()
            .ok_or_else(|| CoreError::InvalidArgument {
                message: "HEAD is detached".into(),
            })?,
    };
    let is_checked_out = head.is_branch() && checked_out.as_deref() == Some(branch_name.as_str());
    let Ok(local_branch) = repo.find_branch(&branch_name, BranchType::Local) else {
        // No local branch: nothing of ours to replay.
        return Ok(RebaseOutcome::UpToDate);
    };
    let local = local_branch.get().peel_to_commit()?;
    let upstream_ref = local_branch.upstream()?;
    let upstream = upstream_ref.get().peel_to_commit()?;
    let base = repo.merge_base(local.id(), upstream.id())?;
    if base == upstream.id() {
        return Ok(RebaseOutcome::UpToDate);
    }
    if base == local.id() {
        move_branch(
            &repo,
            &branch_name,
            local.id(),
            upstream.id(),
            is_checked_out,
        )?;
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
                let replayed_id = replayed.to_string();
                if let Some(resolution) = resolutions
                    .iter()
                    .find(|r| r.path == path && r.commit == replayed_id)
                {
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
    move_branch(&repo, &branch_name, local.id(), last, is_checked_out)?;
    Ok(RebaseOutcome::Rebased {
        commit: last.to_string(),
        commits: count,
    })
}

/// Moves the checked-out branch from `from` to `to` and updates the working
/// tree, refusing to overwrite changes that aren't committed.
/// Moves `branch` from `from` to `to`; the working tree follows only when
/// it is checked out.
fn move_branch(
    repo: &Repository,
    branch: &str,
    from: Oid,
    to: Oid,
    checked_out: bool,
) -> Result<()> {
    if checked_out {
        return move_branch_and_checkout(repo, branch, from, to);
    }
    repo.reference_matching(
        &format!("refs/heads/{branch}"),
        to,
        true,
        from,
        "genbeya: sync",
    )?;
    Ok(())
}

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

/// Where a branch stands against its upstream.
#[derive(Debug, Clone, PartialEq)]
pub struct BranchStatus {
    /// None when there is no local branch of the name.
    pub commit: Option<String>,
    pub upstream: Option<String>,
    pub upstream_commit: Option<String>,
    pub ahead: u32,
    pub behind: u32,
}

pub fn branch_status(dir: &Path, branch: &str) -> Result<BranchStatus> {
    let repo = Repository::open(dir)?;
    let Ok(local) = repo.find_branch(branch, BranchType::Local) else {
        return Ok(BranchStatus {
            commit: None,
            upstream: None,
            upstream_commit: None,
            ahead: 0,
            behind: 0,
        });
    };
    let commit = local.get().peel_to_commit()?.id();
    let (mut upstream, mut upstream_commit, mut ahead, mut behind) = (None, None, 0, 0);
    if let Ok(up) = local.upstream() {
        if let Some(target) = up.get().target() {
            let (a, b) = repo.graph_ahead_behind(commit, target)?;
            ahead = a as u32;
            behind = b as u32;
            upstream_commit = Some(target.to_string());
        }
        upstream = up.name()?.map(str::to_string);
    } else {
        // Never pushed: every commit is the branch's own.
        let mut walk = repo.revwalk()?;
        walk.push(commit)?;
        ahead = walk.count() as u32;
    }
    Ok(BranchStatus {
        commit: Some(commit.to_string()),
        upstream,
        upstream_commit,
        ahead,
        behind,
    })
}

/// The commits of `branch` its upstream doesn't have, newest first.
pub fn unpushed_commits(dir: &Path, branch: &str, max: usize) -> Result<Vec<CommitInfo>> {
    let repo = Repository::open(dir)?;
    let Ok(local) = repo.find_branch(branch, BranchType::Local) else {
        return Ok(Vec::new());
    };
    let mut walk = repo.revwalk()?;
    walk.push(local.get().peel_to_commit()?.id())?;
    if let Ok(up) = local.upstream() {
        if let Some(target) = up.get().target() {
            walk.hide(target)?;
        }
    }
    walk.set_sorting(Sort::TOPOLOGICAL | Sort::TIME)?;
    let mut out = Vec::new();
    for id in walk.take(max) {
        let commit = repo.find_commit(id?)?;
        let author = commit.author();
        out.push(CommitInfo {
            id: commit.id().to_string(),
            author: author.name().unwrap_or("").to_string(),
            email: author.email().unwrap_or("").to_string(),
            time: author.when().seconds(),
            summary: commit.summary().ok().flatten().unwrap_or("").to_string(),
        });
    }
    Ok(out)
}

/// Points `branch` at `commit`, creating it when it doesn't exist; refused
/// when `expected` (the commit it must be at now) doesn't hold. When the
/// branch is checked out, the working tree follows. For the rescue branch,
/// a reset to upstream after it, and undoing unpushed commits.
pub fn set_branch(dir: &Path, branch: &str, commit: &str, expected: Option<&str>) -> Result<()> {
    if branch.is_empty() || branch.contains("..") || branch.starts_with('-') {
        return Err(CoreError::InvalidArgument {
            message: format!("invalid branch {branch}"),
        });
    }
    let repo = Repository::open(dir)?;
    let to = Oid::from_str(commit)?;
    repo.find_commit(to)?;
    let head = repo.head()?;
    let checked_out = head.is_branch() && head.shorthand().ok() == Some(branch);
    let existing = repo.find_branch(branch, BranchType::Local);
    let moved = match existing {
        Ok(existing) => {
            let from = existing.get().peel_to_commit()?.id();
            if let Some(expected) = expected {
                if from != Oid::from_str(expected)? {
                    return Err(CoreError::InvalidArgument {
                        message: format!("{branch} moved meanwhile"),
                    });
                }
            }
            move_branch(&repo, branch, from, to, checked_out)
        }
        Err(_) => {
            repo.branch(branch, &repo.find_commit(to)?, false)?;
            Ok(())
        }
    };
    moved
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
    // A branch pushed for the first time tracks what it was pushed to.
    let mut pushed = repo.find_branch(branch, BranchType::Local)?;
    if pushed.upstream().is_err() {
        // A single-branch clone fetches only its branch: fetch this one too,
        // so it can track it.
        let spec = format!("+refs/heads/{branch}:refs/remotes/{REMOTE}/{branch}");
        let fetched = repo.find_remote(REMOTE)?.fetch_refspecs()?;
        if !fetched
            .iter()
            .any(|s| matches!(s, Ok(Some(found)) if found == spec))
        {
            repo.remote_add_fetch(REMOTE, &spec)?;
        }
        pushed.set_upstream(Some(&format!("{REMOTE}/{branch}")))?;
    }
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
