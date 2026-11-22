//! The Git core's flows on this machine: a bare repository plays the remote,
//! clones play the phone and a teammate. Fixtures are made with the git CLI;
//! everything under test goes through `genbeya_core::git`.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, Instant};

use genbeya_core::git::{self, *};

fn sh(dir: &Path, args: &[&str]) -> String {
    let out = Command::new("git")
        .args(args)
        .current_dir(dir)
        .output()
        .expect("git runs");
    assert!(
        out.status.success(),
        "git {args:?}: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8_lossy(&out.stdout).trim().to_string()
}

fn me(name: &str) -> Identity {
    Identity {
        name: name.into(),
        email: format!("{}@example.com", name.to_lowercase()),
    }
}

const TASK: &str = "---\nid: GM-1\ntitle: First task\nstatus: todo\n---\n\nDo it.\n";

/// A bare remote with `main` (a task, a page, a symbolic link) and a content branch `genbeya`.
struct Fixture {
    _tmp: tempfile::TempDir,
    root: PathBuf,
    url: String,
}

impl Fixture {
    fn new() -> Self {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path().to_path_buf();
        let remote = root.join("remote.git");
        sh(
            &root,
            &[
                "init",
                "--bare",
                "-q",
                "-b",
                "main",
                remote.to_str().unwrap(),
            ],
        );
        let seed = root.join("seed");
        sh(
            &root,
            &[
                "clone",
                "-q",
                remote.to_str().unwrap(),
                seed.to_str().unwrap(),
            ],
        );
        sh(&seed, &["config", "user.name", "Seed"]);
        sh(&seed, &["config", "user.email", "seed@example.com"]);
        fs::create_dir_all(seed.join("tasks")).unwrap();
        fs::create_dir_all(seed.join("docs")).unwrap();
        fs::write(seed.join("tasks/GM-1.md"), TASK).unwrap();
        fs::write(seed.join("docs/Home.md"), "# Home\n\nWelcome.\n").unwrap();
        fs::write(seed.join("README.md"), "readme\n").unwrap();
        std::os::unix::fs::symlink("README.md", seed.join("link")).unwrap();
        sh(&seed, &["add", "-A"]);
        sh(&seed, &["commit", "-q", "-m", "Seed"]);
        for i in 0..5 {
            fs::write(seed.join("docs/Log.md"), format!("# Log\n\n{i}\n")).unwrap();
            sh(&seed, &["add", "-A"]);
            sh(&seed, &["commit", "-q", "-m", &format!("Log {i}")]);
        }
        sh(&seed, &["push", "-q", "origin", "main"]);
        sh(&seed, &["switch", "-q", "--orphan", "genbeya"]);
        fs::create_dir_all(seed.join("tasks")).unwrap();
        fs::write(seed.join("tasks/GM-9.md"), TASK.replace("GM-1", "GM-9")).unwrap();
        sh(&seed, &["add", "tasks"]);
        sh(&seed, &["commit", "-q", "-m", "Content branch"]);
        sh(&seed, &["push", "-q", "origin", "genbeya"]);
        let url = format!("file://{}", remote.display());
        Fixture {
            _tmp: tmp,
            root,
            url,
        }
    }

    fn clone(&self, name: &str) -> PathBuf {
        let dir = self.root.join(name);
        git::clone(
            &self.url,
            &dir,
            Some("main"),
            None,
            &RemoteOptions::default(),
            None,
            None,
        )
        .unwrap();
        dir
    }

    fn remote_git(&self, args: &[&str]) -> String {
        sh(&self.root.join("remote.git"), args)
    }
}

fn edit(dir: &Path, path: &str, text: &str, who: &str, message: &str) -> String {
    fs::write(dir.join(path), text).unwrap();
    git::commit_files(dir, &[path.to_string()], message, &me(who)).unwrap()
}

fn none() -> RemoteOptions {
    RemoteOptions::default()
}

#[test]
fn clone_sets_up_a_tracking_branch_and_plain_symlinks() {
    let f = Fixture::new();
    let dir = f.clone("phone");
    let head = git::head(&dir).unwrap();
    assert_eq!(head.branch.as_deref(), Some("main"));
    assert_eq!(head.upstream.as_deref(), Some("origin/main"));
    assert_eq!((head.ahead, head.behind), (0, 0));
    assert!(head.dirty.is_empty(), "{:?}", head.dirty);
    let link = fs::symlink_metadata(dir.join("link")).unwrap();
    assert!(
        link.file_type().is_file(),
        "symbolic links are checked out as plain files"
    );
    assert_eq!(fs::read_to_string(dir.join("link")).unwrap(), "README.md");
}

#[test]
fn default_branch_comes_from_the_remote() {
    let f = Fixture::new();
    let dir = f.root.join("phone");
    let head = git::clone(&f.url, &dir, None, None, &none(), None, None).unwrap();
    assert_eq!(head.branch.as_deref(), Some("main"));
}

#[test]
fn commit_push_and_a_teammate_rebases_in_memory() {
    let f = Fixture::new();
    let alice = f.clone("alice");
    let bob = f.clone("bob");

    edit(
        &alice,
        "tasks/GM-1.md",
        &TASK.replace("status: todo", "status: review"),
        "Alice",
        "GM-1: Move to review",
    );
    assert_eq!(git::head(&alice).unwrap().ahead, 1);
    assert_eq!(
        git::push(&alice, "main", &none()).unwrap(),
        PushOutcome::Pushed
    );
    assert_eq!(
        git::push(&alice, "main", &none()).unwrap(),
        PushOutcome::UpToDate
    );

    // Bob edited another file meanwhile: his push is refused, never forced.
    edit(
        &bob,
        "docs/Home.md",
        "# Home\n\nWelcome, Bob.\n",
        "Bob",
        "Greet Bob",
    );
    match git::push(&bob, "main", &none()).unwrap() {
        PushOutcome::Rejected { .. } => {}
        other => panic!("expected a rejection, got {other:?}"),
    }
    git::fetch(&bob, &[], &none(), None, None).unwrap();
    assert_eq!(git::head(&bob).unwrap().behind, 1);
    match git::rebase_onto_upstream(&bob, &me("Bob"), &[]).unwrap() {
        RebaseOutcome::Rebased { commits, .. } => assert_eq!(commits, 1),
        other => panic!("{other:?}"),
    }
    let head = git::head(&bob).unwrap();
    assert_eq!((head.ahead, head.behind), (1, 0));
    assert!(head.dirty.is_empty());
    assert!(
        fs::read_to_string(bob.join("tasks/GM-1.md"))
            .unwrap()
            .contains("status: review"),
        "upstream change checked out"
    );
    assert!(
        fs::read_to_string(bob.join("docs/Home.md"))
            .unwrap()
            .contains("Bob"),
        "local change kept"
    );
    assert_eq!(
        git::push(&bob, "main", &none()).unwrap(),
        PushOutcome::Pushed
    );

    // Alice has nothing local: she fast-forwards.
    git::fetch(&alice, &[], &none(), None, None).unwrap();
    assert!(matches!(
        git::rebase_onto_upstream(&alice, &me("Alice"), &[]).unwrap(),
        RebaseOutcome::FastForwarded { .. }
    ));
    assert_eq!(
        git::rebase_onto_upstream(&alice, &me("Alice"), &[]).unwrap(),
        RebaseOutcome::UpToDate
    );
    assert!(fs::read_to_string(alice.join("docs/Home.md"))
        .unwrap()
        .contains("Bob"));
    // The rebased commit keeps Bob as its author.
    assert_eq!(
        f.remote_git(&["log", "-1", "--format=%an <%ae>", "main"]),
        "Bob <bob@example.com>"
    );
}

#[test]
fn a_conflict_is_reported_without_touching_anything_then_resolved() {
    let f = Fixture::new();
    let alice = f.clone("alice");
    let bob = f.clone("bob");
    edit(
        &alice,
        "tasks/GM-1.md",
        &TASK.replace("status: todo", "status: done"),
        "Alice",
        "GM-1: Done",
    );
    git::push(&alice, "main", &none()).unwrap();

    let mine = TASK.replace("status: todo", "status: in-progress");
    let bob_commit = edit(&bob, "tasks/GM-1.md", &mine, "Bob", "GM-1: Start");
    git::fetch(&bob, &[], &none(), None, None).unwrap();
    let before = git::head(&bob).unwrap();
    let outcome = git::rebase_onto_upstream(&bob, &me("Bob"), &[]).unwrap();
    let RebaseOutcome::Conflicts { commit, conflicts } = outcome else {
        panic!("{outcome:?}")
    };
    assert_eq!(commit, bob_commit);
    assert_eq!(conflicts.len(), 1);
    let c = &conflicts[0];
    assert_eq!(c.path, "tasks/GM-1.md");
    assert_eq!(c.ancestor.as_deref(), Some(TASK.as_bytes()));
    // In a rebase, "ours" is the upstream being built on and "theirs" the local commit replayed.
    assert!(String::from_utf8_lossy(c.ours.as_ref().unwrap()).contains("status: done"));
    assert!(String::from_utf8_lossy(c.theirs.as_ref().unwrap()).contains("status: in-progress"));
    // Nothing moved: same HEAD, same file, no rebase left behind.
    assert_eq!(git::head(&bob).unwrap(), before);
    assert_eq!(fs::read_to_string(bob.join("tasks/GM-1.md")).unwrap(), mine);
    assert!(!bob.join(".git/rebase-merge").exists() && !bob.join(".git/rebase-apply").exists());

    // The Genbeya merge (in Dart) decides; the core applies its result.
    let merged = TASK.replace("status: todo", "status: done\nassignee: bob");
    let resolution = FileChange {
        path: "tasks/GM-1.md".into(),
        content: Some(merged.clone().into_bytes()),
    };
    match git::rebase_onto_upstream(&bob, &me("Bob"), &[resolution]).unwrap() {
        RebaseOutcome::Rebased { commits: 1, .. } => {}
        other => panic!("{other:?}"),
    }
    assert_eq!(
        fs::read_to_string(bob.join("tasks/GM-1.md")).unwrap(),
        merged
    );
    assert!(git::head(&bob).unwrap().dirty.is_empty());
    assert_eq!(
        git::push(&bob, "main", &none()).unwrap(),
        PushOutcome::Pushed
    );
    assert_eq!(
        f.remote_git(&["show", "main:tasks/GM-1.md"]),
        merged.trim_end()
    );
}

#[test]
fn commits_onto_the_content_branch_without_a_checkout() {
    let f = Fixture::new();
    let phone = f.clone("phone");
    git::fetch(&phone, &["genbeya".into()], &none(), None, None).unwrap();
    let task = TASK.replace("GM-1", "GM-10");
    let changes = [FileChange {
        path: "tasks/GM-10.md".into(),
        content: Some(task.clone().into_bytes()),
    }];
    git::commit_onto_branch(&phone, "genbeya", &changes, "Create GM-10", &me("Alice")).unwrap();
    assert!(
        !phone.join("tasks/GM-10.md").exists(),
        "the checkout doesn't change"
    );
    assert_eq!(git::head(&phone).unwrap().branch.as_deref(), Some("main"));
    assert_eq!(
        git::push(&phone, "genbeya", &none()).unwrap(),
        PushOutcome::Pushed
    );
    assert_eq!(
        f.remote_git(&["show", "genbeya:tasks/GM-10.md"]),
        task.trim_end()
    );
    assert_eq!(
        f.remote_git(&["show", "genbeya:tasks/GM-9.md"]),
        TASK.replace("GM-1", "GM-9").trim_end(),
        "the rest of the branch kept"
    );

    // Deleting works the same way; the checked-out branch is refused.
    let delete = [FileChange {
        path: "tasks/GM-9.md".into(),
        content: None,
    }];
    git::commit_onto_branch(&phone, "genbeya", &delete, "Remove GM-9", &me("Alice")).unwrap();
    let refused = git::commit_onto_branch(&phone, "main", &changes, "x", &me("Alice"));
    assert!(
        matches!(refused, Err(CoreError::InvalidArgument { .. })),
        "{refused:?}"
    );
}

#[test]
fn diff_and_conflict_check_between_branches() {
    let f = Fixture::new();
    let phone = f.clone("phone");
    sh(&phone, &["switch", "-q", "-c", "feature/GM-1"]);
    sh(&phone, &["config", "user.name", "Sam"]);
    sh(&phone, &["config", "user.email", "sam@example.com"]);
    fs::write(
        phone.join("tasks/GM-1.md"),
        TASK.replace("Do it.", "Do it well."),
    )
    .unwrap();
    sh(&phone, &["mv", "docs/Home.md", "docs/Start.md"]);
    sh(&phone, &["commit", "-qam", "Feature"]);
    sh(&phone, &["switch", "-q", "main"]);
    fs::write(
        phone.join("tasks/GM-1.md"),
        TASK.replace("Do it.", "Do it now."),
    )
    .unwrap();
    sh(&phone, &["commit", "-qam", "Main moves on"]);

    let diff = git::diff_from_merge_base(&phone, "feature/GM-1", "main").unwrap();
    let mut files: Vec<_> = diff
        .files
        .iter()
        .map(|f| (f.status.as_str(), f.path.as_str(), f.old_path.as_deref()))
        .collect();
    files.sort();
    let mut expected = vec![
        ("M", "tasks/GM-1.md", None),
        ("R", "docs/Start.md", Some("docs/Home.md")),
    ];
    expected.sort();
    assert_eq!(files, expected);
    assert!(diff.patch.contains("+Do it well."), "{}", diff.patch);
    // The same as git's own diff of those files.
    let git_patch = sh(
        &phone,
        &[
            "diff",
            "--no-color",
            "--full-index",
            "-M",
            &format!("{}..{}", diff.base, diff.head),
        ],
    );
    assert_eq!(diff.patch.trim_end(), git_patch);

    assert_eq!(
        git::merge_conflicts(&phone, "feature/GM-1", "main").unwrap(),
        vec!["tasks/GM-1.md".to_string()]
    );
    assert!(
        git::head(&phone).unwrap().dirty.is_empty(),
        "checked in memory"
    );
}

#[test]
fn log_of_a_path() {
    let f = Fixture::new();
    let phone = f.clone("phone");
    edit(
        &phone,
        "tasks/GM-1.md",
        &TASK.replace("todo", "in-progress"),
        "Alice",
        "GM-1: Start",
    );
    edit(&phone, "docs/Home.md", "# Home\n", "Alice", "Unrelated");
    edit(
        &phone,
        "tasks/GM-1.md",
        &TASK.replace("todo", "done"),
        "Alice",
        "GM-1: Done",
    );
    let log = git::log_path(&phone, "tasks/GM-1.md", 10).unwrap();
    let summaries: Vec<_> = log.iter().map(|c| c.summary.as_str()).collect();
    assert_eq!(summaries, vec!["GM-1: Done", "GM-1: Start", "Seed"]);
    assert_eq!(git::log_path(&phone, "tasks/GM-1.md", 1).unwrap().len(), 1);
}

#[test]
fn shallow_clone_over_the_git_protocol() {
    // libgit2's local transport doesn't do shallow fetches; git daemon speaks the smart protocol.
    let f = Fixture::new();
    let port = 19418 + (std::process::id() % 500) as u16;
    let pid_file = f.root.join("daemon.pid");
    let mut daemon = Command::new("git")
        .args([
            "daemon",
            "--reuseaddr",
            "--export-all",
            "--listen=127.0.0.1",
            &format!("--port={port}"),
            &format!("--base-path={}", f.root.display()),
        ])
        .arg(format!("--pid-file={}", pid_file.display()))
        .arg(f.root.to_str().unwrap())
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .expect("git daemon starts");
    std::thread::sleep(Duration::from_millis(500));
    let dir = f.root.join("shallow");
    let result = git::clone(
        &format!("git://127.0.0.1:{port}/remote.git"),
        &dir,
        Some("main"),
        Some(2),
        &none(),
        None,
        None,
    );
    if let Ok(pid) = fs::read_to_string(&pid_file) {
        Command::new("kill").arg(pid.trim()).status().ok();
    }
    daemon.kill().ok();
    daemon.wait().ok();
    let head = result.unwrap();
    assert!(head.shallow);
    assert_eq!(sh(&dir, &["rev-list", "--count", "HEAD"]), "2");
}

#[test]
fn a_cancelled_clone_leaves_nothing() {
    let f = Fixture::new();
    let dir = f.root.join("cancelled");
    let op = Operation::start(42);
    let mut cancel_on_first = |_p: Progress| git::cancel(42);
    let result = git::clone(
        &f.url,
        &dir,
        Some("main"),
        None,
        &none(),
        Some(&op),
        Some(&mut cancel_on_first),
    );
    assert!(matches!(result, Err(CoreError::Cancelled)), "{result:?}");
    assert!(!dir.exists());
}

#[test]
fn bad_paths_are_refused() {
    let f = Fixture::new();
    let phone = f.clone("phone");
    for path in ["../outside", ".git/config", "/etc/passwd"] {
        let r = git::commit_files(&phone, &[path.to_string()], "x", &me("Alice"));
        assert!(
            matches!(r, Err(CoreError::InvalidPath { .. })),
            "{path}: {r:?}"
        );
    }
}

#[test]
fn stale_locks_are_cleared_fresh_ones_kept() {
    let f = Fixture::new();
    let phone = f.clone("phone");
    fs::write(phone.join(".git/index.lock"), "").unwrap();
    fs::create_dir_all(phone.join(".git/refs/heads")).unwrap();
    fs::write(phone.join(".git/refs/heads/main.lock"), "").unwrap();
    Command::new("touch")
        .args([
            "-d",
            "2 hours ago",
            phone.join(".git/index.lock").to_str().unwrap(),
        ])
        .status()
        .unwrap();
    let removed = git::clear_stale_locks(&phone, Duration::from_secs(600)).unwrap();
    assert_eq!(removed, vec!["index.lock".to_string()]);
    assert!(phone.join(".git/refs/heads/main.lock").exists());
}

/// A real HTTPS clone through this machine's network: `cargo test -- --ignored`.
/// GENBEYA_TEST_URL picks the repository; SSL_CERT_FILE the CA bundle.
#[test]
#[ignore]
fn https_shallow_clone_of_a_real_repository() {
    let url = std::env::var("GENBEYA_TEST_URL")
        .unwrap_or_else(|_| "https://github.com/h3ll5ur7er/genbeya_mobile.git".into());
    if let Ok(bundle) = std::env::var("SSL_CERT_FILE") {
        git::set_ca_locations(Some(&bundle), None).unwrap();
    }
    let tmp = tempfile::tempdir().unwrap();
    let dir = tmp.path().join("clone");
    let started = Instant::now();
    let mut last = None;
    let mut report = |p: Progress| last = Some(p);
    let head = git::clone(&url, &dir, None, Some(1), &none(), None, Some(&mut report)).unwrap();
    let elapsed = started.elapsed();
    let size = Command::new("du")
        .args(["-sk", dir.to_str().unwrap()])
        .output()
        .unwrap();
    println!(
        "cloned {url} ({:?}) in {elapsed:.2?}: {:?}, {} KB on disk",
        head.branch,
        last,
        String::from_utf8_lossy(&size.stdout)
            .split_whitespace()
            .next()
            .unwrap_or("?")
    );
    assert!(head.shallow);
}

#[test]
fn reads_files_from_objects_for_the_repository_model() {
    let f = Fixture::new();
    let phone = f.clone("phone");
    let head = git::resolve_commit(&phone, "HEAD").unwrap().unwrap();
    assert_eq!(head, git::head(&phone).unwrap().commit);
    assert_eq!(
        git::resolve_commit(&phone, "refs/heads/nope").unwrap(),
        None
    );

    let files = git::list_files(&phone, &head).unwrap();
    let task = files
        .iter()
        .find(|file| file.path == "tasks/GM-1.md")
        .expect("the task is listed with its folder");
    assert_eq!(task.size, TASK.len() as u64);
    assert!(!task.link);
    assert!(
        files.iter().any(|file| file.link),
        "the symbolic link is marked"
    );
    assert_eq!(
        git::read_blob(&phone, &task.blob, 1 << 20).unwrap(),
        TASK.as_bytes()
    );
    assert!(matches!(
        git::read_blob(&phone, &task.blob, 4),
        Err(CoreError::InvalidArgument { .. })
    ));
    assert_eq!(
        git::read_file_at(&phone, &head, "tasks/GM-1.md", 1 << 20).unwrap(),
        Some(TASK.as_bytes().to_vec())
    );
    assert_eq!(
        git::read_file_at(&phone, &head, "tasks/none.md", 1 << 20).unwrap(),
        None
    );
    assert!(git::read_file_at(&phone, &head, "../x", 10).is_err());

    // The content branch, read without a checkout; a commit onto it changes one path.
    git::fetch(&phone, &["genbeya".into()], &none(), None, None).unwrap();
    let before = git::resolve_commit(&phone, "refs/remotes/origin/genbeya")
        .unwrap()
        .expect("the remote's content branch");
    let changes = [FileChange {
        path: "tasks/GM-11.md".into(),
        content: Some(TASK.replace("GM-1", "GM-11").into_bytes()),
    }];
    let after =
        git::commit_onto_branch(&phone, "genbeya", &changes, "Create GM-11", &me("Alice")).unwrap();
    assert_eq!(
        git::changed_paths(&phone, &before, &after).unwrap(),
        vec!["tasks/GM-11.md".to_string()]
    );
    assert!(git::changed_paths(&phone, &after, &after)
        .unwrap()
        .is_empty());

    assert_eq!(git::config_value(&phone, "genbeya.branch").unwrap(), None);
    sh(&phone, &["config", "genbeya.branch", "content"]);
    assert_eq!(
        git::config_value(&phone, "genbeya.branch")
            .unwrap()
            .as_deref(),
        Some("content")
    );
}
