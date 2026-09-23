import Foundation
import CryptoKit
import Darwin

/// Why a folder was not moved to a drive. Nothing is lost in any of these cases: the original stays where it was.
public enum OffloadError: Error, Equatable {
    /// A link, a device, a socket or another special item that cannot be copied faithfully.
    case unsupportedItem(String)
    /// Not downloaded, unreadable, or on another drive inside the folder.
    case notFullyLocal(String)
    case sameDrive
    case notEnoughSpace(needed: Int64, available: Int64)
    case copyFailed(String)
    /// A copy did not match its original byte for byte.
    case verifyFailed(String)
    /// The folder changed while it was being copied.
    case sourceChanged
    case cancelled
    case manifestMissing
}

/// Everything in a folder, as found before copying: relative paths, sizes and modification times. Used to prove the folder did not change.
public struct OffloadInventory: Equatable {
    public struct File: Equatable { public let path: String; public let size: Int64; public let modified: Int64; public let modifiedNanos: Int64 }
    public let directories: [String]
    public let files: [File]
    public var bytes: Int64 { files.reduce(0) { $0 + $1.size } }
}

/// Written next to the copy on the drive, so the copy explains itself and can be checked again later, with or without Avakasha.
public struct OffloadManifest: Codable, Equatable {
    public struct Entry: Codable, Equatable { public let path: String; public let size: Int64; public let sha256: String }
    public var version = 1
    public let originalPath: String
    public let created: Date
    public let directories: [String]
    public let files: [Entry]
    public var bytes: Int64 { files.reduce(0) { $0 + $1.size } }
    public static let fileName = "Avakasha manifest.json"
}

/// One folder moved to a drive: where it was, where the verified copy is, and whether it was brought back.
public struct OffloadRecord: Codable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let originalPath: String
    public let destinationPath: String
    public let volumeName: String
    public let volumeUUID: String?
    public let date: Date
    public let bytes: Int64
    public let files: Int
    public var broughtBackTo: String?
    public init(id: UUID = UUID(), name: String, originalPath: String, destinationPath: String, volumeName: String, volumeUUID: String?, date: Date, bytes: Int64, files: Int, broughtBackTo: String? = nil) {
        self.id = id; self.name = name; self.originalPath = originalPath; self.destinationPath = destinationPath; self.volumeName = volumeName
        self.volumeUUID = volumeUUID; self.date = date; self.bytes = bytes; self.files = files; self.broughtBackTo = broughtBackTo
    }
    /// The copy is reachable: its drive is connected and the manifest is there.
    public var isAvailable: Bool { FileManager.default.fileExists(atPath: URL(fileURLWithPath: destinationPath).appendingPathComponent(OffloadManifest.fileName).path) }
}

public enum OffloadIndex {
    public static func load(from url: URL) -> [OffloadRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        if let records = try? decoder.decode([OffloadRecord].self, from: data) { return records }
        // A damaged list is set aside, never overwritten, so its paths can still be read by hand.
        let aside = url.deletingPathExtension().appendingPathExtension("damaged-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: url, to: aside)
        return []
    }
    public static func save(_ records: [OffloadRecord], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: url, options: .atomic)
    }
}

/// Copies a folder to another drive, verifies every file against its original with SHA-256, and proves the original did not change.
/// It never touches the original: moving it to Trash afterwards is the caller's step, through the usual guarded folder move.
public enum Offloader {
    public static let folderName = "Avakasha Offload"

