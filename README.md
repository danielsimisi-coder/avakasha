<p align="center"><img src="assets/keepelix-preview.png" alt="Keepelix — actual app with generated demo files" width="100%"></p>

<p align="center">
  <a href="https://github.com/danielsimisi-coder/keepelix/actions/workflows/ci.yml"><img alt="macOS checks" src="https://github.com/danielsimisi-coder/keepelix/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="macOS 13 or later" src="https://img.shields.io/badge/macOS-13%2B-163a3a">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-33785e"></a>
  <img alt="Beta" src="https://img.shields.io/badge/status-beta-d8a354">
</p>

<p align="center"><strong>Review large files with your eyes and your keyboard.</strong><br>Choose a folder. Preview a file. Keep it or move it to Trash. Continue.</p>

<p align="center"><a href="https://github.com/danielsimisi-coder/keepelix/releases">Releases</a> · <a href="docs/DISTRIBUTION.md">Build from source</a> · <a href="docs/PRIVACY.md">Privacy</a> · <a href="docs/SAFETY.md">Safety</a> · <a href="docs/README.he.md">עברית</a></p>

## Your Mac is full. But full of what?

Keepelix was born from a recurring frustration: **storage keeps filling up, you do not know where the space has gone, and the Mac’s built-in tools do not give you a clear, convenient way to work through the problem.**

A storage total tells you that you have a problem. A folder full of unfamiliar filenames still leaves the hard part: finding the large files, seeing what they actually contain, and deciding what you can let go of without losing something important.

The first pile we tackled was accumulated WhatsApp media: old videos, repeated images and forgotten attachments mixed with useful files and client material. But WhatsApp was one example of the broader problem. Downloads, Movies and external drives can build up the same way.

Keepelix makes the review practical. Choose a folder or drive, sort by size, and work through the files: **Space to preview, Delete to move to Trash, ↓ to continue.** Older-file filters and duplicate suggestions help narrow the pile; Undo helps recover from a mistaken move. You decide what matters.

**No WhatsApp account connection. No cloud analysis. No automatic permanent deletion.** Keepelix reviews your chosen location; it does not automatically diagnose every source of disk usage, read conversations or identify client files.

## What it does

| Review | Compare | Stay in control |
|---|---|---|
| Space for Quick Look; arrows for the next file | SHA-256 exact-copy groups | Confirmed batch moves to macOS Trash |
| Command/Shift multi-selection | Select extra copies while keeping one | Undo and redo batches during this session |
| Filter by name, type and size | Opt-in, local similar-image suggestions | Changed-file and path checks before each move |
| Right-click to reveal the original in Finder | Paired previews for comparison | Progress, cancellation and per-file errors |
| Explicit resume of your last folder and position | Hard links are not treated as extra copies | No private file inventory in the app bundle |

## Try the beta

**macOS 13 or later.** The release package contains a universal Apple Silicon + Intel app.

