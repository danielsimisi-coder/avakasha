import Foundation

/// Free space on the volume that holds a URL, for an honest "space" summary next to the session's Trash total.
/// Sizes throughout Avakasha are allocated blocks (FileRecord.allocatedBytes), not logical lengths, and items moved to
/// Trash are NOT free space until the user empties Trash. APFS clones and snapshots can also make the space actually
/// freed differ from the bytes moved, so the UI must present these two numbers side by side, never as one prediction.
public enum DiskSpace {
    /// Bytes the current user may still write on the volume of `url` (macOS's "important usage" figure, which counts
    /// purgeable space; falls back to the plain available capacity). nil when the path does not exist or cannot be read.
    public static func available(at url: URL) -> Int64? {
        if let important = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        if let plain = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity { return Int64(plain) }
        return nil
    }
}
