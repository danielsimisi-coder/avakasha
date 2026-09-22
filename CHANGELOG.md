# Changelog

## 0.1.0-beta.8

- ⌘C with the list focused, or right-click on the path, copies the highlighted file's path (and the file itself for pasting into Finder or a chat).
- A chat badge next to the highlighted file names its WhatsApp group or contact (identifier until Chat names is loaded); clicking it filters to that chat.

## 0.1.0-beta.7
- Stop a running scan, map or comparison: Refresh turns into a red Stop while work runs, Esc stops too, and the files found so far stay listed as partial results. Trash and restore operations still run to completion.
- The selected file's path and the map's folder path are links: underline on hover, click shows the item in Finder.

## 0.1.0-beta.6


- Chat filter lists every WhatsApp chat found in the scan, largest first, by identifier.
- **Stop auto-download…** opens WhatsApp and shows the path to its media auto-download setting (no public deep link exists).
- **Chat names…**: explicit, read-only read of WhatsApp's local chat list (identifier, display name, type only) to label groups and contacts in the filter and the storage map. Messages are never read; nothing is stored. Synthetic-database tests prove the file is left untouched.

## 0.1.0-beta.5

- Show the selected file's path (home folder as ~) next to the selection controls, and the folder path in the storage map details.
- Type badge for the selected file: image pixel size, video length, colour-coded icons in the list.
- Videos in mp4, m4v or mov play inline with an always-visible transport bar (play/pause, scrubber, time, mute); other formats keep Quick Look. Nothing autoplays.
- The counter reads "Item N of M · selected · size" so you always know where you are in the list.
- Empty state says "Scanning…" while a scan runs. Read-only demo includes a generated three-second clip.
- WhatsApp chat filter: group chats, personal chats, status and broadcasts, by per-chat folder names only (chat databases are never read; contact and group names are not shown). The storage map labels those folders too.
- Drag highlighted rows out to Finder, WhatsApp or any window as file copies.
- The preview pane is open by default. Space plays or pauses a video; for other files it still toggles the preview.
- Extending the selection with Shift+↓, Shift+↑ or ⌘-click previews the row you just reached; the path, badge and counter follow it.

## 0.1.0-beta.4

- English is the default interface language on every Mac. Keepelix › Language offers Hebrew, which applies on the next launch with full right-to-left layout; the choice is stored for this app only.
- The sidebar highlights the location currently loaded, and clicking it again shows it without rescanning (Refresh rescans).
- The package declares English and Hebrew localizations so system panels follow the chosen language.
- The repository documentation is English only.

## 0.1.0-beta.3

- Add a storage map: measure any folder or drive, list folders largest first with share bars, open folders, and hand a folder to file review with one click. Read-only; Delete does nothing in the map.
- Report what the map could not measure instead of guessing: not accessible, hidden, bundle, not downloaded and other-volume entries are labelled and counted; hard links count once; symbolic links are not followed; cancellation keeps consistent partial totals.
- Blocked restores no longer block earlier batches. Items whose original path is taken stay in Trash under Retry restore; Undo continues to older batches; quitting with items waiting asks first.
- Independent review fixes: skipped folders deeper than one level no longer corrupt the map hierarchy; Select All cannot reach the hidden file list from the map; a waiting restore whose Trash item vanished is reported once instead of waiting forever.
- Localise remaining status and error messages in Hebrew, add accessibility labels to filters and tables, and show scanning/measuring empty states.
- Fix the workspace not filling the window height.
- Package as 0.1.0 beta 3; the build script checks that a signing identity exists and warns when it is not a Developer ID identity.

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
