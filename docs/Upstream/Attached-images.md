# Attached images

A spec for Genbeya: where images that people paste, drop or take with a camera are kept for **pages, tasks and pull requests**, how they are referenced, and what Genbeya does with them, so every client (desktop, VS Code, the mobile app, coding agents) writes them the same way.

**Decided** (by the maintainer): screenshots in tasks and pull requests come to Genbeya. The rest of this page is proposed.

[TOC]

## What already works

Genbeya renders images stored in the repository wherever it shows Markdown. A link is resolved against the file it is in, and a link that starts with `/` from the repository's root (`resolveLinkPath` in `src/utilities/repository-path.ts`). `content.image` serves PNG, JPEG, GIF, WebP, SVG and AVIF up to 10 MB. Remote images never load.

What's missing is a convention: where a new image goes, what it is called, how it is referenced so that moving a task doesn't break it, and how review files keep their approvals when screenshots are added. And a way to add one: today, an image is a file someone copies in by hand.

## The convention

| Belongs to | Folder | Referenced as |
| --- | --- | --- |
| A page | `<wikiRoot>/images/` | Relative to the page: `![Board](images/2026-11-21-board.png)` from `docs/Home.md`, `../images/…` from a subpage |
| A task, its comments and its time log | `<taskRoot>/.images/<task ID>/` | From the repository root: `![Login error](/tasks/.images/GM-14/2026-11-21-login-error.png)` |
| A pull request, its review and its discussion | `<pullRoot>/.images/<pull request ID>/` | From the repository root: `![Before](/pulls/.images/PR-7/2026-11-23-before.png)` |

- **Pages** keep what Genbeya's own wiki does: one `images` folder in the wiki, relative links, so pages still render on GitHub, in any editor and in static site generators that publish the wiki folder. Moving a page already rewrites relative links that point out of it.
- **Tasks and pull requests** keep their images in a folder named after their ID. IDs never change, so the folder never moves. Folders starting with a dot hold no tasks, and the pull request folder only counts Markdown files directly in it, so `.images` is neither an epic nor a pull request.
- **References from the root** survive moving a task into another epic without rewriting anything, read the same at every depth, and render on GitHub, GitLab and in VS Code's preview. Tasks and pull requests aren't published as a site, which is the one place root links break.
- **Names** are `<date>-<slug>.<extension>`: the date the image was added, and a slug made from its alt text (lowercase letters, digits and dashes, up to 60 characters), `screenshot` or `photo` without one. A name that's taken gets `-2`, `-3`.
- **Alt text** is asked for when the image is added, prefilled with *Screenshot* or *Photo*.

The test for the format holds: someone without Genbeya sees `![Login error](/tasks/.images/GM-14/…)`, knows what it is, finds the file with `git ls-files`, and sees the image on the forge.

## Adding an image

Every client prepares the image the same way before anything is written:

| Step | Rule |
| --- | --- |
| Accept | PNG, JPEG, WebP and GIF; HEIC and HEIF (iPhone photos) are converted to JPEG. SVG is refused: it can carry scripts, and it is rarely what was pasted |
| Orient | The camera's rotation applied to the pixels |
| Shrink | Photos to 1600 pixels on the long side; screenshots to 2560, so text stays readable |
| Encode | Screenshots as PNG, or lossless WebP when the PNG is over 1 MB; photos as JPEG at quality 82; GIFs kept as they are |
| Strip | Every metadata block: EXIF with GPS position and camera, XMP, IPTC, comments. Re-encoding through a canvas drops them; the backend checks again |
| Limit | Over 5 MB after all this is refused, with the size shown |
| Show | The resulting size before saving: an image stays in the history for good |

A **screenshot** is an image from the clipboard or the system's screenshot tool; a **photo** is one from the camera or with camera metadata.

## What Genbeya does

