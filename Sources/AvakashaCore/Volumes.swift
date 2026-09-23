import Foundation

/// Capacity of one mounted volume. Read from volume attributes only; nothing inside the volume is listed.
public struct VolumeInfo: Equatable {
    public let url: URL
    public let name: String
    public let total: Int64
    public let available: Int64
    public let isInternal: Bool
    public let isRemovable: Bool
    public let isStartup: Bool
    /// Space macOS reports it can free by itself when needed (important-usage capacity minus plain available capacity), already counted in `available`.
    public let purgeable: Int64
    public let isReadOnly: Bool
    public let uuid: String?
    public init(url: URL, name: String, total: Int64, available: Int64, isInternal: Bool, isRemovable: Bool, isStartup: Bool, purgeable: Int64 = 0, isReadOnly: Bool = false, uuid: String? = nil) {
        self.url = url; self.name = name; self.total = total; self.available = available; self.isInternal = isInternal; self.isRemovable = isRemovable; self.isStartup = isStartup
        self.purgeable = purgeable; self.isReadOnly = isReadOnly; self.uuid = uuid
    }
    public var used: Int64 { max(0, total - available) }
    public var usedFraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }
}

public enum Volumes {
    private static let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
                                                    .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsRootFileSystemKey, .volumeIsBrowsableKey, .volumeIsLocalKey, .volumeURLKey,
                                                    .volumeIsReadOnlyKey, .volumeUUIDStringKey]

    /// Browsable local volumes, startup disk first, then by name. "Free" is what the current user may still write
    /// (purgeable space is not counted as used); Trash contents are not free until emptied.
    public static func mounted() -> [VolumeInfo] {
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) else { return [] }
        var seen = Set<String>(); var result: [VolumeInfo] = []
        for url in urls {
            guard let info = info(at: url), seen.insert(info.url.path).inserted else { continue }
            result.append(info)
        }
        return result.sorted { a, b in a.isStartup != b.isStartup ? a.isStartup : a.name.localizedStandardCompare(b.name) == .orderedAscending }
    }

    /// Drives that can hold a copy of `source`: external, local, writable, not the startup disk and not the drive `source` is on.
    /// Internal volumes are left out: another volume on the same internal disk would free nothing.
    public static func offloadDestinations(for source: URL) -> [VolumeInfo] {
        var s = stat(); guard stat(source.path, &s) == 0 else { return [] }
        return mounted().filter { v in
            var d = stat()
            return !v.isStartup && !v.isReadOnly && (!v.isInternal || v.isRemovable) && stat(v.url.path, &d) == 0 && d.st_dev != s.st_dev
        }
    }
    /// The volume that holds `url`, or nil when the path does not exist or is not a browsable local volume.
    public static func info(at url: URL) -> VolumeInfo? {
        guard let v = try? url.resourceValues(forKeys: keys), v.volumeIsLocal ?? false, v.volumeIsBrowsable ?? true,
              let total = v.volumeTotalCapacity, total > 0 else { return nil }
        let important = v.volumeAvailableCapacityForImportantUsage ?? 0
        let plain = Int64(v.volumeAvailableCapacity ?? 0)
        let available = important > 0 ? important : plain
        let volumeURL = v.volume ?? url
        return VolumeInfo(url: volumeURL, name: v.volumeName ?? volumeURL.lastPathComponent, total: Int64(total), available: available,
                          isInternal: v.volumeIsInternal ?? false, isRemovable: v.volumeIsRemovable ?? false, isStartup: v.volumeIsRootFileSystem ?? (volumeURL.path == "/"), purgeable: important > plain ? important - plain : 0,
                          isReadOnly: v.volumeIsReadOnly ?? false, uuid: v.volumeUUIDString)
    }
}
