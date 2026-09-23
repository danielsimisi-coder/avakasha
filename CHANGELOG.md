# Changelog

## 0.1.0-beta.11

- Free up space measures as soon as it opens (names and sizes only; Esc stops) and shows a summary: how much can go to Trash now, how much needs the owning app, how much is Terminal-only, how much to review.
- Select several rebuildable rows, or "Select all that can go", and move them in one step; one ⌘Z brings them all back.
- Every other row gets one action: open the owning app (Mail, Docker, OrbStack, Chrome, Safari, Messages, Premiere, Xcode, Finder for iPhone backups), review its files in Avakasha, open Trash, or copy the command and open Terminal. Commands are copied, never run.
- Items under 100 MB are tucked away behind "Show small items".
- Cache folders whose names make macOS treat them as bundles are no longer offered, since bundles are never moved whole.
- The read-only demo can never read outside its generated folder: scans, maps and Free up space are refused elsewhere.
- The workspace always fills the window height.

## 0.1.0-beta.10

- Fix a small unfilled spot in the app icon's sun.
- Public open-source release on GitHub.
- The sidebar shows the app's real icon next to the name, the same image Finder and the Dock draw.
- Interface pass from a panel of UX, accessibility and localisation reviews: sidebar in three sections (Start, Locations, Tools), window subtitle names the current place, one "moved to Trash · Undo" line after every move, File and View menus with a key for every command, a five-step type scale, caveats behind info buttons, grey data bars with colour reserved for interaction, Return cancels every Trash confirmation, sidebar exposed to VoiceOver as a radio group, focus follows scans, gender-neutral Hebrew and one glossary in both languages.
- Overview reads "Make room on your Mac" with drive cards and three start buttons.
- The read-only demo never reaches real folders; screenshots regenerated from it.

## 0.1.0-beta.9

- The storage map shows a Rescan button and says its numbers are out of date after files are moved to Trash or restored.
- The Resume button is gone; the empty screen offers "Continue: ~/folder" for the last folder instead.
- Largest files: a button in the storage map hands the largest files under the mapped folder (up to 200, same exclusions as file review) to file review, largest first, with the mapped folder as the root; Refresh there measures the map again. The map's details pane names up to five files inside the highlighted folder that are among the mapped folder's 200 largest, and Return on the "Files in this folder" row reviews that folder.
- Installers & archives: a sidebar button and review mode listing disk images, installer packages and archives not modified within the chosen cutoff, by file extension only; the type badge names the family. Nothing is auto-selected.
- Reviewed and kept: K, the check in the star column or Keep & next marks files you decided to keep (stored in this app's preferences by path with the file's size and modification time, so a rewritten file reappears). The star filter adds "Not yet reviewed" and "Reviewed only"; a move to Trash forgets the mark. A star still shows ahead of the check.
- Session space summary in the bottom row: allocated bytes moved to Trash this session (less what Undo restored) next to the free space macOS reports for the volume, side by side, not as a prediction.
- Overview at launch: used, total and free space for each local disk with a share bar, what this session moved to Trash, and buttons to map the home folder, map a folder or drive, or open Trash in Finder. Reads volume attributes only.
- Whole-folder moves from the storage map: Delete or the red "Move folder to Trash…" button moves the selected subfolder to Trash as one item after a check (inside the mapped root, not the root, a link, a bundle, hidden or a cloud placeholder), a fresh measurement, a refusal when anything in it could not be measured, and a confirmation that is always shown. The folder is moved only if it is still the folder that was measured (device and inode). Undo with ⌘Z while the map is shown; blocked restores wait under Retry restore; Redo is not available for folders.
- Free up space: a sidebar screen listing known caches and app data from a built-in catalogue (Xcode, OrbStack, Docker, package managers, AI caches, browsers, messaging, Mail, backups, logs, per-app Library/Caches folders) with what each is, what happens next time and a verdict. Sizes are measured only when you press Measure all. Move to Trash… is offered only for rebuildable data and uses the same guarded folder flow with the home folder as the root; commands for developer tools are copied to the clipboard, never run; Mail, Chrome profiles, Messages and backups are explained, never moved.
- The sidebar highlights the view you are in (Overview, Storage map, Free up space, Older files, Installers) as well as the loaded location.
- Chat names and the chat filter are reset when Largest files switches the review to the map root, so names loaded for another WhatsApp folder are not shown there.

## 0.1.0-beta.8

- Star important files with S or the star column. A filter shows starred files only or hides them. Stars are kept in this app's local preferences by path; files are not modified. Starred files are never auto-selected as extra copies, and the Trash confirmation warns when starred files are included.
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

- English is the default interface language on every Mac. Avakasha › Language offers Hebrew, which applies on the next launch with full right-to-left layout; the choice is stored for this app only.
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
- Rename the project to Avakasha.
- Redesign the interface with a sidebar, native icons, clearer empty states and dedicated review actions.
- Add a Finder Trash shortcut, old-file filters and size/date/name sorting.
- Add a read-only synthetic demo for documentation screenshots.

- Fix a startup crash in the packaged app by using the standard preferences domain.
- Verify production preferences and interface initialization from the signed app bundle during packaging.


## 0.1.0-beta.1

First standalone release of Avakasha, replacing the personal review prototype.

- User-selected folders; asynchronous scan with progress and cancellation.
- Keyboard preview, next-file navigation and contextual Reveal in Finder.
- Command/Shift multi-selection, filtered Select All, totals and batch confirmation.
- OS Trash with per-file failure reporting and session-scoped Undo.
- Exact SHA-256 duplicates and keep-one extra-copy selection.
- Opt-in local similar-image groups with paired Quick Look previews.
- Local resume position; English and Hebrew primary controls.
- Synthetic filesystem tests, private-data source audit and macOS CI.

Beta limitations: ad-hoc builds are not Apple-notarized, some secondary status/error messages remain English, and broader real-device/OS testing is still required.