- **Editors** (pages, task descriptions, the comment box, pull request replies and code range comments): paste or drop an image, or **Insert image…**, and the reference goes where the cursor was.
- **One manager call**, `content.addImage(workspace, owner, alt, bytes)`, with `owner` naming the page, task or pull request. It picks the folder and the name, checks the type by its first bytes, the size and that no metadata is left, writes the file where the owner's area lives, and answers the reference text. Areas on the [Content branch](https://github.com/genbeya/genbeya/blob/develop/docs/Architecture/Content-branch.md) commit right away, as other edits there do. The [Demo](https://github.com/genbeya/genbeya/blob/develop/docs/Architecture/Demo.md) needs the same call: its working tree already keeps bytes behind a marker (`file-bytes.ts`).
- **Deleting a task** deletes `.images/<ID>/` in the same change.
- **Moving a task** into another epic leaves the images where they are. Relative links into `.images/<ID>/`, which other tools may write (VS Code's paste writes relative links), are rewritten by the move like page links are.
- **Promoting** a pull request's to-do to a task in **Clean up…** copies the images it references into the new task's folder and points the references there. **Shorten to outcome…** leaves images no longer referenced where they are.
- **Images nobody references** are never deleted by Genbeya. A list of unused images is a later step.
- **Areas**: images in the task folder belong to the tasks, in the pull request folder to the pull requests, in the wiki folder to the wiki, wherever those live. `.genbeya-content` needs no change.
- **Search** skips them, as it skips every binary file.

### Pull requests and their approvals

The change ID today leaves out Markdown files directly in the pull request folder (`:(exclude,glob)pulls/*.md` in `src/access/git/pull-access.ts`), so replies and verdicts committed to the source branch keep approvals. Screenshots added to a review must keep them too:

- The change ID also leaves out `<pullRoot>/.images/<ID>/` files of the allowed types: one exclude per extension, `:(exclude,glob)pulls/.images/*/*.png` and so on, since Git's globs have no braces.
- Anything else in `.images` counts as code and is reviewed, so nothing executable can hide in the folder, as today.
- Every client computes the change ID with exactly these excludes; the mobile app checks it with conformance cases.

### Agents and VS Code

- **The agent skill** learns the convention in its Tasks and Pull requests sections: put screenshots in `tasks/.images/<ID>/` or `pulls/.images/<ID>/`, named as above, referenced from the root, without metadata. A coding agent that takes screenshots of what it built can then attach them to its pull request.
- **VS Code** shows the images in its previews already. The extension can preset `markdown.copyFiles.destination` so pasting into a task file stores the image in `tasks/.images/${documentBaseName}/`.

### The Guide

[Tasks](https://github.com/genbeya/genbeya/blob/develop/docs/Guide/Tasks.md), [Pull requests](https://github.com/genbeya/genbeya/blob/develop/docs/Guide/Pull-requests.md) and [Wiki](https://github.com/genbeya/genbeya/blob/develop/docs/Guide/Wiki.md) each get a paragraph on adding images; [Managers](https://github.com/genbeya/genbeya/blob/develop/docs/Architecture/Managers.md) gets the call and the change ID rule.

## Options considered

| Choice | Options | Proposed, and why |
| --- | --- | --- |
| How tasks reference images | Relative links; links from the root; `![[…]]` embeds | **From the root**: survives epic moves without rewriting and renders on forges; relative links break on every move unless rewritten; embeds render nowhere but Genbeya |
| Where task images live | Next to the task file; one shared folder; a folder per task ID | **A folder per ID**: an image's owner is visible in its path, a deleted task takes its images along, epic moves don't touch them |
| The folder's name | `.images`, `.attachments`, `assets` | **`.images`**: it says what is allowed in it, which the change ID rule relies on. `.attachments` would invite logs and archives that review must then see |
| Where page images live | Next to each page; one folder in the wiki | **One folder**, as Genbeya's own wiki keeps them, linked relatively |
| Image size | Kept as taken; shrunk | **Shrunk**: repositories never forget a 12-megapixel photo |

## Done when

- [ ] Paste, drop and **Insert image…** in all four editors write the image by these rules and insert the reference
- [ ] `content.addImage` in the backend, the demo and VS Code, with its checks
- [ ] Metadata stripped and checked; HEIC converted; SVG refused; 5 MB limit
- [ ] The change ID leaves out allowed images in `<pullRoot>/.images/`, with a test that a screenshot keeps an approval and that a script in the folder makes it stale
- [ ] Deleting a task deletes its images; moving one rewrites relative links into its folder; promoting copies them
- [ ] The agent skill and the Guide describe the convention

## Until Genbeya has it

The mobile app follows this spec from the start, so nothing it writes has to change later:

- **Pages** need nothing new in Genbeya: images in `<wikiRoot>/images/`, linked relatively, render on desktop today. The trial adds them ([[GM-16]]).
- **Tasks** would render on desktop today as well, since root links resolve already. They still wait for release, as decided ([[Decisions]], D8), so that the format is agreed before images exist in real task folders ([[GM-26]]).
- **Pull requests** wait for Genbeya's change ID rule: before it, a screenshot in a review would make every approval look stale on desktop. The mobile app writes no image into `<pullRoot>/.images/` until a Genbeya release has the rule ([[GM-26]]).
- **Renumbering** a task at sync (when a teammate took its ID meanwhile, see [[Call chains#c10-sync]]) moves its `.images/<ID>/` folder and rewrites its references in the same commits ([[GM-11]]).

## Open questions

- **Lossless WebP** for large screenshots: every forge renders WebP today, but some older tools don't. PNG only, at the cost of size?
- **Alt text**: ask every time, or only on desktop where typing is cheap?
- **Unused images**: list them in Settings, in **Clean up…**, or not at all?
- **Large animated GIFs** from screen recorders: keep the 5 MB limit for them too?
