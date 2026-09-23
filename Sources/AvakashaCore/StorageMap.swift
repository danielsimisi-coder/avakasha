import Foundation
import Darwin

/// One folder in a storage map. Sizes are allocated blocks on disk, so they are
/// estimates of usage, never a promise of how much space Trash would free:
/// APFS clones and snapshots, sparse files, cloud placeholders and hard links
/// all break the equation "sum of files = reclaimable space".
public final class StorageNode {
    public let url: URL
    public let name: String
    public let isHidden: Bool
    /// Bundles such as apps or photo libraries are measured but not opened: their contents are not reviewable files.
    public let isPackage: Bool
    /// True when the folder itself could not be read (permissions, Full Disk Access, or a protected location).
    public let isUnreadable: Bool
    /// Allocated bytes of everything below this folder, hard-linked data counted once.
    public private(set) var bytes: Int64 = 0
    /// Allocated bytes of the regular files directly inside this folder (not in subfolders).
    public private(set) var directBytes: Int64 = 0
    public private(set) var files: Int = 0
    /// Modification time (seconds since 1970) of the newest regular file anywhere below this folder; 0 when it holds none.
    public private(set) var newestModified: Int64 = 0
    public private(set) var directFiles: Int = 0
    public private(set) var directories: Int = 0
    /// Entries (files or folders) that could not be read or stat'd anywhere below this folder.
    public private(set) var inaccessible: Int = 0
    /// Cloud placeholders that are not downloaded locally. They are listed but take no local space.
    public private(set) var notDownloaded: Int = 0
    /// Mount points for other volumes found below this folder. They are not entered.
    public private(set) var otherVolumes: Int = 0
    public private(set) var children: [StorageNode] = []
    public weak private(set) var parent: StorageNode?

    init(url: URL, name: String, isHidden: Bool, isPackage: Bool, isUnreadable: Bool = false) {
        self.url = url; self.name = name; self.isHidden = isHidden; self.isPackage = isPackage; self.isUnreadable = isUnreadable
    }
    func addFile(bytes allocated: Int64) { directBytes += allocated; bytes += allocated; directFiles += 1; files += 1 }
    func noteModified(_ seconds: Int64) { if seconds > newestModified { newestModified = seconds } }
    func addSharedFile() { directFiles += 1; files += 1 }
    func addInaccessible() { inaccessible += 1 }
    func addNotDownloaded() { notDownloaded += 1 }
    func addOtherVolume() { otherVolumes += 1 }
    func addPackageEntry(bytes allocated: Int64, isDirectory: Bool) {
        if isDirectory { directories += 1 } else { bytes += allocated; files += 1 }
    }
    func absorb(_ child: StorageNode) {
        child.parent = self; children.append(child); noteModified(child.newestModified)
        bytes += child.bytes; files += child.files; directories += child.directories + 1
        inaccessible += child.inaccessible; notDownloaded += child.notDownloaded; otherVolumes += child.otherVolumes
    }
    /// Removes a moved child and subtracts its totals from every ancestor; used after a folder went to Trash.
    public func detach(_ child: StorageNode) {
        guard let index = children.firstIndex(where: { $0 === child }) else { return }
        children.remove(at: index)
        var node: StorageNode? = self
        while let n = node {
            n.bytes -= child.bytes; n.files -= child.files; n.directories -= child.directories + 1
            n.inaccessible -= child.inaccessible; n.notDownloaded -= child.notDownloaded; n.otherVolumes -= child.otherVolumes
            node = n.parent
        }
        child.parent = nil
    }
    func sortRecursively() {
        children.sort { $0.bytes == $1.bytes ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.bytes > $1.bytes }
        children.forEach { $0.sortRecursively() }
    }
    /// Folders from the map root down to this node.
    public var trail: [StorageNode] { var t = [self]; while let p = t[0].parent { t.insert(p, at: 0) }; return t }
    /// Bytes below this node that belong to entries the map could not measure.
    public var hasCaveats: Bool { inaccessible > 0 || notDownloaded > 0 || otherVolumes > 0 || isUnreadable }
}

/// One of the largest files under a mapped folder. `bytes` are allocated blocks, like `StorageNode.bytes`.
public struct LargeFile: Equatable {
    public let url: URL
    public let bytes: Int64
    public init(url: URL, bytes: Int64) { self.url = url; self.bytes = bytes }
}

