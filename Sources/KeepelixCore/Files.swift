import Foundation
import Darwin

public final class CancellationToken {
    private let lock = NSLock()
    private var value = false
    public init() {}
    public func cancel() { lock.lock(); value = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    public func check() throws { if isCancelled { throw TriageError.cancelled } }
}

public enum TriageError: Error, LocalizedError {
    case cancelled, unsafePath, changed, notLocal, destinationExists, missingKeeper, inaccessible
    public var errorDescription: String? {
        switch self {
        case .inaccessible: return "This folder could not be read. Check its permissions or grant access in System Settings > Privacy & Security."
        case .cancelled: return "Operation cancelled."
        case .unsafePath: return "The file is outside the chosen folder, is a link, or is not a regular file."
        case .changed: return "The file changed since the scan. Scan again before moving it."
        case .notLocal: return "The file is not downloaded locally."
        case .destinationExists: return "A file already exists at the original location. Nothing was overwritten."
        case .missingKeeper: return "The retained duplicate is missing, changed, or selected. Nothing from this group was moved."
        }
    }
}

public struct FileIdentity: Equatable, Codable {
    public let device: Int32
    public let inode: UInt64
    public let size: Int64
    public let modifiedSeconds: Int64
    public let modifiedNanos: Int64
    public init(url: URL) throws {
        var s = stat()
        guard url.withUnsafeFileSystemRepresentation({ lstat($0, &s) }) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard s.st_mode & S_IFMT == S_IFREG else { throw TriageError.unsafePath }
        guard s.st_flags & 0x40000000 == 0 else { throw TriageError.notLocal } // SF_DATALESS
        device = s.st_dev; inode = s.st_ino; size = s.st_size
        modifiedSeconds = Int64(s.st_mtimespec.tv_sec); modifiedNanos = Int64(s.st_mtimespec.tv_nsec)
    }
}

public enum FileKind: String, CaseIterable, Codable {
    case image = "Images", video = "Videos", audio = "Audio", document = "Documents", archive = "Archives", other = "Other"
    public static func classify(_ url: URL) -> FileKind {
        let e = url.pathExtension.lowercased()
        if ["jpg","jpeg","png","heic","heif","webp","gif","tif","tiff","bmp"].contains(e) { return .image }
        if ["mp4","mov","mkv","avi","m4v","webm"].contains(e) { return .video }
        if ["mp3","m4a","wav","aiff","flac","opus","ogg","aac"].contains(e) { return .audio }
        if ["pdf","doc","docx","xls","xlsx","ppt","pptx","txt","rtf","md","pages","numbers","key"].contains(e) { return .document }
        if ["zip","rar","7z","tar","gz","dmg","pkg"].contains(e) { return .archive }
        return .other
    }
}

public struct FileRecord: Identifiable, Equatable {
    public var id: String { url.path }
    public let url: URL
    public let identity: FileIdentity
    public let allocatedBytes: Int64
    public let kind: FileKind
    public init(url: URL) throws {
        self.url = url.standardizedFileURL
        identity = try FileIdentity(url: url)
        var s = stat()
        guard url.withUnsafeFileSystemRepresentation({ lstat($0, &s) }) == 0 else { throw TriageError.changed }
        allocatedBytes = Int64(s.st_blocks) * 512
        kind = FileKind.classify(url)
    }
    public var name: String { url.lastPathComponent }
}

public struct ScanResult {
    public let files: [FileRecord]
    public let skipped: Int
    public let cancelled: Bool
}

public enum FileSafety {
    public static func root(_ url: URL) throws -> URL {
        let u = url.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard u.isFileURL, u.path != "/", FileManager.default.fileExists(atPath: u.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw TriageError.unsafePath }
        return u
    }
    public static func validate(_ record: FileRecord, root: URL) throws {
        let path = record.url.standardizedFileURL
        let prefix = root.standardizedFileURL.path + "/"
        guard path.path.hasPrefix(prefix), path.resolvingSymlinksInPath().path == path.path else { throw TriageError.unsafePath }
        guard try FileIdentity(url: path) == record.identity else { throw TriageError.changed }
    }
}

public enum Scanner {
    public static func scan(root: URL, token: CancellationToken, progress: (Int) -> Void = { _ in }) throws -> ScanResult {
        let root = try FileSafety.root(root)
        var files: [FileRecord] = []; var skipped = 0; var visited = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey, .isPackageKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in skipped += 1; return true }) else { throw TriageError.unsafePath }
        for case let url as URL in e {
            if token.isCancelled { return ScanResult(files: files, skipped: skipped, cancelled: true) }
            visited += 1
            if visited % 250 == 0 { progress(files.count) }
            do {
                let values = try url.resourceValues(forKeys: Set(keys))
                if values.isSymbolicLink == true || values.isPackage == true { e.skipDescendants(); skipped += 1; continue }
                if values.isDirectory == true { continue }
                guard values.isRegularFile == true else { continue }
                let r = try FileRecord(url: url)
                // Never load a file's contents during inventory. App databases are not browseable media.
                if ["sqlite","sqlite-wal","sqlite-shm","db","db-wal","db-shm","thumb","mmsthumb","favicon"].contains(url.pathExtension.lowercased()) { skipped += 1; continue }
                try FileSafety.validate(r, root: root)
                files.append(r)
            } catch { skipped += 1 }
        }
        files.sort { $0.allocatedBytes == $1.allocatedBytes ? $0.id < $1.id : $0.allocatedBytes > $1.allocatedBytes }
        progress(files.count)
        return ScanResult(files: files, skipped: skipped, cancelled: false)
    }
}
