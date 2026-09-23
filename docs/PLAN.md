# 0.1.0 beta acceptance criteria

- A standalone, offline macOS 13+ app; user chooses the scan folder.
- No bundled user file inventory, personal paths, telemetry, secrets or cloud service.
- Background, cancellable metadata scan; skip symbolic links, packages, hidden folders and cloud placeholders.
- Size/type/name filters; standard Command/Shift multi-selection; Select All means the filtered list.
- Space previews locally; arrow navigation; context menu reveals the clicked item in Finder.
- Confirm the count and total before moving to Trash. No permanent deletion.
- Revalidate identity, modification time and root containment before every move. Report partial failures.
- Undo the last move batch without overwriting an existing destination. Failed restores remain retryable.
- SHA-256 exact-duplicate groups; select extras keeps one per group. Revalidate the keeper before moving extras.
- Opt-in perceptual image similarity groups are review suggestions only, with side-by-side preview.
- Remember folder and position locally; resuming is explicit.
- Real filesystem tests use synthetic fixtures only. macOS CI runs tests and release compilation.
- A reproducible universal app build; documented Developer ID/notarization path. Ad-hoc beta is clearly labelled.
- The repository and every release contain only the clean project, never the original workspace.

Independent review is required before public release. No user's real files are modified during validation.