public struct StorageMapResult {
    public let root: StorageNode
    public let cancelled: Bool
    /// Directory entries visited, including ones that failed.
    public let entries: Int
    /// Regular files with more than one hard link whose data was only counted once.
    public let sharedFiles: Int
    /// The `limit` largest reviewable files, sorted by bytes descending, ties by path ascending. Follows the
    /// file-review policy of `Scanner`: no package contents, hidden files or files under hidden folders, cloud
    /// placeholders or app databases, and hard-linked data listed once. Partial after cancellation.
    public let largestFiles: [LargeFile]
}

/// The largest files seen so far, kept as a sorted array with a cutoff so memory stays O(limit) however many files the walk visits.
struct LargestFiles {
    let limit: Int
    private(set) var items: [LargeFile] = []
    init(limit: Int) { self.limit = max(0, limit) }
    static func precedes(_ a: LargeFile, _ b: LargeFile) -> Bool { a.bytes == b.bytes ? a.url.path < b.url.path : a.bytes > b.bytes }
    /// Cheap pre-check so files that cannot make the list never get a name or URL built for them.
    func admits(bytes: Int64) -> Bool { limit > 0 && (items.count < limit || bytes >= items[limit - 1].bytes) }
    mutating func insert(_ file: LargeFile) {
        if items.count == limit, let last = items.last, !Self.precedes(file, last) { return }
        var lo = 0, hi = items.count
        while lo < hi { let mid = (lo + hi) / 2; if Self.precedes(items[mid], file) { lo = mid + 1 } else { hi = mid } }
        items.insert(file, at: lo); if items.count > limit { items.removeLast() }
    }
}

public enum StorageMapper {
    private static let SF_DATALESS_FLAG: UInt32 = 0x40000000
    private static let UF_HIDDEN_FLAG: UInt32 = 0x00008000
    /// App databases and thumbnail caches are not browseable media; same list as `Scanner`.
    private static let unreviewableExtensions: Set<String> = ["sqlite", "sqlite-wal", "sqlite-shm", "db", "db-wal", "db-shm", "thumb", "mmsthumb", "favicon"]

    /// Walks `root` without following symbolic links and without leaving its volume.
    /// The callback receives entries visited and bytes measured so far. Never reads file contents.
    /// `limit` caps `largestFiles`, collected in the same walk so the app never needs a second scan.
    public static func map(root: URL, token: CancellationToken, limit: Int = 200, progress: (Int, Int64) -> Void = { _, _ in }) throws -> StorageMapResult {
        try map(root: root, token: token, limit: limit, progress: progress, treatAsOtherVolume: { _ in false })
    }
    /// `treatAsOtherVolume` lets synthetic tests exercise the skip path without a real mount point.
    static func map(root: URL, token: CancellationToken, limit: Int = 200, progress: (Int, Int64) -> Void, treatAsOtherVolume: (String) -> Bool) throws -> StorageMapResult {
        let rootURL = try FileSafety.root(root)
        var rootStat = stat()
        guard rootURL.withUnsafeFileSystemRepresentation({ lstat($0, &rootStat) }) == 0 else { throw TriageError.inaccessible }
        let rootDevice = rootStat.st_dev
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(rootURL.path), nil]
        defer { free(argv[0]) }
        guard let handle = argv.withUnsafeMutableBufferPointer({ fts_open($0.baseAddress, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil) }) else { throw TriageError.inaccessible }
        defer { fts_close(handle) }

        var stack: [StorageNode] = []
        var packageLevel: Int16? = nil          // level of the package currently being measured
        var skippedPath: String? = nil          // fts returns a skipped directory once more, as FTS_DP; ignore that visit
        var seenLinks = Set<String>()           // "dev:inode" for files with st_nlink > 1
        var sharedFiles = 0, entries = 0, cancelled = false
        var largest = LargestFiles(limit: limit)
        func currentTotal() -> Int64 { stack.reduce(0) { $0 + $1.bytes } }

