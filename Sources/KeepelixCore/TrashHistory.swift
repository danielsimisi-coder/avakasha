import Foundation
import Darwin

/// Session-only undo/redo. Calls must be serialized by the application's work queue.
public final class TrashHistory {
    private struct UndoBatch { let root: URL; let tickets: [RestoreTicket]; let keepers: [String: FileRecord] }
    private struct RedoBatch { let root: URL; let files: [FileRecord]; let keepers: [String: FileRecord] }
    private var undoStack: [UndoBatch] = []
    private var redoStack: [RedoBatch] = []
    /// Restores that hit a conflict (an existing file at the original path, or a changed Trash item).
    /// They wait here for an explicit retry and never block Undo of earlier batches.
    private var blocked: [UndoBatch] = []
    /// Allocated bytes (disk blocks, not logical size) of every file this session moved to Trash and has not restored.
    /// It is what the user moved, not what is free: Trash keeps the blocks until emptied, and APFS clones can free less.
    public private(set) var sessionMovedBytes: Int64 = 0
    /// Allocated bytes recorded when each ticket was created, keyed by the Trash location so a later move of a file at
    /// the same original path (while the first waits in `blocked`) cannot be confused with it.
    private var ticketBytes: [String: Int64] = [:]
    public init() {}
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var blockedCount: Int { blocked.reduce(0) { $0 + $1.tickets.count } }
    /// Trash locations of every waiting restore, for Finder recovery after the session.
    public var blockedItems: [RestoreTicket] { blocked.flatMap(\.tickets) }

    public func move(_ files: [FileRecord], root: URL, keepers: [String: FileRecord] = [:], backend: TrashBackend = SystemTrash()) -> MoveResult {
        let result = TrashService.move(files, root: root, keepers: keepers, backend: backend)
        if !result.tickets.isEmpty {
            undoStack.append(UndoBatch(root: root, tickets: result.tickets, keepers: keepers))
            redoStack.removeAll()
            count(result.tickets, from: files)
        }
        return result
    }

    /// Adds the allocated bytes of the files behind freshly created tickets; failed files never count.
    private func count(_ tickets: [RestoreTicket], from files: [FileRecord]) {
        let bytes = Dictionary(files.map { ($0.id, $0.allocatedBytes) }, uniquingKeysWith: { first, _ in first })
        for ticket in tickets {
            guard let size = bytes[ticket.original.path] else { continue }
            ticketBytes[ticket.trashed.path] = size; sessionMovedBytes += size
        }
    }
    /// Subtracts the bytes recorded at move time for every ticket that was actually restored; never below zero.
    private func discount(_ tickets: [RestoreTicket]) {
        for ticket in tickets {
            guard let size = ticketBytes.removeValue(forKey: ticket.trashed.path) else { continue }
            sessionMovedBytes = max(0, sessionMovedBytes - size)
        }
    }

    public func undo(backend: TrashBackend = SystemTrash()) -> RestoreResult? {
        guard let batch = undoStack.popLast() else { return nil }
        return restore(batch, backend: backend)
    }

    /// Attempts every waiting restore again. Items still in conflict keep waiting; nothing is overwritten.
    public func retryBlocked(backend: TrashBackend = SystemTrash()) -> RestoreResult? {
        guard !blocked.isEmpty else { return nil }
        let waiting = blocked; blocked = []
        var restored: [URL] = [], pending: [RestoreTicket] = [], failures: [FileFailure] = []
        for batch in waiting {
            let result = restore(batch, backend: backend)
            restored += result.restored; pending += result.pending; failures += result.failures
        }
        return RestoreResult(restored: restored, pending: pending, failures: failures)
    }

    private func restore(_ batch: UndoBatch, backend: TrashBackend) -> RestoreResult {
        let attempt = TrashService.undo(batch.tickets, root: batch.root, backend: backend)
        // A ticket whose Trash item is gone (restored in Finder, or Trash emptied) can never succeed; report it once instead of waiting forever.
        var pending: [RestoreTicket] = [], failures: [FileFailure] = []
        for (ticket, failure) in zip(attempt.pending, attempt.failures) {
            var s = stat()
            if ticket.trashed.withUnsafeFileSystemRepresentation({ lstat($0, &s) }) != 0 && errno == ENOENT {
                failures.append(FileFailure(url: ticket.original, message: "The item is no longer in Trash, so it cannot be restored by Keepelix. It may have been restored in Finder or Trash was emptied."))
            } else { pending.append(ticket); failures.append(failure) }
        }
        let result = RestoreResult(restored: attempt.restored, pending: pending, failures: failures)
        if !result.pending.isEmpty { blocked.append(UndoBatch(root: batch.root, tickets: result.pending, keepers: batch.keepers)) }
        let restored = Set(result.restored.map(\.path))
        discount(batch.tickets.filter { restored.contains($0.original.path) })
        let records = batch.tickets.compactMap { ticket -> FileRecord? in
            guard restored.contains(ticket.original.path), let record = try? FileRecord(url: ticket.original),
                  record.identity == ticket.identity, (try? FileSafety.validate(record, root: batch.root)) != nil else { return nil }
            return record
        }
        if !records.isEmpty { redoStack.append(RedoBatch(root: batch.root, files: records, keepers: batch.keepers)) }
        return result
    }

    public func redo(backend: TrashBackend = SystemTrash()) -> MoveResult? {
        guard let batch = redoStack.popLast() else { return nil }
        // Original identities and keeper guards are retained; never adopt replacement files.
        let result = TrashService.move(batch.files, root: batch.root, keepers: batch.keepers, backend: backend)
        if !result.tickets.isEmpty { undoStack.append(UndoBatch(root: batch.root, tickets: result.tickets, keepers: batch.keepers)); count(result.tickets, from: batch.files) }
        let moved = Set(result.tickets.map { $0.original.path })
        let pending = batch.files.filter { !moved.contains($0.id) }
        if !pending.isEmpty { redoStack.append(RedoBatch(root: batch.root, files: pending, keepers: batch.keepers)) }
        return result
    }
}
