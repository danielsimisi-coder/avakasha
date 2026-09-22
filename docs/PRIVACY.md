# Privacy

FileTriage has no networking client, analytics, account system, advertising SDK or automatic updater. It never uploads files or directory listings. Quick Look previews are provided by macOS and the preview extensions installed on your Mac.

- **Inventory:** reads file names, locations, sizes, types and filesystem identity inside the chosen folder. No folder is scanned before you choose one or press Resume.
- **Exact duplicates:** reads file bytes locally to calculate SHA-256. It does not read app databases or chat history.
- **Similar images:** explicitly opt-in. Decodes images locally into tiny comparison thumbnails. Similarity is not a deletion recommendation.
- **Preview:** reads only the selected file and, in duplicate views, a comparison file from the same group.
- **Local settings:** the last chosen folder and selected file path are stored in this Mac's UserDefaults. The file inventory and undo tickets stay in memory and are discarded on exit.
- **Permissions:** uses normal macOS file permissions. Protected folders may be skipped. FileTriage does not bypass OS restrictions or automatically request Full Disk Access.

Keep private names, file paths and screenshots out of public bug reports. Reports should use synthetic examples. There is no bundled file inventory in this repository or its release.
