# Beta validation and boundaries

All fixtures are generated temporary files. No personal media, WhatsApp databases or user Trash items are used in development checks.

- Core tests cover scanning exclusions, root containment, changed files, partial moves, no-overwrite Undo, duplicate keeper protection, metadata differences, a concurrent replacement rollback, and synthetic image similarity.
- Hidden AppKit smoke mode exercises multi-selection, filtered Select All, selection clearing, duplicate extras, the context menu, Quick Look and navigation without showing windows.
- Independent Codex review found selection and concurrent-change issues; fixes and regression tests followed. External GLM review was not used. This is not a claim that the full external-review workflow passed.
- GitHub CI runs tests, hidden smoke, release compilation and the tracked-source audit.

The initial release is a private, ad-hoc-signed beta. Developer ID signing, notarization, Gatekeeper acceptance on a clean Mac, Intel runtime testing and broad accessibility testing remain release gates for a public supported distribution. The optional real macOS Trash/Undo integration test passed locally using one generated disposable file. Wider filesystem and permission combinations still need dedicated acceptance.

Local evidence: 20 core cases and the hidden UI smoke passed; an additional opt-in macOS Trash round-trip passed. Enable it with `FILETRIAGE_SYSTEM_TRASH_TEST=1 swift test`. Default CI skips that OS-integration case.

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
