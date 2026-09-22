# Private beta security review

## Scope

Application source, packaging, CI, every reachable Git blob and the built universal ZIP. No personal media, chat databases, client documents or existing Trash contents were inspected. Author name, requested contact email, GitHub project URLs and the matching bundle identifier are intentional public project metadata.

## Findings and checks

- Two independent Codex passes inspected deletion, duplicate selection, path containment, restore and privacy. Their actionable findings led to identity checks after Trash, safe rollback, keeper re-hashing, metadata comparison, complete confirmation paths and clearing selection on mode changes. The last mode-transition finding was fixed and verified by a reproducing hidden UI regression. No third independent pass is claimed.
- 21 local tests passed, including a real macOS Trash/Undo round-trip involving one generated disposable file. Hidden AppKit checks also cover location buttons, busy-state disabling, selection, mode transitions, preview and context menus.
- No application networking, process execution, shell invocation, dynamic code loading, third-party packages or bundled personal inventory was found in source inspection. Preview delegates to macOS Quick Look and installed extensions.
- Source audit covers tracked files and all reachable historical blobs, rejects unexpected binaries/symlinks, matches synthetic artwork by hash, and detects common credential/home-path patterns. Disposable tests prove it rejects an empty index and credentials retained in history. This is not a universal secret detector.
- Release audit permits only the expected app binary, plist, signature, matching license and synthetic icon. Packaging omits extended filesystem attributes and local home paths were not found in the ZIP payload.
- CI has read-only repository permission, a pinned checkout commit, no persisted checkout credentials, full history for auditing and a bounded timeout.

## Remaining boundaries

This is a private beta, not a certification of zero vulnerabilities. Path-based Trash/Undo cannot eliminate all hostile concurrent filesystem races; important data still needs backups. Quick Look and image decoders are OS components. Cloud-folder deletions may sync; removing app media may break references. Undo is session-local. UserDefaults stores chosen paths locally. Similarity is a suggestion and never automatically selects files for deletion.

Developer ID signing, Apple notarization, clean-Mac Gatekeeper testing, Intel runtime testing and broader permission/filesystem/accessibility acceptance remain necessary before a supported public release. External GLM review was not used; a full Coverloop external-review pass is not claimed.

## Beta 3 focused review

An independent adversarial pass (separate Claude context, read-only on the repository, synthetic fixtures only, no external providers) reviewed the storage map walker, the blocked-restore history and the map-mode isolation in the interface. Findings and disposition:

- **Fixed, high:** `fts` returns a skipped directory once more as a post-order visit, so a mount point or undownloaded cloud folder at depth two or deeper popped its parent early and misattributed everything after it. A synthetic depth-two skip test now covers the walker; nested unreadable folders are also tested.
- **Fixed, medium:** Select All reached the hidden file table while the map was shown. Selection actions are now guarded by map mode and selection state is refreshed on the way back.
- **Fixed, medium:** a waiting restore whose Trash item disappeared (restored in Finder, Trash emptied) stayed waiting forever and inflated the waiting count. Such items are now reported once and dropped; changed Trash items are still kept and refused.
- **Confirmed safe:** no overwrite on Undo or Retry in either order of conflicting paths, changed Trash items refused, tickets never dropped silently, earlier batches undoable behind a blocked one, Redo never adopts replacements, keepers enforced through blocked → retry → redo, histories per root, map mode cannot reach a Trash move, review from the map goes through the same root validation, symbolic links never followed, no file contents read (verified with a FIFO), no crash path in the `fts` bindings.
- **Open, low:** a Redo entry for a file that no longer matches stays lit until a new move (pre-existing); waiting restores in another folder's history are only visible after returning to that folder; memory use of the map is roughly a few hundred bytes per folder.

No release-blocking issue for a private beta was found after the fixes. No third pass is claimed.

## Beta 2 focused follow-up

Independent review of the new history and keyboard integration found no overwrite, replacement-adoption, containment or keeper bypass. A cross-folder history UX issue was fixed by keeping separate histories for each chosen root, covered by hidden UI regression. A failed latest restore continues to block older batches until resolved; Finder Trash recovery remains available. This is a documented beta limitation. Local validation now includes 28 passing core/integration tests and the expanded keyboard smoke.
