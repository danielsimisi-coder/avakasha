# Contributing

Small changes with a clear user benefit are welcome. Keep the app local, keyboard-friendly and conservative about file operations.

1. Use macOS 13+ with Xcode command-line tools and Swift 5.9+.
2. Run `swift test` and `swift build -c release`.
3. Add synthetic-fixture tests for changes to selection, scanning, grouping, Trash or restore behavior.
4. Run `python3 scripts/audit-source.py` after staging your intended files.
5. Open a focused pull request describing behavior and validation.

Never commit real user files, personal paths, exported inventories, credentials or screenshots of private media. A successful build alone is not evidence that a destructive workflow is correct. New deletion behavior must have failure-path tests and an independent review.

No automatic permanent deletion, forced permission bypasses, cloud content analysis or telemetry will be accepted.
