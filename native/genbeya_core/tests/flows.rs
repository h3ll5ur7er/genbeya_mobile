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
            &[],
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
    let head = git::clone(&f.url, &dir, None, &[], None, &none(), None, None).unwrap();
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
    match git::rebase_branch(&bob, None, &me("Bob"), &[]).unwrap() {
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
        git::rebase_branch(&alice, None, &me("Alice"), &[]).unwrap(),
        RebaseOutcome::FastForwarded { .. }
    ));
    assert_eq!(
        git::rebase_branch(&alice, None, &me("Alice"), &[]).unwrap(),
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
    let outcome = git::rebase_branch(&bob, None, &me("Bob"), &[]).unwrap();
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
    let resolution = Resolution {
        commit: commit.clone(),
        path: "tasks/GM-1.md".into(),
        content: Some(merged.clone().into_bytes()),
    };
    // A resolution names the commit it was made for: for another, it doesn't apply.
    let elsewhere = Resolution {
        commit: "0".repeat(40),
        ..resolution.clone()
    };
    assert!(matches!(
        git::rebase_branch(&bob, None, &me("Bob"), &[elsewhere]).unwrap(),
        RebaseOutcome::Conflicts { .. }
    ));
    match git::rebase_branch(&bob, None, &me("Bob"), &[resolution]).unwrap() {
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
        &[],
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
        &[],
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
    let head = git::clone(
        &url,
        &dir,
        None,
        &[],
        Some(1),
        &none(),
        None,
        Some(&mut report),
    )
    .unwrap();
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
    let blobs = [task.blob.clone(), task.blob.clone()];
    assert_eq!(
        git::read_blobs(&phone, &blobs, 1 << 20).unwrap(),
        vec![
            Some(TASK.as_bytes().to_vec()),
            Some(TASK.as_bytes().to_vec())
        ]
    );
    assert_eq!(git::read_blobs(&phone, &blobs[..1], 4).unwrap(), vec![None]);
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

    // Authors of the checked-out history, renamed by .mailmap.
    let authors = git::commit_authors(&phone, 100).unwrap();
    assert!(!authors.is_empty());
    assert_eq!(authors.iter().map(|a| a.commits).sum::<u32>() as usize, {
        sh(&phone, &["rev-list", "--count", "HEAD"])
            .parse::<usize>()
            .unwrap()
    });
    let first = &authors[0];
    fs::write(
        phone.join(".mailmap"),
        format!("Renamed Person <renamed@example.com> <{}>\n", first.email),
    )
    .unwrap();
    sh(&phone, &["add", ".mailmap"]);
    sh(
        &phone,
        &[
            "-c",
            "user.name=Mapper",
            "-c",
            "user.email=mapper@example.com",
            "commit",
            "-q",
            "-m",
            "mailmap",
        ],
    );
    let mapped = git::commit_authors(&phone, 100).unwrap();
    assert!(mapped
        .iter()
        .any(|a| a.name == "Renamed Person" && a.email == "renamed@example.com"));
    assert_eq!(mapped[0].name, "Mapper", "the newest commit first");
    assert_eq!(git::commit_authors(&phone, 1).unwrap().len(), 1);

    assert_eq!(git::config_value(&phone, "genbeya.branch").unwrap(), None);
    git::set_config_value(&phone, "user.name", Some("Ada Lovelace")).unwrap();
    assert_eq!(
        sh(&phone, &["config", "--local", "user.name"]),
        "Ada Lovelace"
    );
    git::set_config_value(&phone, "user.name", None).unwrap();
    git::set_config_value(&phone, "user.name", None).unwrap();
    let local = Command::new("git")
        .args(["config", "--local", "--get", "user.name"])
        .current_dir(&phone)
        .status()
        .unwrap();
    assert!(!local.success(), "removed from the clone's config");
    sh(&phone, &["config", "genbeya.branch", "content"]);
    assert_eq!(
        git::config_value(&phone, "genbeya.branch")
            .unwrap()
            .as_deref(),
        Some("content")
    );
}

#[test]
fn lists_a_remote_and_clones_its_content_branch_along() {
    let f = Fixture::new();
    let listed = git::remote_branches(&f.url, &none()).unwrap();
    assert_eq!(listed.default_branch.as_deref(), Some("main"));
    assert_eq!(
        listed.branches,
        vec!["genbeya".to_string(), "main".to_string()]
    );

    let dir = f.root.join("with-content");
    let extra = ["genbeya".to_string(), "missing".to_string()];
    let head = git::clone(&f.url, &dir, None, &extra, None, &none(), None, None).unwrap();
    assert_eq!(head.branch.as_deref(), Some("main"));
    let content = git::resolve_commit(&dir, "refs/remotes/origin/genbeya").unwrap();
    assert!(content.is_some(), "the content branch came along");
    assert_eq!(
        git::resolve_commit(&dir, "refs/remotes/origin/missing").unwrap(),
        None
    );
    assert!(
        sh(&dir, &["config", "--get-all", "remote.origin.fetch"]).contains("refs/heads/genbeya"),
        "later fetches include it"
    );

    let refused = git::clone(
        &f.url,
        &f.root.join("nope"),
        Some("nope"),
        &[],
        None,
        &none(),
        None,
        None,
    );
    assert!(
        matches!(refused, Err(CoreError::InvalidArgument { .. })),
        "{refused:?}"
    );
    assert!(!f.root.join("nope").exists());
}

/// US-1: the device makes the Ed25519 key it offers.
#[test]
fn ssh_keys_made_on_the_device() {
    let key = git::generate_ssh_key("Pixel 9 Pro XL").unwrap();
    assert!(key
        .private_key
        .starts_with("-----BEGIN OPENSSH PRIVATE KEY-----\n"));
    assert!(key.public_key.starts_with("ssh-ed25519 AAAA"));
    assert!(key.public_key.ends_with(" Pixel 9 Pro XL"));
    assert!(key.fingerprint.starts_with("SHA256:"));
    assert_ne!(
        git::generate_ssh_key("x").unwrap().private_key,
        key.private_key
    );
}

/// A local sshd serving the fixture's remote, if this machine has one.
struct SshServer {
    child: std::process::Child,
    port: u16,
    host_fingerprint: String,
}

impl Drop for SshServer {
    fn drop(&mut self) {
        let _ = self.child.kill();
    }
}

fn ssh_server(root: &Path, authorized: &str, host_key: &str) -> Option<SshServer> {
    let sshd = Path::new("/usr/sbin/sshd");
    if !sshd.exists() || Command::new("ssh-keygen").arg("-?").output().is_err() {
        return None;
    }
    let dir = root.join(format!("sshd-{host_key}"));
    fs::create_dir_all(&dir).unwrap();
    let key = dir.join("host_key");
    if !key.exists() {
        let made = Command::new("ssh-keygen")
            .args(["-q", "-t", "ed25519", "-N", "", "-f"])
            .arg(&key)
            .output()
            .unwrap();
        assert!(made.status.success());
    }
    fs::write(dir.join("authorized_keys"), format!("{authorized}\n")).unwrap();
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    drop(listener);
    let config = dir.join("sshd_config");
    fs::write(
        &config,
        format!(
            "Port {port}\nListenAddress 127.0.0.1\nHostKey {key}\nAuthorizedKeysFile {auth}\n\
             PasswordAuthentication no\nKbdInteractiveAuthentication no\nPubkeyAuthentication yes\n\
             PermitRootLogin prohibit-password\nStrictModes no\nUsePAM no\nPidFile {pid}\n",
            key = key.display(),
            auth = dir.join("authorized_keys").display(),
            pid = dir.join("sshd.pid").display(),
        ),
    )
    .unwrap();
    fs::create_dir_all("/run/sshd").ok();
    let child = Command::new(sshd)
        .args(["-D", "-e", "-f"])
        .arg(&config)
        .stderr(std::process::Stdio::null())
        .spawn()
        .ok()?;
    let fingerprint = Command::new("ssh-keygen")
        .args(["-l", "-E", "sha256", "-f"])
        .arg(key.with_extension("pub"))
        .output()
        .unwrap();
    let line = String::from_utf8_lossy(&fingerprint.stdout).to_string();
    let host_fingerprint = line.split_whitespace().nth(1)?.to_string();
    let deadline = Instant::now() + Duration::from_secs(5);
    while std::net::TcpStream::connect(("127.0.0.1", port)).is_err() {
        if Instant::now() > deadline {
            return None;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    Some(SshServer {
        child,
        port,
        host_fingerprint,
    })
}

/// US-1 · Clone a private repository over SSH (docs/Experience/User-stories.md).
#[test]
fn clone_and_push_over_ssh_with_a_key_made_on_the_device() {
    let f = Fixture::new();
    let key = git::generate_ssh_key("phone").unwrap();
    let Some(server) = ssh_server(&f.root, &key.public_key, "a") else {
        eprintln!("skipped: no sshd on this machine");
        return;
    };
    let login = std::env::var("USER").unwrap_or_else(|_| "root".into());
    let url = format!(
        "ssh://{login}@127.0.0.1:{}{}",
        server.port,
        f.root.join("remote.git").display()
    );
    let mut options = RemoteOptions {
        auth: Auth::SshKey {
            username: login.clone(),
            public_key: Some(key.public_key.clone()),
            private_key: key.private_key.clone(),
            passphrase: None,
        },
        trusted_host_keys: vec![],
    };

    // The first connection asks about the host's key, with its fingerprint.
    let first = git::clone(
        &url,
        &f.root.join("ssh1"),
        None,
        &[],
        Some(1),
        &options,
        None,
        None,
    );
    match first {
        Err(CoreError::HostKeyUnknown { fingerprint, .. }) => {
            assert_eq!(fingerprint, server.host_fingerprint)
        }
        other => panic!("expected an unknown host key, got {other:?}"),
    }

    // Trusted, the clone works, and so does a push.
    options.trusted_host_keys = vec![server.host_fingerprint.clone()];
    let dir = f.root.join("ssh2");
    let extra = ["genbeya".to_string()];
    git::clone(&url, &dir, None, &extra, Some(1), &options, None, None).unwrap();
    assert!(git::resolve_commit(&dir, "refs/remotes/origin/genbeya")
        .unwrap()
        .is_some());
    edit(
        &dir,
        "docs/Home.md",
        "# Home\n\nFrom the phone, over SSH.\n",
        "Alice",
        "Over SSH",
    );
    assert_eq!(
        git::push(&dir, "main", &options).unwrap(),
        PushOutcome::Pushed
    );
    assert_eq!(
        f.remote_git(&["log", "-1", "--format=%s", "main"]),
        "Over SSH"
    );

    // A key the server doesn't know is refused as an auth failure.
    let stranger = git::generate_ssh_key("stranger").unwrap();
    let refused = git::remote_branches(
        &url,
        &RemoteOptions {
            auth: Auth::SshKey {
                username: login.clone(),
                public_key: Some(stranger.public_key),
                private_key: stranger.private_key,
                passphrase: None,
            },
            trusted_host_keys: options.trusted_host_keys.clone(),
        },
    );
    assert!(
        matches!(refused, Err(CoreError::AuthFailed { .. })),
        "{refused:?}"
    );

    // A changed host key stops it.
    drop(server);
    let Some(other) = ssh_server(&f.root, &key.public_key, "b") else {
        return;
    };
    let url = format!(
        "ssh://{login}@127.0.0.1:{}{}",
        other.port,
        f.root.join("remote.git").display()
    );
    let changed = git::remote_branches(&url, &options);
    assert!(
        matches!(changed, Err(CoreError::HostKeyUnknown { .. })),
        "{changed:?}"
    );
}

#[test]
fn a_files_history_follows_renames_skips_merges_and_knows_a_shallow_end() {
    let tmp = tempfile::tempdir().unwrap();
    let dir = tmp.path().join("repo");
    sh(
        tmp.path(),
        &["init", "-q", "-b", "main", dir.to_str().unwrap()],
    );
    sh(&dir, &["config", "user.name", "Ada"]);
    sh(&dir, &["config", "user.email", "ada@example.com"]);
    let commit = |message: &str| {
        sh(&dir, &["add", "-A"]);
        sh(&dir, &["commit", "-q", "-m", message]);
    };
    fs::create_dir_all(dir.join("tasks")).unwrap();
    fs::write(dir.join("tasks/A-1.md"), TASK.replace("GM-1", "A-1")).unwrap();
    commit("Create A-1");
    fs::write(
        dir.join("tasks/A-1.md"),
        TASK.replace("GM-1", "A-1").replace("todo", "doing"),
    )
    .unwrap();
    commit("A-1: Move to doing");
    fs::create_dir_all(dir.join("tasks/Epic")).unwrap();
    sh(&dir, &["mv", "tasks/A-1.md", "tasks/Epic/A-1.md"]);
    commit("A-1: Move to Epic");
    sh(&dir, &["switch", "-q", "-c", "side"]);
    fs::write(dir.join("README.md"), "side\n").unwrap();
    commit("Side work");
    sh(&dir, &["switch", "-q", "main"]);
    fs::write(
        dir.join("tasks/Epic/A-1.md"),
        TASK.replace("GM-1", "A-1").replace("todo", "done"),
    )
    .unwrap();
    commit("A-1: Done");
    sh(
        &dir,
        &["merge", "-q", "--no-ff", "-m", "Merge side", "side"],
    );

    let head = sh(&dir, &["rev-parse", "HEAD"]);
    let history = git::file_history(&dir, &head, "tasks/Epic/A-1.md", 100, 1 << 20).unwrap();
    let subjects: Vec<&str> = history
        .revisions
        .iter()
        .map(|r| r.subject.as_str())
        .collect();
    assert_eq!(
        subjects,
        [
            "A-1: Done",
            "A-1: Move to Epic",
            "A-1: Move to doing",
            "Create A-1"
        ]
    );
    assert!(!history.truncated);
    let moved = &history.revisions[1];
    assert_eq!(moved.path, "tasks/Epic/A-1.md");
    assert_eq!(moved.old_path.as_deref(), Some("tasks/A-1.md"));
    assert_eq!(moved.before, moved.after, "a move without edits");
    let created = &history.revisions[3];
    assert_eq!(created.old_path, None);
    assert_eq!(created.before, None);
    assert_eq!(created.author, "Ada");
    assert_eq!(
        git::file_history(&dir, &head, "tasks/Epic/A-1.md", 2, 1 << 20)
            .unwrap()
            .revisions
            .len(),
        2
    );
    let small = git::file_history(&dir, &head, "tasks/Epic/A-1.md", 1, 10).unwrap();
    assert_eq!(small.revisions[0].after, None, "larger than the limit");

    // A shallow clone stops where its history does, without claiming a creation.
    let shallow = tmp.path().join("shallow");
    sh(
        tmp.path(),
        &[
            "clone",
            "-q",
            "--depth",
            "2",
            &format!("file://{}", dir.display()),
            shallow.to_str().unwrap(),
        ],
    );
    let head = sh(&shallow, &["rev-parse", "HEAD"]);
    let cut = git::file_history(&shallow, &head, "tasks/Epic/A-1.md", 100, 1 << 20).unwrap();
    assert!(cut.truncated);
    assert!(cut.revisions.iter().all(|r| r.subject != "Create A-1"));
}

#[test]
fn search_finds_what_git_grep_finds() {
    let tmp = tempfile::tempdir().unwrap();
    let dir = tmp.path().join("repo");
    sh(
        tmp.path(),
        &["init", "-q", "-b", "main", dir.to_str().unwrap()],
    );
    sh(&dir, &["config", "user.name", "Ada"]);
    sh(&dir, &["config", "user.email", "ada@example.com"]);
    fs::create_dir_all(dir.join("docs")).unwrap();
    fs::write(
        dir.join("docs/Home.md"),
        "# Home\n\nThe Board shows tasks.\nboards and onboarding\n",
    )
    .unwrap();
    fs::write(
        dir.join("docs/Crlf.md"),
        "line one\r\nthe board\r\nlast\r\n",
    )
    .unwrap();
    fs::write(
        dir.join("docs/Ümlaut.md"),
        "Über die Straße\nmit 😀 board_x\n",
    )
    .unwrap();
    fs::write(dir.join("code.rs"), "fn board() {}\n// TODO: board\n").unwrap();
    fs::write(dir.join("image.bin"), [0u8, 98, 111, 97, 114, 100]).unwrap();
    sh(&dir, &["add", "-A"]);
    sh(&dir, &["commit", "-q", "-m", "Seed"]);
    let head = sh(&dir, &["rev-parse", "HEAD"]);

    let query = |text: &str, case_sensitive: bool, regex: bool, whole_word: bool| GrepQuery {
        text: text.into(),
        case_sensitive,
        regex,
        whole_word,
    };
    // Each query against `git grep` with the same flags.
    let cases: Vec<(GrepQuery, Vec<&str>)> = vec![
        (query("board", false, false, false), vec!["-i", "-F"]),
        (query("Board", true, false, false), vec!["-F"]),
        (query("board", false, false, true), vec!["-i", "-F", "-w"]),
        (query("^the", false, true, false), vec!["-i", "-E"]),
        (query("b(oa)rds?$", false, true, false), vec!["-i", "-E"]),
        (query("straße", false, false, false), vec!["-i", "-F"]),
        (query("nothing-here", false, false, false), vec!["-i", "-F"]),
    ];
    for (q, flags) in cases {
        let mut files = git::grep_files(&dir, &head, &q).unwrap();
        files.sort();
        let mut args = vec!["-c", "core.quotePath=false", "grep", "-l", "-I"];
        args.extend(flags.iter().copied());
        args.extend(["-e", q.text.as_str(), "HEAD", "--"]);
        let out = Command::new("git")
            .args(&args)
            .current_dir(&dir)
            .output()
            .unwrap();
        let mut expected: Vec<String> = String::from_utf8_lossy(&out.stdout)
            .lines()
            .map(|l| l.trim_start_matches("HEAD:").to_string())
            .collect();
        expected.sort();
        assert_eq!(files, expected, "{} with {flags:?}", q.text);

        // The matching lines, as git grep -n numbers them.
        let lines = git::grep_lines(&dir, &head, &files, &q, 100).unwrap();
        let mut ours: Vec<String> = lines
            .iter()
            .flat_map(|f| {
                f.lines
                    .iter()
                    .filter(|l| l.is_match)
                    .map(move |l| format!("{}:{}", f.path, l.line))
            })
            .collect();
        ours.sort();
        let mut args = vec!["-c", "core.quotePath=false", "grep", "-n", "-I"];
        args.extend(flags.iter().copied());
        args.extend(["-e", q.text.as_str(), "HEAD", "--"]);
        let out = Command::new("git")
            .args(&args)
            .current_dir(&dir)
            .output()
            .unwrap();
        let mut theirs: Vec<String> = String::from_utf8_lossy(&out.stdout)
            .lines()
            .map(|l| {
                let l = l.trim_start_matches("HEAD:");
                let mut parts = l.splitn(3, ':');
                format!("{}:{}", parts.next().unwrap(), parts.next().unwrap())
            })
            .collect();
        theirs.sort();
        assert_eq!(ours, theirs, "lines of {} with {flags:?}", q.text);
    }

    // Ranges in UTF-16 units, context lines around a match, a limit per file.
    let found = git::grep_lines(
        &dir,
        &head,
        &["docs/Ümlaut.md".into()],
        &query("board", false, false, false),
        10,
    )
    .unwrap();
    let line = found[0].lines.iter().find(|l| l.is_match).unwrap();
    assert_eq!(line.text, "mit 😀 board_x");
    assert_eq!(line.ranges, vec![GrepRange { start: 7, end: 12 }]);
    assert!(
        found[0].lines.iter().any(|l| !l.is_match && l.line == 1),
        "the line before"
    );
    let limited = git::grep_lines(
        &dir,
        &head,
        &["docs/Home.md".into()],
        &query("board", false, false, false),
        1,
    )
    .unwrap();
    assert_eq!(limited[0].lines.iter().filter(|l| l.is_match).count(), 1);
    assert!(matches!(
        git::grep_files(&dir, &head, &query("(", false, true, false)),
        Err(CoreError::InvalidArgument { .. })
    ));
}

#[test]
fn the_content_branch_rebases_without_a_checkout_and_a_rescue_keeps_everything() {
    let f = Fixture::new();
    let phone = f.clone("phone");
    let desk = f.clone("desk");
    for dir in [&phone, &desk] {
        git::fetch(dir, &["genbeya".into()], &none(), None, None).unwrap();
    }
    let task = |id: &str, status: &str| FileChange {
        path: format!("tasks/{id}.md"),
        content: Some(
            TASK.replace("GM-1", id)
                .replace("todo", status)
                .into_bytes(),
        ),
    };
    // A teammate pushes to the content branch; the phone commits there offline.
    git::commit_onto_branch(
        &desk,
        "genbeya",
        &[task("GM-20", "todo")],
        "Create GM-20",
        &me("Desk"),
    )
    .unwrap();
    assert_eq!(
        git::push(&desk, "genbeya", &none()).unwrap(),
        PushOutcome::Pushed
    );
    let mine = git::commit_onto_branch(
        &phone,
        "genbeya",
        &[task("GM-21", "todo")],
        "Create GM-21",
        &me("Alice"),
    )
    .unwrap();
    let status = git::branch_status(&phone, "genbeya").unwrap();
    assert_eq!(status.commit.as_deref(), Some(mine.as_str()));
    assert_eq!((status.ahead, status.behind), (1, 0));
    assert_eq!(
        git::unpushed_commits(&phone, "genbeya", 10).unwrap()[0].summary,
        "Create GM-21"
    );

    git::fetch(&phone, &[], &none(), None, None).unwrap();
    assert_eq!(git::branch_status(&phone, "genbeya").unwrap().behind, 1);
    let checkout = git::head(&phone).unwrap();
    match git::rebase_branch(&phone, Some("genbeya"), &me("Alice"), &[]).unwrap() {
        RebaseOutcome::Rebased { commits: 1, .. } => {}
        other => panic!("{other:?}"),
    }
    assert_eq!(
        git::head(&phone).unwrap(),
        checkout,
        "the checkout doesn't change"
    );
    assert!(!phone.join("tasks/GM-21.md").exists());
    assert_eq!(
        git::push(&phone, "genbeya", &none()).unwrap(),
        PushOutcome::Pushed
    );
    assert!(f
        .remote_git(&["show", "genbeya:tasks/GM-20.md"])
        .contains("GM-20"));
    assert!(f
        .remote_git(&["show", "genbeya:tasks/GM-21.md"])
        .contains("GM-21"));
    let unknown = git::rebase_branch(&phone, Some("nope"), &me("Alice"), &[]).unwrap();
    assert_eq!(unknown, RebaseOutcome::UpToDate);

    // On the checked-out branch: a rescue branch keeps the local commit and is
    // pushed, then the branch goes back to its upstream, working tree included.
    let local = edit(
        &phone,
        "docs/Home.md",
        "# Home\n\nPhone.\n",
        "Alice",
        "Phone edit",
    );
    let upstream = git::branch_status(&phone, "main")
        .unwrap()
        .upstream_commit
        .unwrap();
    git::set_branch(&phone, "mobile/rescue/alice-2026-11-23", &local, None).unwrap();
    assert_eq!(
        git::push(&phone, "mobile/rescue/alice-2026-11-23", &none()).unwrap(),
        PushOutcome::Pushed
    );
    let rescue = git::branch_status(&phone, "mobile/rescue/alice-2026-11-23").unwrap();
    assert_eq!(
        rescue.upstream.as_deref(),
        Some("origin/mobile/rescue/alice-2026-11-23")
    );
    assert_eq!(rescue.ahead, 0);
    git::set_branch(&phone, "main", &upstream, Some(&local)).unwrap();
    assert_eq!(git::head(&phone).unwrap().commit, upstream);
    assert_eq!(
        fs::read_to_string(phone.join("docs/Home.md")).unwrap(),
        "# Home\n\nWelcome.\n"
    );
    assert!(git::head(&phone).unwrap().dirty.is_empty());
    assert_eq!(
        f.remote_git(&["log", "-1", "--format=%s", "mobile/rescue/alice-2026-11-23"]),
        "Phone edit"
    );

    // Commits moved to a branch of their own: the checkout follows it.
    let own = edit(&phone, "docs/Home.md", "# Home\n\nMine.\n", "Alice", "Mine");
    git::set_branch(&phone, "mobile/alice", &own, None).unwrap();
    git::switch_branch(&phone, "mobile/alice").unwrap();
    git::set_branch(&phone, "main", &upstream, Some(&own)).unwrap();
    assert_eq!(
        git::head(&phone).unwrap().branch.as_deref(),
        Some("mobile/alice")
    );
    assert_eq!(
        fs::read_to_string(phone.join("docs/Home.md")).unwrap(),
        "# Home\n\nMine.\n"
    );
    assert_eq!(git::branch_status(&phone, "main").unwrap().ahead, 0);
    git::switch_branch(&phone, "main").unwrap();

    // Undo an unpushed commit: the branch back to its parent; a stale expectation is refused.
    let undone = edit(&phone, "docs/Home.md", "# Home\n\nOops.\n", "Alice", "Oops");
    assert!(
        git::set_branch(&phone, "main", &upstream, Some(&local)).is_err(),
        "moved meanwhile"
    );
    git::set_branch(&phone, "main", &upstream, Some(&undone)).unwrap();
    assert_eq!(git::branch_status(&phone, "main").unwrap().ahead, 0);
}
