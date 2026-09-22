# Privacy

Keepelix has no networking client, analytics, account system, advertising SDK or automatic updater. It never uploads files or directory listings. Quick Look previews are provided by macOS and the preview extensions installed on your Mac.

- **Inventory:** reads file names, locations, sizes, types and filesystem identity inside the chosen folder. No folder is scanned before you choose one or click Continue for your last folder.
- **Chat filter:** classifies WhatsApp media by the chat identifier in its folder name without opening any database.
- **Chat names (opt-in):** only when you press Chat names… and confirm, Keepelix opens WhatsApp's local chat list (`ChatStorage.sqlite`) read-only and reads one table: chat identifier, display name and type. Messages, contacts and media references are not read; the names stay in memory for the session and are not written anywhere.
- **Drag out:** dragging rows hands the file location to the receiving app as a copy; nothing is moved or deleted by a drag.
- **Storage map:** reads folder and file names, allocated sizes and filesystem flags below the folder or drive you choose. It never reads file contents, never follows symbolic links and never enters other volumes. Nothing is stored after the session.
- **Exact duplicates:** reads file bytes locally to calculate SHA-256. It does not read app databases or chat history.
- **Similar images:** explicitly opt-in. Decodes images locally into tiny comparison thumbnails. Similarity is not a deletion recommendation.
- **Preview:** reads only the selected file and, in duplicate views, a comparison file from the same group. Video playback and the type badge use the system media frameworks locally; images are read for pixel size only, and nothing autoplays.
- **Local settings:** the last chosen folder and selected file path are stored in this Mac's UserDefaults. A manually located WhatsApp media folder is also remembered locally. Starred file paths, the confirmation preference and the interface language choice (which also sets this app's own language and layout-direction defaults) are stored locally. Reviewed-and-kept marks are stored locally in this app's preferences as well, keyed by file path together with the file's size and modification time; the files themselves are not written to. The file inventory and undo/redo tickets stay in memory and are discarded on exit.
- **Free space:** the session summary reads only the volume's available capacity (macOS's important-usage figure, which counts purgeable space, falling back to the plain available capacity), the available capacity of the volume that holds the current location. Nothing else about the volume is read or stored.
- **Permissions:** uses normal macOS file permissions. Protected folders may be skipped. Keepelix does not bypass OS restrictions or automatically request Full Disk Access.

Keep private names, file paths and screenshots out of public bug reports. Reports should use synthetic examples. There is no bundled file inventory in this repository or its release.
