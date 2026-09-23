import Foundation
import Darwin

/// One APFS snapshot on a volume: its name and when it was taken. Sizes are not available without administrator rights.
public struct LocalSnapshot: Equatable {
    public let name: String
    public let created: Date
    public init(name: String, created: Date) { self.name = name; self.created = created }
    /// Time Machine's local snapshots: "com.apple.TimeMachine.2026-09-23-101010.local". Snapshots on a backup disk end in ".backup" and are not local.
    public var isTimeMachine: Bool { name.hasPrefix("com.apple.TimeMachine.") && name.hasSuffix(".local") }
}

/// Local snapshots are part of what macOS shows as System Data. They are listed with fs_snapshot_list(2), the call behind
/// `tmutil listlocalsnapshots`: names and dates only, no administrator rights, nothing is changed.
public enum LocalSnapshots {
    private typealias ListFunction = @convention(c) (Int32, UnsafeMutablePointer<attrlist>, UnsafeMutableRawPointer, Int, UInt32) -> Int32
    /// The volume that holds snapshots of your data: the Data volume for the startup disk, the volume itself otherwise.
    /// Only internal drives are asked, so a sleeping external drive never stalls the interface.
    public static func listIfInternal(_ volume: VolumeInfo) -> [LocalSnapshot] { volume.isInternal || volume.isStartup ? list(on: dataVolume(for: volume)) : [] }
    public static func dataVolume(for volume: VolumeInfo) -> URL {
        volume.isStartup && FileManager.default.fileExists(atPath: "/System/Volumes/Data") ? URL(fileURLWithPath: "/System/Volumes/Data") : volume.url
    }
    public static func list(on volume: URL) -> [LocalSnapshot] {
        // fs_snapshot_list is declared in <sys/snapshot.h> but not exported to Swift; look it up once.
        guard let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "fs_snapshot_list") else { return [] }
        let list = unsafeBitCast(symbol, to: ListFunction.self)
        let fd = open(volume.path, O_RDONLY)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var attributes = attrlist()
        attributes.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attributes.commonattr = attrgroup_t(bitPattern: Int32(bitPattern: ATTR_CMN_RETURNED_ATTRS) | ATTR_CMN_NAME | ATTR_CMN_CRTIME)
        var snapshots: [LocalSnapshot] = []
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { list(fd, &attributes, $0.baseAddress!, $0.count, 0) }
            guard count > 0 else { break }
            buffer.withUnsafeBytes { raw in
                var offset = 0
                for _ in 0..<Int(count) {
                    guard offset + 4 <= raw.count else { return }
                    let length = Int(raw.load(fromByteOffset: offset, as: UInt32.self))
                    let returned = raw.load(fromByteOffset: offset + 4, as: attribute_set_t.self)
                    var field = offset + 4 + MemoryLayout<attribute_set_t>.size
                    var name = "", created = Date(timeIntervalSince1970: 0)
                    if returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 {
                        let reference = raw.load(fromByteOffset: field, as: attrreference_t.self)
                        let start = field + Int(reference.attr_dataoffset)
                        if start < offset + length, let base = raw.baseAddress { name = String(cString: base.advanced(by: start).assumingMemoryBound(to: CChar.self)) }
                        field += MemoryLayout<attrreference_t>.size
                    }
                    if returned.commonattr & attrgroup_t(ATTR_CMN_CRTIME) != 0 {
                        let time = raw.loadUnaligned(fromByteOffset: field, as: timespec.self)
                        created = Date(timeIntervalSince1970: TimeInterval(time.tv_sec))
                    }
                    if !name.isEmpty { snapshots.append(LocalSnapshot(name: name, created: created)) }
                    guard length > 0 else { return }
                    offset += length
                }
            }
        }
        return snapshots.sorted { $0.created > $1.created }
    }
}

/// What the weekly check and the low-space warning decide. Wording lives in the app; only numbers are stored.
public enum SpaceWatch {
    public static let week: TimeInterval = 7 * 24 * 3600
    public static func isDue(last: Date?, now: Date = Date(), interval: TimeInterval = week) -> Bool { last.map { now.timeIntervalSince($0) >= interval } ?? true }

    public enum Report: Equatable {
        /// This much can go to Trash now, `grew` more than at the previous check (nil on the first check).
        case canGo(bytes: Int64, grew: Int64?)
    }
    /// A notification is worth it only when there is real space to free, and on later checks only when it grew.
    public static func weeklyReport(previous: Int64?, current: Int64, minimum: Int64 = 2_000_000_000, minimumGrowth: Int64 = 1_000_000_000) -> Report? {
        guard current >= minimum else { return nil }
        guard let previous else { return .canGo(bytes: current, grew: nil) }
        let growth = current - previous
        return growth >= minimumGrowth ? .canGo(bytes: current, grew: growth) : nil
    }
    /// Low space: under 15 GB free, or under 10% on a disk smaller than 150 GB; whichever is smaller, so a large disk with plenty left never warns.
    public static func isLow(available: Int64, total: Int64) -> Bool { total > 0 && Double(available) < min(15_000_000_000, Double(total) * 0.10) }
    public static func shouldWarnLowSpace(available: Int64, total: Int64, lastWarned: Date?, now: Date = Date()) -> Bool {
        isLow(available: available, total: total) && isDue(last: lastWarned, now: now, interval: 24 * 3600)
    }
}