        while let entry = fts_read(handle) {
            entries += 1
            if entries % 256 == 0, token.isCancelled { cancelled = true; break }
            if entries % 2048 == 0 { progress(entries, currentTotal()) }
            let e = entry.pointee
            let info = Int32(e.fts_info)
            let level = e.fts_level
            let statp = e.fts_statp
            let flags = statp?.pointee.st_flags ?? 0
            // fts_name is a flexible array member; derive the name from the full path instead of copying the struct.
            let name = info == FTS_D || info == FTS_DNR || info == FTS_ERR ? (String(cString: e.fts_path) as NSString).lastPathComponent : ""
            let hidden = name.hasPrefix(".") || flags & UF_HIDDEN_FLAG != 0
            let dataless = flags & SF_DATALESS_FLAG != 0
            let insidePackage = packageLevel != nil && level > packageLevel!

            switch info {
            case FTS_D:
                if level == 0 {
                    stack.append(StorageNode(url: rootURL, name: rootURL.lastPathComponent, isHidden: false, isPackage: false)); continue
                }
                guard let parent = stack.last else { continue }
                let path = String(cString: e.fts_path)
                if (statp.map { $0.pointee.st_dev != rootDevice } ?? false) || treatAsOtherVolume(path) { parent.addOtherVolume(); fts_set(handle, entry, FTS_SKIP); skippedPath = path; continue }
                if dataless { parent.addNotDownloaded(); fts_set(handle, entry, FTS_SKIP); skippedPath = path; continue }
                if insidePackage { stack.last?.addPackageEntry(bytes: 0, isDirectory: true); continue }
                let url = URL(fileURLWithPath: path, isDirectory: true)
                let package = !url.pathExtension.isEmpty && ((try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false)
                let node = StorageNode(url: url, name: name, isHidden: hidden, isPackage: package)
                if package { packageLevel = level }
                stack.append(node)
            case FTS_DP:
                if let skipped = skippedPath, skipped == String(cString: e.fts_path) { skippedPath = nil; continue }
                if insidePackage { continue } // folders inside a package were never pushed
                guard stack.count > 1, let node = stack.popLast() else { continue }
                if packageLevel == level { packageLevel = nil }
                stack.last!.absorb(node)
            case FTS_F:
                guard let node = stack.last, let s = statp else { continue }
                if insidePackage { node.addPackageEntry(bytes: dataless ? 0 : Int64(s.pointee.st_blocks) * 512, isDirectory: false); node.noteModified(Int64(s.pointee.st_mtimespec.tv_sec)); continue }
                if dataless { node.addNotDownloaded(); node.addSharedFile(); continue }
                if s.pointee.st_nlink > 1 {
                    let key = "\(s.pointee.st_dev):\(s.pointee.st_ino)"
                    if !seenLinks.insert(key).inserted { sharedFiles += 1; node.addSharedFile(); continue }
                }
                let allocated = Int64(s.pointee.st_blocks) * 512
                node.addFile(bytes: allocated); node.noteModified(Int64(s.pointee.st_mtimespec.tv_sec))
                // fts_path ends with the entry's name, so its last fts_namelen bytes are the name without copying the struct.
                let namePtr = e.fts_path + Int(e.fts_pathlen) - Int(e.fts_namelen)
                guard largest.admits(bytes: allocated), namePtr.pointee != 0x2E /* "." */, flags & UF_HIDDEN_FLAG == 0,
                      !stack.contains(where: \.isHidden), !unreviewableExtensions.contains((String(cString: namePtr) as NSString).pathExtension.lowercased()) else { continue }
                largest.insert(LargeFile(url: URL(fileURLWithPath: String(cString: e.fts_path), isDirectory: false), bytes: allocated))
            case FTS_DNR, FTS_ERR:
                // fts reports an unreadable directory a second time, after its preorder FTS_D visit and without FTS_DP.
                if level == 0 { throw TriageError.inaccessible }
                let url = URL(fileURLWithPath: String(cString: e.fts_path), isDirectory: true)
                if insidePackage { stack.last?.addInaccessible(); continue }
                if stack.count > 1, stack.last?.url == url { stack.removeLast(); if packageLevel == level { packageLevel = nil } }
                guard let parent = stack.last else { continue }
                let node = StorageNode(url: url, name: name, isHidden: hidden, isPackage: false, isUnreadable: true)
                node.addInaccessible(); parent.absorb(node)
            case FTS_NS:
                if level == 0 { throw TriageError.inaccessible }
                stack.last?.addInaccessible()
            default:
                continue // symbolic links, sockets, devices and cycles take no reviewable space
            }
        }
        // Unwind partial results after cancellation so every parent still has honest subtotals.
        while stack.count > 1 { let node = stack.removeLast(); stack.last!.absorb(node) }
        guard let root = stack.first else { throw TriageError.inaccessible }
        root.sortRecursively()
        progress(entries, root.bytes)
        return StorageMapResult(root: root, cancelled: cancelled, entries: entries, sharedFiles: sharedFiles, largestFiles: largest.items)
    }
}
