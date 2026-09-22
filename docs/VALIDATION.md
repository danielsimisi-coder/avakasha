# Beta validation and boundaries

All fixtures are generated temporary files. No personal media, WhatsApp databases or user Trash items are used in development checks.

- Core tests cover scanning exclusions, root containment, changed files, partial moves, no-overwrite Undo, duplicate keeper protection, metadata differences, a concurrent replacement rollback, and synthetic image similarity.
- Hidden AppKit smoke mode exercises multi-selection, filtered Select All, selection clearing, duplicate extras, the context menu, Quick Look and navigation without showing windows.
- Independent Codex review found selection and concurrent-change issues; fixes and regression tests followed. External GLM review was not used. This is not a claim that the full external-review workflow passed.
- GitHub CI runs tests, hidden smoke, release compilation and the tracked-source audit.

The initial release is a private, ad-hoc-signed beta. Developer ID signing, notarization, Gatekeeper acceptance on a clean Mac, Intel runtime testing and broad accessibility testing remain release gates for a public supported distribution. The optional real macOS Trash/Undo integration test passed locally using one generated disposable file. Wider filesystem and permission combinations still need dedicated acceptance.

Local evidence for the first beta: 20 core cases and the hidden UI smoke passed; an additional opt-in macOS Trash round-trip passed. Enable it with `FILETRIAGE_SYSTEM_TRASH_TEST=1 swift test`. Default CI skips that OS-integration case.

## Beta 9 checks

92 test functions in `Tests/AvakashaCoreTests` (44 in `CoreTests.swift`, 9 in `LargestFilesTests.swift`, 7 in `InstallersTests.swift`, 8 in `ReviewedStoreTests.swift`, 7 in `SessionSpaceTests.swift`, 9 in `FolderTrashTests.swift`, 4 in `KnownLocationsTests.swift`, 4 in `VolumesTests.swift`), all on generated fixtures.

Whole folders (`FolderTrashTests.swift`): move and restore round trip; the root itself and folders outside it refused; symlinked, package and hidden folders refused; a folder changed or replaced between the check and the move is not moved; restore never overwrites and can be retried once the path is free; restore refuses a different Trash item or a linked parent; the history records folder moves with Undo but no Redo; a blocked folder restore waits for retry. Known locations (`KnownLocationsTests.swift`): the catalogue is well formed (unique ids, relative paths, a command only on command-only entries, and no command is a raw `rm -rf`; the copied commands themselves delete immediately through the owning tool, without Trash or Undo); `present` lists only existing real directories in a synthetic home and skips a symbolic link; per-app cache folders are listed but curated and hidden ones are not; `measure` reports allocated bytes and errors. Volumes (`VolumesTests.swift`): the temporary directory's volume has capacity, a missing path has no volume, the mounted list puts the startup disk first, fractions are clamped. No test lists or measures the real home folder.

The earlier beta 9 cases cover: the map's largest-file list sorted by size then path and capped by the limit, ties at the cutoff resolved by path whatever the walk order, files in subfolders reported with full URLs, hidden files and folders, package contents and database extensions excluded, hard-linked data listed once, a cancelled walk returning the partial list, limit zero still mapping; installer classification by extension (disk images, packages, archives, case-insensitive, unknown extensions nil), the cutoff boundary and input order; the reviewed store marking, unmarking, toggling, ignoring malformed stored values, rejecting a rewritten file whose size or modification time differs, forgetting by path and saving the full dictionary on every change; session bytes equal to the sum of allocated bytes, back to zero on Undo and up again on Redo, kept while a restore is blocked, not confused by a new move at the same path, counting only moved files on partial failures, and `DiskSpace.available` answering for a temporary directory and nil for a missing path.