1. Get the ZIP from [Releases](https://github.com/danielsimisi-coder/keepelix/releases), extract it, and open Keepelix.
2. Click **WhatsApp**, **Downloads**, **Movies**, **Pictures**, **Documents** or **Desktop**, or choose **Other folder or drive**. Each scans only the selected location. WhatsApp checks its local media folder on click and offers a folder picker if unavailable; no account connection is needed. Pictures skips Photos library packages.
3. Select a row and press **Space**. Use **↓** or **Keep & next** to continue.
4. Use **⌘-click** or **Shift-click** to select several files. The count and size are shown before you confirm **Move to Trash**.

**Signing status:** the initial private beta is ad-hoc signed, **not Apple-notarized**. Gatekeeper may block a downloaded build. Do not disable Gatekeeper; building from source is the alternative until a Developer ID-signed, notarized release is available. See [distribution instructions](docs/DISTRIBUTION.md).

## Keyboard controls

| Key | Action |
|---|---|
| `Space` | Toggle the selected file's preview |
| `↑` / `↓` | Move through the list |
| `⌘` + click | Add or remove a file from the selection |
| `Shift` + click | Select a range |
| `⌘A` | Select the filtered list; in search text, select the text |
| `Delete` / `⌘⌫` | Move selected files to Trash (confirmation enabled by default) |
| `⌘Z` | Restore the latest Trash batch from this app session |
| `⇧⌘Z` | Redo the last restored batch with fresh safety checks |
| Right-click | Reveal the clicked original in Finder |

## Exact is different from similar

**Exact duplicates** have matching SHA-256 content hashes. “Select extra copies” leaves one deterministic keeper per group and checks it again before moving the selected extras. You can inspect every selection before confirming.

**Similar images** use a local visual difference hash and an aspect-ratio check. They may be resized exports, near-identical frames, or unrelated pictures that happen to resemble one another. Results are **review suggestions**, never automatically selected for removal. Rotated, cropped or very different edits may be missed.

“All groups” is useful for an overview; choose a group in the picker for focused side-by-side review.

## Before you move files

- **Save important files elsewhere first.** Keepelix is not a backup tool.
- **Close the owning app** before deleting its media. Removing WhatsApp or another application's files can leave missing attachments; future re-download is not guaranteed.
- **Downloaded cloud files may sync deletions.** Undownloaded placeholders are skipped, but that does not make downloaded cloud content disposable.
- **Trash is not free space yet.** Empty it yourself only after reviewing what you removed.
- **Undo is session-scoped.** After quitting, restore items through Finder Trash. Restores never overwrite an existing destination.

The app does not read chat databases or identify clients. It is an independent file tool, not affiliated with WhatsApp or Meta. Read the full [safety limits](docs/SAFETY.md).

## Build and test

No third-party dependencies. Requires Swift 5.9+ and macOS development tools.

```sh
git clone https://github.com/danielsimisi-coder/keepelix.git
cd keepelix
swift test
swift run Keepelix
```

Package a universal app:

```sh
./scripts/build-app.sh
```

Tests use disposable, generated fixtures. They exercise root boundaries, stale files, symlink replacement, duplicate selection, hard links, cancellation, partial Trash failures, restore conflicts and image similarity. CI also builds the release target and checks the tracked source for accidental private payloads.

## Project layout

```text
Sources/Keepelix/       Native AppKit interface and Quick Look
Sources/KeepelixCore/   Scanning, duplicate analysis, Trash and restore
Tests/                   Synthetic filesystem acceptance tests
scripts/                 Packaging and source privacy checks
docs/                    Privacy, safety, release and contributor guidance
```

## Status and contribution

This is a first beta. Code compilation and automated tests are not substitutes for testing on every macOS version. The Intel slice is cross-built; real Intel-machine verification and clean-Mac Gatekeeper verification are release checklist items, not implied claims.

Primary controls support English and Hebrew. Some status and system error text remains English. Contributions to accessibility, localisation and synthetic-fixture coverage are welcome. See [CONTRIBUTING](CONTRIBUTING.md), [SECURITY](SECURITY.md), and [CHANGELOG](CHANGELOG.md).

Released under the [MIT License](LICENSE). Built to help people decide what to keep.

## Author and contact

© 2026 **Daniel Siman Tov**. Contact: [daniel.simisi@gmail.com](mailto:daniel.simisi@gmail.com).

Keepelix is available under the [MIT License](LICENSE).

## Review older files

Choose a folder, then **Older files** in the sidebar. Filter files not modified in 6 months, 1 year, 2 years or 5 years. Sort by largest, smallest, oldest, newest or name; the Name, On disk and Last modified column headers also sort the list. Switching review views clears selection.

“Old” means last modified before the selected cutoff. It does not mean you have not opened the file, and it never means the file is safe to delete automatically. The view remains limited to your chosen folder. The **Trash** shortcut opens your user Trash folder in Finder.

The Trash confirmation offers **Do not show again**. Re-enable it from **Keepelix → Confirm before Trash**. Undo and Redo also have buttons; successful actions update the status without extra popups. History lasts only for the current session.

![Older files view with generated demo files](assets/keepelix-older-files.png)

Screenshots show the real app using generated, read-only demo files.

Undo/Redo history is separate for each chosen folder during the session. Switching folders cannot replay an action in the previous folder; return to that folder to access its history. If a restore is blocked, resolve the reported conflict and retry, or restore through Finder Trash. Earlier batches wait behind that unresolved batch.