    /// Walks the folder without following links. Regular files and folders only; anything else stops the offload before a byte is copied.
    public static func inventory(of folder: URL, token: CancellationToken = CancellationToken(), allowManifest: Bool = false) throws -> OffloadInventory {
        let root = folder.standardizedFileURL.path
        var rootStat = stat()
        guard lstat(root, &rootStat) == 0, rootStat.st_mode & S_IFMT == S_IFDIR else { throw OffloadError.unsupportedItem(folder.lastPathComponent) }
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(root), nil]
        defer { free(argv[0]) }
        guard let handle = argv.withUnsafeMutableBufferPointer({ fts_open($0.baseAddress, FTS_PHYSICAL | FTS_NOCHDIR, nil) }) else { throw OffloadError.notFullyLocal(folder.lastPathComponent) }
        defer { fts_close(handle) }
        var directories: [String] = [], files: [OffloadInventory.File] = []
        func relative(_ path: String) -> String { path == root ? "" : String(path.dropFirst(root.count + 1)) }
        while let entry = fts_read(handle) {
            if token.isCancelled { throw OffloadError.cancelled }
            let e = entry.pointee, path = String(cString: e.fts_path), rel = relative(path)
            switch Int32(e.fts_info) {
            case FTS_D:
                guard let s = e.fts_statp else { continue }
                if s.pointee.st_dev != rootStat.st_dev || s.pointee.st_flags & 0x40000000 != 0 { throw OffloadError.notFullyLocal(rel) } // another drive, or a folder not downloaded
                if !rel.isEmpty { directories.append(rel) }
            case FTS_DP: continue
            case FTS_F:
                guard let s = e.fts_statp else { continue }
                if s.pointee.st_flags & 0x40000000 != 0 { throw OffloadError.notFullyLocal(rel) } // SF_DATALESS: a cloud placeholder
                files.append(OffloadInventory.File(path: rel, size: Int64(s.pointee.st_size), modified: Int64(s.pointee.st_mtimespec.tv_sec), modifiedNanos: Int64(s.pointee.st_mtimespec.tv_nsec)))
            case FTS_DNR, FTS_ERR, FTS_NS: throw OffloadError.notFullyLocal(rel.isEmpty ? folder.lastPathComponent : rel)
            default: throw OffloadError.unsupportedItem(rel) // symbolic links, sockets, devices: not copied, so the folder is not offloaded
            }
        }
        // The copy's manifest sits at its top level; an item with that name (in any letter case) would be replaced by it.
        if !allowManifest, let clash = (files.map(\.path) + directories).first(where: { !$0.contains("/") && $0.lowercased() == OffloadManifest.fileName.lowercased() }) { throw OffloadError.unsupportedItem(clash) }
        return OffloadInventory(directories: directories.sorted(), files: files.sorted { $0.path < $1.path })
    }

    public static func sha256(of url: URL, token: CancellationToken = CancellationToken(), progress: (Int64) -> Void = { _ in }) throws -> String {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { throw OffloadError.copyFailed(url.lastPathComponent) }
        defer { try? handle.close() }
        var hash = SHA256()
        while true {
            if token.isCancelled { throw OffloadError.cancelled }
            let chunk = try handle.read(upToCount: 4 << 20) ?? Data()
            if chunk.isEmpty { break }
            hash.update(data: chunk); progress(Int64(chunk.count))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// A folder name on the drive that does not exist yet: "Old project", then "Old project 2", and so on.
    public static func freeDestination(for name: String, in parent: URL) -> URL {
        var candidate = parent.appendingPathComponent(name, isDirectory: true), n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(name) \(n)", isDirectory: true); n += 1
        }
        return candidate
    }

    /// A hidden working name no one else uses; only a folder this call created under it is ever removed.
    static func partialName(for final: URL) -> URL {
        final.deletingLastPathComponent().appendingPathComponent("." + final.lastPathComponent + "." + UUID().uuidString + ".avakasha-partial", isDirectory: true)
    }
    /// Copies `source` into `parent` (on another drive unless `allowSameDrive`, which only tests use) and verifies it.
    /// The copy is built under a hidden ".partial" name and renamed only once every file matched; on any failure the partial copy is removed
    /// (it is Avakasha's own, seconds old) and the original is untouched. Returns the verified copy and its manifest.
    public static func copy(_ source: URL, into parent: URL, allowSameDrive: Bool = false, token: CancellationToken = CancellationToken(),
                            progress: (_ done: Int64, _ total: Int64) -> Void = { _, _ in }) throws -> (folder: URL, manifest: OffloadManifest, inventory: OffloadInventory) {
        let before = try inventory(of: source, token: token)
        var sourceStat = stat(), parentStat = stat()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        guard stat(source.path, &sourceStat) == 0, stat(parent.path, &parentStat) == 0 else { throw OffloadError.copyFailed(parent.path) }
        if !allowSameDrive, sourceStat.st_dev == parentStat.st_dev { throw OffloadError.sameDrive }
        let available = (try? parent.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity).flatMap { $0.map(Int64.init) } ?? 0
        let needed = before.bytes + before.bytes / 20 + 200_000_000 // 5% and 200 MB to spare
        if available < needed { throw OffloadError.notEnoughSpace(needed: needed, available: available) }

        let final = freeDestination(for: source.lastPathComponent, in: parent)
        let partial = partialName(for: final)
        let total = before.bytes * 3 // read to hash, copy, read the copy to hash
        var done: Int64 = 0
        var own: URL? = nil // the folder this call created, under its working name and then its final one; the only thing ever removed
        do {
            try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: false); own = partial
            for dir in before.directories { try FileManager.default.createDirectory(at: partial.appendingPathComponent(dir, isDirectory: true), withIntermediateDirectories: true) }
            var entries: [OffloadManifest.Entry] = []
            for file in before.files {
                let from = source.appendingPathComponent(file.path), to = partial.appendingPathComponent(file.path)
                let original = try sha256(of: from, token: token) { done += $0; progress(done, total) }
                guard copyfile(from.path, to.path, nil, copyfile_flags_t(COPYFILE_ALL | COPYFILE_NOFOLLOW | COPYFILE_EXCL)) == 0 else { throw OffloadError.copyFailed(file.path) }
                done += file.size; progress(done, total)
                let copied = try sha256(of: to, token: token) { done += $0; progress(done, total) }
                guard copied == original else { throw OffloadError.verifyFailed(file.path) }
                var s = stat()
                guard lstat(from.path, &s) == 0, Int64(s.st_size) == file.size, Int64(s.st_mtimespec.tv_sec) == file.modified, Int64(s.st_mtimespec.tv_nsec) == file.modifiedNanos else { throw OffloadError.sourceChanged }
                entries.append(OffloadManifest.Entry(path: file.path, size: file.size, sha256: original))
            }
            // Folder dates last, after their contents stopped changing.
            for dir in before.directories.reversed() { _ = copyfile(source.appendingPathComponent(dir).path, partial.appendingPathComponent(dir).path, nil, copyfile_flags_t(COPYFILE_METADATA | COPYFILE_NOFOLLOW)) }
            let manifest = OffloadManifest(originalPath: source.standardizedFileURL.path, created: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)), directories: before.directories, files: entries)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: partial.appendingPathComponent(OffloadManifest.fileName), options: .atomic)
            // The original must be exactly as inventoried before anything else happens to it.
            guard try inventory(of: source, token: token) == before else { throw OffloadError.sourceChanged }
            try FileManager.default.moveItem(at: partial, to: final); own = final
            // After the rename: the manifest reads back and every file it lists is on the drive at its size.
            guard try checkShape(final) == manifest else { throw OffloadError.verifyFailed(final.lastPathComponent) }
            return (final, manifest, before)
        } catch {
            if let own { try? FileManager.default.removeItem(at: own) }
            if let offload = error as? OffloadError { throw offload }
            throw OffloadError.copyFailed(error.localizedDescription)
        }
    }

    public static func readManifest(_ copy: URL) throws -> OffloadManifest {
        guard let data = try? Data(contentsOf: copy.appendingPathComponent(OffloadManifest.fileName)) else { throw OffloadError.manifestMissing }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(OffloadManifest.self, from: data) else { throw OffloadError.manifestMissing }
        // Every path stays inside the copy: no "..", no absolute paths.
        for path in manifest.files.map(\.path) + manifest.directories where path.isEmpty || path.hasPrefix("/") || path.split(separator: "/").contains("..") { throw OffloadError.verifyFailed(path) }
        return manifest
    }
    /// Without reading contents: the manifest is readable and every listed file and folder is there, each file at its size.
    /// Anything extra is ignored: macOS adds ".DS_Store" and, on exFAT or FAT drives, "._" files that hold metadata, and Bring Back
    /// copies only what the manifest lists.
    public static func checkShape(_ copy: URL) throws -> OffloadManifest {
        let manifest = try readManifest(copy)
        var isDirectory: ObjCBool = false
        for entry in manifest.files {
            let url = copy.appendingPathComponent(entry.path)
            guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber, size.int64Value == entry.size,
                  (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw OffloadError.verifyFailed(entry.path) }
        }
        for dir in manifest.directories where !(FileManager.default.fileExists(atPath: copy.appendingPathComponent(dir).path, isDirectory: &isDirectory) && isDirectory.boolValue) {
            throw OffloadError.verifyFailed(dir)
        }
        return manifest
    }
    /// Checks a copy on the drive against its manifest: every file present, same size, same SHA-256, and nothing missing.
    public static func verify(_ copy: URL, token: CancellationToken = CancellationToken(), progress: (Int64) -> Void = { _ in }) throws -> OffloadManifest {
        let manifest = try checkShape(copy)
        for entry in manifest.files {
            let url = copy.appendingPathComponent(entry.path)
            guard (try? sha256(of: url, token: token, progress: progress)) == entry.sha256 else { throw token.isCancelled ? OffloadError.cancelled : OffloadError.verifyFailed(entry.path) }
        }
        return manifest
    }

    /// Copies a verified copy back to `target` (which must not exist yet), checking every file against the manifest.
    /// The copy on the drive is left in place.
    public static func bringBack(_ copy: URL, to target: URL, token: CancellationToken = CancellationToken(), progress: (_ done: Int64, _ total: Int64) -> Void = { _, _ in }) throws {
        let manifest = try verify(copy, token: token)
        guard !FileManager.default.fileExists(atPath: target.path) else { throw OffloadError.copyFailed(target.path) }
        let partial = partialName(for: target)
        let total = manifest.bytes * 2
        var done: Int64 = 0, created = false
        do {
            try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: false); created = true
            for dir in manifest.directories { try FileManager.default.createDirectory(at: partial.appendingPathComponent(dir, isDirectory: true), withIntermediateDirectories: true) }
            for entry in manifest.files {
                if token.isCancelled { throw OffloadError.cancelled }
                let from = copy.appendingPathComponent(entry.path), to = partial.appendingPathComponent(entry.path)
                guard copyfile(from.path, to.path, nil, copyfile_flags_t(COPYFILE_ALL | COPYFILE_NOFOLLOW | COPYFILE_EXCL)) == 0 else { throw OffloadError.copyFailed(entry.path) }
                done += entry.size; progress(done, total)
                guard try sha256(of: to, token: token, progress: { done += $0; progress(done, total) }) == entry.sha256 else { throw OffloadError.verifyFailed(entry.path) }
            }
            for dir in manifest.directories.reversed() { _ = copyfile(copy.appendingPathComponent(dir).path, partial.appendingPathComponent(dir).path, nil, copyfile_flags_t(COPYFILE_METADATA | COPYFILE_NOFOLLOW)) }
            try FileManager.default.moveItem(at: partial, to: target); created = false
        } catch {
            if created { try? FileManager.default.removeItem(at: partial) }
            if let offload = error as? OffloadError { throw offload }
            throw OffloadError.copyFailed(error.localizedDescription)
        }
    }

    /// Whether the folder still matches what was copied (paths, sizes and modification times). nil when it cannot be read, for example
    /// inside Trash, which macOS may keep private from apps.
    public static func matches(_ folder: URL, _ expected: OffloadInventory) -> Bool? { (try? inventory(of: folder)).map { $0 == expected } }

    /// Where to put something brought back: the original place if it is free, otherwise "<name> (brought back)" beside it.
    public static func bringBackTarget(for record: OffloadRecord) -> URL {
        let original = URL(fileURLWithPath: record.originalPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: original.path) else { return original }
        return freeDestination(for: original.lastPathComponent + " (brought back)", in: original.deletingLastPathComponent())
    }
}
