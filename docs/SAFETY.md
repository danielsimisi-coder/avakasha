# Review before removing

Avakasha moves selected regular files to the operating system's Trash. It never empties Trash and does not provide permanent deletion.

## What the app checks

Every move is checked against the original selected root, current canonical path, filesystem device/inode, byte length and nanosecond modification time. Symbolic links and paths redirected through symbolic-link parents are rejected. File size and modification time are rechecked after duplicate hashing. Hard links are excluded as extra copies.

Starred files are never auto-selected as extra copies, and the confirmation warns when starred files are part of a selection; a star is a local marker in this app, not a lock. Reviewed-and-kept marks are the same kind of local marker: they hide or show files in the list and never prevent a selected file from being moved to Trash; a move forgets the mark. Selecting extra exact duplicates leaves one deterministic original per group. Its presence and identity are checked again before each automatically selected extra is moved. File selection is always reviewable and a confirmation states the file count and combined on-disk size by default. You can disable it with “Do not show again” and restore it from the app menu.

## Undo and Redo

Undo restores batches in reverse order; Redo repeats restored moves only after checking the original identities and duplicate keepers again. A new Trash action clears Redo history but keeps waiting restores. Undo restores the last batch during the current app session. It does not overwrite existing files. Items that cannot be restored, because another file now occupies the original path or the Trash item changed, stay in Trash on a waiting list shown as **Retry restore**; they do not block Undo of earlier batches and are retried with the same no-overwrite checks. An item that is no longer in Trash at all (restored in Finder, or Trash emptied) is reported once and removed from the waiting list, because the app can no longer restore it. Quitting with items waiting asks for confirmation. After closing the app, use Finder Trash; application undo tickets are not persisted. Do not empty Trash until you are satisfied with the selection.

## Limits

- These checks protect against ordinary stale scans. They are not an atomic filesystem transaction and do not defend against malicious concurrent filesystem changes. Do not run it on folders actively rewritten by other apps.
- Close the owning app before removing its media. Deleting WhatsApp or other app-managed media can leave missing attachments. No claim is made about synchronisation or future re-download availability.
- Removing a downloaded file in a cloud-synced folder may also remove its cloud copy. The app skips undownloaded placeholders, but local downloaded cloud files still require care.
- On-disk block totals are estimates, not promised savings: APFS clones, hard links, snapshots and Trash affect actual free space. The session summary counts the allocated blocks of files moved to Trash this session (less what Undo restored); that is what was moved, not what was freed, because Trash keeps those blocks until emptied. The free-space figure next to it is what macOS reports for the volume of the current location, including purgeable space.
- Installers & archives is a filter by file extension and age only. It never auto-selects anything, because the app cannot tell whether an installer was used or an archive was extracted.
- Image similarity uses a local difference hash with an aspect-ratio check. False positives and false negatives are expected. It does not understand which photo is important, higher quality or edited intentionally. It never auto-selects similar images.
- Protected/unreadable files, hidden files, app packages, symlinks, databases and thumbnails are skipped. Some media formats lack a system Quick Look preview.
- Avoid selecting the entire home folder. Choose a narrow folder of documents or media you recognise.

This beta is a review tool, not a backup system or an automatic cleaner.

Automatic extra selection compares extended attributes (including resource forks) and permissions; files with ACL entries or unreadable/large attributes require manual review. Groups describe matching data-fork bytes; they do not imply identical history or ownership. The keeper and extra are hashed again immediately before moving, and checked afterward. Concurrent-change detection attempts a no-overwrite rollback and reports any file still in Trash. These checks reduce ordinary races but do not make pathname-based macOS Trash operations atomic.

Image comparison skips files over 100 MB or 100 megapixels. Cancel is checked between images; an individual ImageIO decode is not interruptible. After cancellation is requested, quitting is allowed for read-only work. Trash and Undo must finish before quitting.

Undo/Redo history is separate for each chosen folder during the session. Switching folders cannot replay an action in the previous folder; return to that folder to access its history and its waiting restores.

## Storage map

The map reads names, sizes and filesystem flags only; it never reads file contents. The only action it can take is the checked whole-folder move described under Whole folders below; the measurement itself moves nothing. It does not follow symbolic links, does not enter other volumes mounted below the chosen folder, does not descend into cloud placeholders that are not downloaded, and measures bundles without listing their contents. Hard-linked data is counted once. Folders that cannot be read are listed as not accessible and excluded from totals rather than estimated. Cancelling keeps partial totals and says so. Sizes are allocated blocks, not a promise of reclaimable space: APFS clones, snapshots, sparse files, hard links and Trash all change what emptying would free. Hidden folders are shown because they often hold the space; app and system data inside them deserve extra care before review.

The Largest files view uses the mapped folder as its safety root: each file from the map is validated against that root before it is listed, and every move from that list is checked against the same root, identity and path rules as any other review. The list follows the file-review exclusions (no bundle contents, hidden files, cloud placeholders or app databases) and is at most 200 files, partial if the measurement was cancelled.

## Whole folders

Moving a whole folder to Trash is the most far-reaching action in the app, so it is gated harder than file moves. It is reached from two places only: the storage map (Delete or Move folder to Trash…) and Free up space (Move to Trash…, rebuildable rows only). Both go through one flow:

- **Check.** The folder must sit strictly inside the safety root (the mapped folder, or the home folder for Free up space) and must not be the root itself, a symbolic link or a path through one, a package, a hidden folder or a cloud placeholder. The map additionally never offers the root, bundles, hidden or unreadable folders, or folders with unmeasured items. The folder's identity (device and inode) is recorded at this point.
- **Fresh measurement.** The folder is measured again right then, not from the map on screen. If the fresh walk finds anything it could not count (not accessible, not downloaded, or on another volume), the move is refused and the app suggests reviewing the files instead. Stopping the measurement moves nothing.
- **Confirmation, always.** The dialog shows the fresh size, file and folder counts and the path. It is shown every time; the "Do not show again" preference for file moves does not apply to folders.
- **Move with identity check.** Immediately before moving, the folder is checked again and must still be the folder that was measured; otherwise nothing moves. After the move the Trash item must keep the same identity; if it does not, the app tries to put the folder back and reports what happened.
- **Undo, no Redo.** The folder is recorded as one undo item in the history of its root. Undo restores it only when nothing occupies the original path, the original parent is not a link and the Trash item is still the same folder; a blocked restore waits under Retry restore and does not block earlier batches. Redo is never offered for folders, because redoing would have to trust a path rather than an identity. A folder that is no longer in Trash is reported once and dropped from the waiting list.

Refused outright: the mapped root, folders outside the root, links, packages and bundles, hidden folders, cloud placeholders, unreadable folders, folders with caveats in the fresh measurement, and any folder whose identity changed between the measurement and the move.

## Free up space

The verdict on each row (rebuildable, clean from the app itself, command in Terminal, cleared on restart, review before touching) is a judgement encoded in a catalogue in the source, based on what the owning tools are known to recreate. It is not a guarantee: a cache can hold something you wanted, and a tool can change what it keeps. Only rebuildable rows can be moved, through the whole-folder flow above with the home folder as the root. Mail, Chrome profiles, Messages attachments, iPhone backups, Docker and OrbStack data are explained and pointed to their own cleanup; the app never moves them. Commands are copied to the clipboard and never executed by the app. Those commands delete through the tool itself: nothing goes to Trash and the app cannot undo them, so read a command before running it. Sizes are measured only on request. Close the owning app before moving its cache. The user decides.
