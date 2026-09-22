# Review before removing

Keepelix moves selected regular files to the operating system's Trash. It never empties Trash and does not provide permanent deletion.

## What the app checks

Every move is checked against the original selected root, current canonical path, filesystem device/inode, byte length and nanosecond modification time. Symbolic links and paths redirected through symbolic-link parents are rejected. File size and modification time are rechecked after duplicate hashing. Hard links are excluded as extra copies.

Selecting extra exact duplicates leaves one deterministic original per group. Its presence and identity are checked again before each automatically selected extra is moved. File selection is always reviewable and a confirmation states the file count and combined on-disk size by default. You can disable it with “Do not show again” and restore it from the app menu.

## Undo and Redo

Undo restores batches in reverse order; Redo repeats restored moves only after checking the original identities and duplicate keepers again. A new Trash action clears Redo history but keeps waiting restores. Undo restores the last batch during the current app session. It does not overwrite existing files. Items that cannot be restored, because another file now occupies the original path or the Trash item changed, stay in Trash on a waiting list shown as **Retry restore**; they do not block Undo of earlier batches and are retried with the same no-overwrite checks. An item that is no longer in Trash at all (restored in Finder, or Trash emptied) is reported once and removed from the waiting list, because the app can no longer restore it. Quitting with items waiting asks for confirmation. After closing the app, use Finder Trash; application undo tickets are not persisted. Do not empty Trash until you are satisfied with the selection.

## Limits

- These checks protect against ordinary stale scans. They are not an atomic filesystem transaction and do not defend against malicious concurrent filesystem changes. Do not run it on folders actively rewritten by other apps.
- Close the owning app before removing its media. Deleting WhatsApp or other app-managed media can leave missing attachments. No claim is made about synchronisation or future re-download availability.
- Removing a downloaded file in a cloud-synced folder may also remove its cloud copy. The app skips undownloaded placeholders, but local downloaded cloud files still require care.
- On-disk block totals are estimates, not promised savings: APFS clones, hard links, snapshots and Trash affect actual free space.
- Image similarity uses a local difference hash with an aspect-ratio check. False positives and false negatives are expected. It does not understand which photo is important, higher quality or edited intentionally. It never auto-selects similar images.
- Protected/unreadable files, hidden files, app packages, symlinks, databases and thumbnails are skipped. Some media formats lack a system Quick Look preview.
- Avoid selecting the entire home folder. Choose a narrow folder of documents or media you recognise.

This beta is a review tool, not a backup system or an automatic cleaner.

Automatic extra selection compares extended attributes (including resource forks) and permissions; files with ACL entries or unreadable/large attributes require manual review. Groups describe matching data-fork bytes; they do not imply identical history or ownership. The keeper and extra are hashed again immediately before moving, and checked afterward. Concurrent-change detection attempts a no-overwrite rollback and reports any file still in Trash. These checks reduce ordinary races but do not make pathname-based macOS Trash operations atomic.

Image comparison skips files over 100 MB or 100 megapixels. Cancel is checked between images; an individual ImageIO decode is not interruptible. After cancellation is requested, quitting is allowed for read-only work. Trash and Undo must finish before quitting.

Undo/Redo history is separate for each chosen folder during the session. Switching folders cannot replay an action in the previous folder; return to that folder to access its history and its waiting restores.

## Storage map

The map reads names, sizes and filesystem flags only; it never reads file contents and never moves files. It does not follow symbolic links, does not enter other volumes mounted below the chosen folder, does not descend into cloud placeholders that are not downloaded, and measures bundles without listing their contents. Hard-linked data is counted once. Folders that cannot be read are listed as not accessible and excluded from totals rather than estimated. Cancelling keeps partial totals and says so. Sizes are allocated blocks, not a promise of reclaimable space: APFS clones, snapshots, sparse files, hard links and Trash all change what emptying would free. Hidden folders are shown because they often hold the space; app and system data inside them deserve extra care before review.
