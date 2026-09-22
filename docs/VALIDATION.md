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

The primary preview follows the first selected row in display order. A multi-selection's last-clicked row is not separately tracked. This is a known interaction limitation; the confirmation lists every target independently of preview order.
