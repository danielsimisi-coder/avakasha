import Foundation

/// Session-only undo/redo. Calls must be serialized by the application's work queue.
public final class TrashHistory {
    private struct UndoBatch { let root: URL; let tickets: [RestoreTicket]; let keepers: [String: FileRecord] }
    private struct RedoBatch { let root: URL; let files: [FileRecord]; let keepers: [String: FileRecord] }
    private var undoStack: [UndoBatch] = []
    private var redoStack: [RedoBatch] = []
    public init() {}
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public func move(_ files: [FileRecord], root: URL, keepers: [String: FileRecord] = [:], backend: TrashBackend = SystemTrash()) -> MoveResult {
        let result = TrashService.move(files, root: root, keepers: keepers, backend: backend)
        if !result.tickets.isEmpty {
            undoStack.append(UndoBatch(root: root, tickets: result.tickets, keepers: keepers))
            redoStack.removeAll()
        }
        return result
    }

    public func undo(backend: TrashBackend = SystemTrash()) -> RestoreResult? {
        guard let batch = undoStack.popLast() else { return nil }
        let result = TrashService.undo(batch.tickets, root: batch.root, backend: backend)
        if !result.pending.isEmpty { undoStack.append(UndoBatch(root: batch.root, tickets: result.pending, keepers: batch.keepers)) }
        let restored = Set(result.restored.map(\.path))
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
        if !result.tickets.isEmpty { undoStack.append(UndoBatch(root: batch.root, tickets: result.tickets, keepers: batch.keepers)) }
        let moved = Set(result.tickets.map { $0.original.path })
        let pending = batch.files.filter { !moved.contains($0.id) }
        if !pending.isEmpty { redoStack.append(RedoBatch(root: batch.root, files: pending, keepers: batch.keepers)) }
        return result
    }
}
