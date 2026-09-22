import Foundation
import Darwin

/// Identity of a directory for whole-folder moves. The move requires the full identity (device, inode and the folder's
/// own modification time, which changes whenever a direct child is added or removed) to match what was just measured.
/// Restores compare device and inode only: Finder may write `.DS_Store` inside a folder in Trash, and the no-overwrite
/// check on the destination protects the user there.
public struct FolderIdentity: Equatable {
    public let device: Int32
    public let inode: UInt64
    public let modifiedSeconds: Int64
    public let modifiedNanos: Int64
    public init(url: URL) throws {
        var s = stat()
        guard url.withUnsafeFileSystemRepresentation({ lstat($0, &s) }) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard s.st_mode & S_IFMT == S_IFDIR else { throw TriageError.unsafePath }
        guard s.st_flags & 0x40000000 == 0 else { throw TriageError.notLocal } // SF_DATALESS
        device = s.st_dev; inode = s.st_ino
        modifiedSeconds = Int64(s.st_mtimespec.tv_sec); modifiedNanos = Int64(s.st_mtimespec.tv_nsec)
    }
    public func sameFolder(as other: FolderIdentity) -> Bool { device == other.device && inode == other.inode }
}

public struct FolderTicket: Equatable {
    public let original: URL
    public let trashed: URL
    public let identity: FolderIdentity
    public init(original: URL, trashed: URL, identity: FolderIdentity) { self.original = original; self.trashed = trashed; self.identity = identity }
}
public struct FolderMoveResult { public let ticket: FolderTicket?; public let failure: FileFailure? }
public struct FolderRestoreResult { public let restored: Bool; public let failure: FileFailure? }

/// Moving a whole folder is the most dangerous action in the app, so it is gated harder than file moves:
/// the folder must sit strictly inside the chosen root, must not be the root, a symbolic link, a package, hidden,
/// or a cloud placeholder, and its identity must match what was measured moments before the confirmation.
public enum FolderTrash {
    /// Whole-folder moves are allowed only inside the user's own areas: below the home folder (never the home folder itself),
    /// below the process temporary folder (tests and the demo), or below a mounted volume's root. System folders,
    /// /Applications, /Library, other users and volume roots are refused whatever root was chosen.
    static func isProtected(_ path: String, home: String, temporary: String? = nil) -> Bool {
        if path == home || home.hasPrefix(path + "/") { return true }
        if path.hasPrefix(home + "/") { return false }
        if let temporary = temporary, path.hasPrefix(temporary.hasSuffix("/") ? temporary : temporary + "/") { return false }
        if path.hasPrefix("/Volumes/") { return !path.dropFirst("/Volumes/".count).contains("/") } // a volume's own root is protected, its contents are not
        return true
    }
    /// Verifies a folder may be moved as a whole and returns its identity for the move that follows.
    /// `allowHiddenAncestors` is false for the map (nothing under a hidden folder is offered, matching file review)
    /// and true only for the vetted catalogue, whose entries live under Library or dot folders by design.
    public static func check(_ folder: URL, root: URL, allowHiddenAncestors: Bool = false) throws -> FolderIdentity {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let path = folder.standardizedFileURL
        guard path.path.hasPrefix(rootPath + "/"), path.path != rootPath, path.resolvingSymlinksInPath().path == path.path else { throw TriageError.unsafePath }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.resolvingSymlinksInPath().path
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        guard !isProtected(path.resolvingSymlinksInPath().path, home: home, temporary: temporary) else { throw TriageError.folderProtected }
        guard !path.lastPathComponent.hasPrefix(".") else { throw TriageError.folderProtected }
        if let values = try? path.resourceValues(forKeys: [.isPackageKey, .isHiddenKey]), values.isPackage == true || values.isHidden == true { throw TriageError.folderProtected }
        if !allowHiddenAncestors {
            var ancestor = path.deletingLastPathComponent()
            while ancestor.path.count > rootPath.count {
                if ancestor.lastPathComponent.hasPrefix(".") { throw TriageError.folderProtected }
                if let hidden = try? ancestor.resourceValues(forKeys: [.isHiddenKey]).isHidden, hidden { throw TriageError.folderProtected }
                ancestor = ancestor.deletingLastPathComponent()
            }
        }
        var rootStat = stat()
        guard root.standardizedFileURL.withUnsafeFileSystemRepresentation({ lstat($0, &rootStat) }) == 0 else { throw TriageError.unsafePath }
        let identity = try FolderIdentity(url: path)
        guard identity.device == rootStat.st_dev else { throw TriageError.notLocal } // a mount point inside the root is never moved
        return identity
    }

    /// Moves `folder` to Trash when it still is the folder that was measured (`expected`). Never follows links, never
    /// touches anything outside `root`, and verifies the moved item keeps its identity; otherwise it tries to put it back.
    public static func move(_ folder: URL, root: URL, expected: FolderIdentity, allowHiddenAncestors: Bool = false, backend: TrashBackend = SystemTrash()) -> FolderMoveResult {
        do {
            let current = try check(folder, root: root, allowHiddenAncestors: allowHiddenAncestors)
            guard current == expected else { throw TriageError.changed }
            let destination = try backend.moveToTrash(folder.standardizedFileURL)
            // Only the folder that was checked may be recorded for Undo. If what sits at the reported Trash location is not that
            // folder, nothing is touched further (a rollback could move the wrong item) and the user is pointed at Finder Trash.
            guard let moved = try? FolderIdentity(url: destination), moved.sameFolder(as: current) else {
                throw NSError(domain: "Avakasha", code: 7, userInfo: [NSLocalizedDescriptionKey: "The folder was moved but could not be verified afterwards. Inspect it in Finder Trash; Undo is unavailable for it."])
            }
            return FolderMoveResult(ticket: FolderTicket(original: folder.standardizedFileURL, trashed: destination, identity: moved), failure: nil)
        } catch { return FolderMoveResult(ticket: nil, failure: FileFailure(url: folder, message: error.localizedDescription)) }
    }

    /// Restores a folder from Trash to its original path. Refuses when anything already exists there (never overwrites),
    /// when the original parent is now a link, or when the Trash item is no longer the same folder.
    public static func restore(_ ticket: FolderTicket, root: URL, backend: TrashBackend = SystemTrash()) -> FolderRestoreResult {
        do {
            let destination = ticket.original.standardizedFileURL
            let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
            // Compare paths, not URLs: a resolved URL of an existing directory gains a trailing slash.
            guard destination.path.hasPrefix(rootPath + "/"),
                  destination.deletingLastPathComponent().resolvingSymlinksInPath().path == destination.deletingLastPathComponent().path,
                  ticket.trashed.resolvingSymlinksInPath().path == ticket.trashed.path,
                  try FolderIdentity(url: ticket.trashed).sameFolder(as: ticket.identity) else { throw TriageError.unsafePath }
            if (try? FileManager.default.attributesOfItem(atPath: destination.path)) != nil { throw TriageError.destinationExists }
            try backend.restore(ticket.trashed, to: destination)
            return FolderRestoreResult(restored: true, failure: nil)
        } catch { return FolderRestoreResult(restored: false, failure: FileFailure(url: ticket.original, message: error.localizedDescription)) }
    }
}