The hidden UI smoke opens on the overview with real volume capacities (startup disk first) and checks that only the map entry is highlighted while the map is shown, never a location, and that Storage map from the overview returns to the last map without re-measuring. On a synthetic tree it moves a subfolder to Trash from the map through the guarded flow (folder gone, row detached, map totals reduced and marked out of date), checks that Undo is offered and Redo is not, undoes and finds the folder back, and checks that a hidden folder cannot be moved whole. On a synthetic home it lists the known locations that exist (DerivedData, Mail, a per-app cache folder, Library/Caches), measures them on request, checks that Mail is never offered for Trash while DerivedData is, moves DerivedData through the same flow with the home folder as the root, and restores it through Undo (the free-up screen routes ⌘Z to the home folder's history). The synthetic home is removed afterwards.

The hidden UI smoke additionally opens Largest files from the map (file review on the map root, largest first, folder label suffix, first row selected, session summary visible, the map location not treated as already loaded), checks Refresh re-measuring the map and rebuilding the view, Return on the loose-files row reviewing that folder, the Installers mode with the age cutoff and family badge and the sidebar button leaving map mode, K marking and persisting a file, the green check with a star shown ahead of it, the Not yet reviewed and Reviewed only filters, Keep & next marking the file it leaves and stepping to the next unreviewed one, the check click and K clearing the mark, Trash forgetting the mark, and the session summary after Trash and after Undo. All fixtures are temporary and removed afterwards.

## Review disposition

The first independent pass led to these changes: filtering clears a vanished selection; confirmations list all paths; Trash checks the moved identity and attempts safe rollback; duplicate actions re-hash both files, protect a selected keeper and compare extended attributes/permissions; similar groups retain their comparison anchor; oversized image inputs are skipped and cancelled read-only work can quit; the audit rejects an empty index; Quick Look's OS boundary is stated explicitly.

The primary preview, path, badge and counter follow the row most recently added to the selection (Shift+arrow or ⌘-click); shrinking the selection steps back to the last remaining row. The confirmation lists every target independently of preview order.

The final independent pass identified a mode-transition keeper-guard bug. Changing view mode now clears selection before clearing guards; the hidden UI regression exercises the exact transition. No additional independent pass was claimed after that fix. All 21 core/integration tests and the updated hidden UI regression passed locally.

Beta 2 fixes a packaged-only startup crash: production now uses `UserDefaults.standard`, and packaging executes `--launch-check` inside the signed bundle using the production preferences path. This initializes the interface without opening a window or scanning files. CI now builds the universal package and runs this check plus the release payload audit.

## Beta 6 checks

44 core cases: the chat-list reader is exercised on a synthetic SQLite database (names resolved, unknown identifiers ignored, unexpected schema and missing file rejected, database bytes unchanged and no write-ahead files created). The hidden UI smoke builds a synthetic chat list, loads it, and filters by a named chat.

## Beta 5 checks

42 core cases, including chat-folder classification by folder name only. The hidden UI smoke now also checks the path label and type badge for the selection, the "Item N of M" counter, that a generated `.mov` opens in the inline player paused, play/pause and mute toggles and Space driving them, that closing the preview releases the player, Shift+arrow focus tracking, drag-out pasteboard writers for valid rows only, and the chat filter appearing only when chat folders exist. Visual check on the read-only demo with a generated clip.

## Beta 4 checks

Same 41 core cases. The hidden UI smoke now also verifies the Language menu (English default, Hebrew choice writes the app-only language, `AppleLanguages` and layout-direction defaults, strings switch only on the next launch) and that clicking the loaded location again does not rescan. The Hebrew right-to-left layout was checked visually on the read-only demo and captured for the README. Packaged launch check and release audit passed with the declared localizations.

## Beta 3 checks

41 core/integration cases pass locally (one opt-in system Trash case skipped by default). New synthetic fixtures cover the storage map: folder aggregation and direct-file subtotals, hard links counted once, symbolic links not followed, bundles measured without children, unreadable and hidden folders, consistent partial totals after cancellation, rejection of missing, file or unreadable roots, a skipped other-volume folder at depth two and a nested unreadable folder keeping the hierarchy intact. New history tests cover a blocked restore that no longer hides earlier batches, a retry that succeeds only after the conflict is resolved, blocked items surviving a new move, a changed Trash item that stays blocked with its Trash item kept, and a vanished Trash item that is reported once instead of waiting forever. The hidden UI smoke additionally measures a synthetic tree, drills, goes up, verifies Delete does nothing in the map, checks that Select All does not reach the hidden file list, hands a folder to file review, returns to the map without re-measuring, and exercises Delete → blocked Undo → Undo of the earlier batch → Retry restore with an isolated fixture Trash backend. Screenshots were regenerated from the read-only demo. The packaged universal build passed `--launch-check` and the release audit.

## Beta 2 current checks

All 28 core/integration cases passed locally, including the opt-in system Trash round-trip on an owned generated file. Hidden UI smoke passed Delete → Undo → Redo → Undo, held-key protection, confirmation preference, selection and old-file sorting using an isolated fixture Trash backend. New history tests cover replacement files, missing duplicate keepers and partial restores. Documentation screenshots use read-only generated media.
