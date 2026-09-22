import Foundation

public struct RestoreTicket {
    public let original: URL
    public let trashed: URL
    public let identity: FileIdentity
    public init(original: URL, trashed: URL, identity: FileIdentity) { self.original = original; self.trashed = trashed; self.identity = identity }
}
public struct FileFailure { public let url: URL; public let message: String }
public struct MoveResult { public let tickets: [RestoreTicket]; public let failures: [FileFailure] }
public struct RestoreResult {
    public let restored: [URL]; public let pending: [RestoreTicket]; public let failures: [FileFailure]
    /// Whole-folder restores that hit a conflict and wait for a retry.
    public let pendingFolders: [FolderTicket]
    public init(restored: [URL], pending: [RestoreTicket], failures: [FileFailure], pendingFolders: [FolderTicket] = []) {
        self.restored = restored; self.pending = pending; self.failures = failures; self.pendingFolders = pendingFolders
    }
}

public protocol TrashBackend {
    func moveToTrash(_ url: URL) throws -> URL
    func restore(_ source: URL, to destination: URL) throws
}
public struct SystemTrash: TrashBackend {
    public init() {}
    public func moveToTrash(_ url: URL) throws -> URL {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        guard let destination = result as URL? else {
            throw NSError(domain: "Avakasha", code: 1, userInfo: [NSLocalizedDescriptionKey: "macOS moved the item but did not return its Trash location. Use Finder to restore it."])
        }
        return destination
    }
    public func restore(_ source: URL, to destination: URL) throws {
        // FileManager fails if destination exists; never remove or replace an existing file.
        try FileManager.default.moveItem(at: source, to: destination)
    }
}

public enum TrashService {
    public static func move(_ files: [FileRecord], root: URL, keepers: [String: FileRecord] = [:],
                            backend: TrashBackend = SystemTrash()) -> MoveResult {
        let ids = Set(files.map(\.id)); var tickets: [RestoreTicket] = []; var failures: [FileFailure] = []
        let blocked = Set(keepers.flatMap { extra, keeper in ids.contains(keeper.id) ? [extra, keeper.id] : [] })
        var processed = Set<String>()
        for file in files where processed.insert(file.id).inserted {
            do {
                guard !blocked.contains(file.id) else { throw TriageError.missingKeeper }
                try FileSafety.validate(file, root: root)
                if let keeper = keepers[file.id] {
                    guard !ids.contains(keeper.id) else { throw TriageError.missingKeeper }
                    do {
                        try FileSafety.validate(keeper, root: root)
                        guard try ExactDuplicates.digest(file, root: root, token: CancellationToken()) == ExactDuplicates.digest(keeper, root: root, token: CancellationToken()),
                              ExactDuplicates.safeToAutoSelect(file, keeper) else { throw TriageError.missingKeeper }
                    } catch { throw TriageError.missingKeeper }
                }
                let destination = try backend.moveToTrash(file.url)
                let actual: FileIdentity
                do { actual = try FileIdentity(url: destination) }
                catch {
                    tickets.append(RestoreTicket(original:file.url,trashed:destination,identity:file.identity))
                    throw NSError(domain:"Avakasha",code:3,userInfo:[NSLocalizedDescriptionKey:"The file was moved, but its Trash identity could not be checked. Inspect it in Finder Trash; Undo may be unavailable."])
                }
                let ticket = RestoreTicket(original: file.url, trashed: destination, identity: actual)
                var valid = actual == file.identity
                if let keeper = keepers[file.id] {
                    valid = valid && (try? FileSafety.validate(keeper, root: root)) != nil
                    if valid {
                        if let moved = try? FileRecord(url: destination), let left = try? ExactDuplicates.digest(moved, root: destination.deletingLastPathComponent(), token: CancellationToken()),
                           let right = try? ExactDuplicates.digest(keeper, root: root, token: CancellationToken()) { valid = left == right }
                        else { valid = false }
                    }
                }
                if !valid {
                    let rollback = undo([ticket], root: root, backend: backend)
                    tickets.append(contentsOf: rollback.pending)
                    throw NSError(domain: "Avakasha", code: 2, userInfo: [NSLocalizedDescriptionKey: rollback.pending.isEmpty ? "A concurrent change was detected. The moved file was restored; scan again." : "A concurrent change was detected. The file remains in Trash; use Undo or Finder to restore it."])
                }
                tickets.append(ticket)
            } catch { failures.append(FileFailure(url: file.url, message: error.localizedDescription)) }
        }
        return MoveResult(tickets: tickets, failures: failures)
    }
    public static func undo(_ tickets: [RestoreTicket], root: URL, backend: TrashBackend = SystemTrash()) -> RestoreResult {
        var restored: [URL] = []; var pending: [RestoreTicket] = []; var failures: [FileFailure] = []
        for ticket in tickets {
            do {
                let destination = ticket.original.standardizedFileURL
                guard destination.path.hasPrefix(root.standardizedFileURL.path + "/"),
                      destination.deletingLastPathComponent().resolvingSymlinksInPath() == destination.deletingLastPathComponent(),
                      ticket.trashed.resolvingSymlinksInPath() == ticket.trashed,
                      try FileIdentity(url: ticket.trashed) == ticket.identity else { throw TriageError.unsafePath }
                // lstat also catches dangling symlinks that fileExists would miss.
                if (try? FileManager.default.attributesOfItem(atPath: destination.path)) != nil { throw TriageError.destinationExists }
                try backend.restore(ticket.trashed, to: destination); restored.append(destination)
            } catch { pending.append(ticket); failures.append(FileFailure(url: ticket.original, message: error.localizedDescription)) }
        }
        return RestoreResult(restored: restored, pending: pending, failures: failures)
    }
}
