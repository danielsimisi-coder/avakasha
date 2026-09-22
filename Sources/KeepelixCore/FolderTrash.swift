import Foundation
import Darwin

/// Identity of a directory for whole-folder moves: device and inode only. A folder's own modification time changes
/// whenever a direct child is added or removed, including Finder's `.DS_Store`, so it cannot gate restores; the
/// no-overwrite check on the destination protects the user instead.
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
    public static func check(_ folder: URL, root: URL) throws -> FolderIdentity {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let path = folder.standardizedFileURL
        guard path.path.hasPrefix(rootPath + "/"), path.path != rootPath, path.resolvingSymlinksInPath().path == path.path else { throw TriageError.unsafePath }
        guard !path.lastPathComponent.hasPrefix(".") else { throw TriageError.folderProtected }
        if let values = try? path.resourceValues(forKeys: [.isPackageKey, .isHiddenKey]), values.isPackage == true || values.isHidden == true { throw TriageError.folderProtected }
        return try FolderIdentity(url: path)
    }

    /// Moves `folder` to Trash when it still is the folder that was measured (`expected`). Never follows links, never
    /// touches anything outside `root`, and verifies the moved item keeps its identity; otherwise it tries to put it back.
    public static func move(_ folder: URL, root: URL, expected: FolderIdentity, backend: TrashBackend = SystemTrash()) -> FolderMoveResult {
        do {
            let current = try check(folder, root: root)
            guard current == expected else { throw TriageError.changed }
            let destination = try backend.moveToTrash(folder.standardizedFileURL)
            guard let moved = try? FolderIdentity(url: destination), moved.sameFolder(as: current) else {
                let rollback = restore(FolderTicket(original: folder.standardizedFileURL, trashed: destination, identity: (try? FolderIdentity(url: destination)) ?? current), root: root, backend: backend)
                throw NSError(domain: "Keepelix", code: 7, userInfo: [NSLocalizedDescriptionKey: rollback.restored
                    ? "The folder changed while it was moved. It was put back; measure it again."
                    : "The folder was moved but could not be verified afterwards. Inspect it in Finder Trash; Undo may be unavailable."])
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
