# Beta validation and boundaries

All fixtures are generated temporary files. No personal media, WhatsApp databases or user Trash items are used in development checks.

- Core tests cover scanning exclusions, root containment, changed files, partial moves, no-overwrite Undo, duplicate keeper protection, metadata differences, a concurrent replacement rollback, and synthetic image similarity.
- Hidden AppKit smoke mode exercises multi-selection, filtered Select All, selection clearing, duplicate extras, the context menu, Quick Look and navigation without showing windows.
- Independent Codex review found selection and concurrent-change issues; fixes and regression tests followed. External GLM review was not used. This is not a claim that the full external-review workflow passed.
- GitHub CI runs tests, hidden smoke, release compilation and the tracked-source audit.

The initial release is a private, ad-hoc-signed beta. Developer ID signing, notarization, Gatekeeper acceptance on a clean Mac, Intel runtime testing and broad accessibility testing remain release gates for a public supported distribution. Unit tests use an injectable Trash backend; real Finder Trash integration still needs dedicated acceptance on a disposable user account.
