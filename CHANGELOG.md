# Changelog

## 0.1.0-beta.2

- Add Delete-to-Trash, optional confirmation suppression, and session Undo/Redo with keyboard shortcuts and buttons.
- Simplify the interface and confirmation dialogs.
- Rename the project to Keepelix.
- Redesign the interface with a sidebar, native icons, clearer empty states and dedicated review actions.
- Add a Finder Trash shortcut, old-file filters and size/date/name sorting.
- Add a read-only synthetic demo for documentation screenshots.

- Fix a startup crash in the packaged app by using the standard preferences domain.
- Verify production preferences and interface initialization from the signed app bundle during packaging.


## 0.1.0-beta.1

First standalone release of Keepelix, replacing the personal review prototype.

- User-selected folders; asynchronous scan with progress and cancellation.
- Keyboard preview, next-file navigation and contextual Reveal in Finder.
- Command/Shift multi-selection, filtered Select All, totals and batch confirmation.
- OS Trash with per-file failure reporting and session-scoped Undo.
- Exact SHA-256 duplicates and keep-one extra-copy selection.
- Opt-in local similar-image groups with paired Quick Look previews.
- Local resume position; English and Hebrew primary controls.
- Synthetic filesystem tests, private-data source audit and macOS CI.

Beta limitations: ad-hoc builds are not Apple-notarized, some secondary status/error messages remain English, and broader real-device/OS testing is still required.
