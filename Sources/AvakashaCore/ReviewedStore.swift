import Foundation

/// Remembers which files the user already looked at and decided to keep, so the next scan can skip them.
/// Entries are keyed by path and pinned to the file's size and modification time: a file rewritten since it was
/// reviewed no longer matches and is shown again. The store never touches the file system; it only compares the
/// identities the scanner already collected, so it can never move, read or delete anything.
/// Calls must be serialized by the application's work queue.
public final class ReviewedStore {
    private var entries: [String: String]
    private let save: ([String: String]) -> Void

    /// `load` runs once here; `save` receives the complete dictionary after every change. Stored values that do
    /// not parse are dropped on load rather than trusted, so a corrupted store can only forget, never mis-skip.
    public init(load: () -> [String: String], save: @escaping ([String: String]) -> Void) {
        entries = load().filter { ReviewedStore.parse($0.value) != nil }
        self.save = save
    }

    /// Number of remembered files, including ones whose current identity has not been re-checked.
    public var count: Int { entries.count }

    /// True only when the stored identity equals the record's current size and mtime.
    public func isReviewed(_ record: FileRecord) -> Bool {
        guard let stored = entries[record.id], let (size, seconds, nanos) = ReviewedStore.parse(stored) else { return false }
        let i = record.identity
        return size == i.size && seconds == i.modifiedSeconds && nanos == i.modifiedNanos
    }

    /// Records the current identity of each file; a previous entry for the same path is replaced.
    public func mark(_ records: [FileRecord]) {
        guard !records.isEmpty else { return }
        for r in records { entries[r.id] = ReviewedStore.encode(r.identity) }
        save(entries)
    }

    /// Forgets the given files regardless of their stored identity.
    public func unmark(_ records: [FileRecord]) {
        forget(paths: Set(records.map(\.id)))
    }

    /// Drops entries by path, e.g. after a move to Trash; a file restored later must be reviewed again.
    public func forget(paths: Set<String>) {
        let before = entries.count
        for p in paths { entries.removeValue(forKey: p) }
        if entries.count != before { save(entries) }
    }

    /// Marks all if any record is not currently reviewed, otherwise unmarks all. Returns the resulting state.
    @discardableResult
    public func toggle(_ records: [FileRecord]) -> Bool {
        guard !records.isEmpty else { return false }
        if records.allSatisfy(isReviewed) { unmark(records); return false }
        mark(records); return true
    }

    private static func encode(_ i: FileIdentity) -> String { "\(i.size):\(i.modifiedSeconds):\(i.modifiedNanos)" }

    private static func parse(_ value: String) -> (Int64, Int64, Int64)? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, let size = Int64(parts[0]), let seconds = Int64(parts[1]), let nanos = Int64(parts[2]) else { return nil }
        return (size, seconds, nanos)
    }
}
