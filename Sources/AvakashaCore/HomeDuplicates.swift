import Foundation
import Darwin
import CryptoKit

/// Exact duplicates across the whole home folder: your own files, not app data. Library (which also holds iCloud Drive), hidden folders,
/// bundles (the Photos library, apps), Trash, cloud placeholders, links and other drives are never looked at. Only names and sizes are
/// read to find candidates; contents are read only for files that share a size and a quick head-and-tail fingerprint, and the final
/// verdict is the same full SHA-256 comparison the folder review uses.
public enum HomeDuplicates {
    public static let defaultMinimumBytes: Int64 = 1_000_000

    /// Regular files of at least `minimumBytes` whose size occurs more than once, found without reading any contents.
    public static func sameSizeFiles(in home: URL, minimumBytes: Int64 = defaultMinimumBytes, token: CancellationToken = CancellationToken(),
                                     progress: (Int) -> Void = { _ in }) throws -> [URL] {
        let root = try FileSafety.root(home).path
        var rootStat = stat(); guard stat(root, &rootStat) == 0 else { throw TriageError.inaccessible }
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(root), nil]
        defer { free(argv[0]) }
        guard let handle = argv.withUnsafeMutableBufferPointer({ fts_open($0.baseAddress, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil) }) else { throw TriageError.inaccessible }
        defer { fts_close(handle) }
        var bySize: [Int64: [URL]] = [:], seen = 0
        while let entry = fts_read(handle) {
            try token.check()
            let e = entry.pointee
            let name = String(cString: e.fts_path + Int(e.fts_pathlen) - Int(e.fts_namelen))
            switch Int32(e.fts_info) {
            case FTS_D:
                guard e.fts_level > 0 else { continue }
                let path = String(cString: e.fts_path)
                let skip = name.hasPrefix(".") || (e.fts_level == 1 && name == "Library")
                    || (!(name as NSString).pathExtension.isEmpty && ((try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false))
                    || (e.fts_statp.map { $0.pointee.st_flags & 0x8000 != 0 } ?? false) // UF_HIDDEN
                if skip { fts_set(handle, entry, FTS_SKIP) }
            case FTS_F:
                guard let s = e.fts_statp, !name.hasPrefix("."), s.pointee.st_flags & 0x40000000 == 0, s.pointee.st_flags & 0x8000 == 0 else { continue } // no dataless, no hidden
                let size = Int64(s.pointee.st_size)
                guard size >= minimumBytes else { continue }
                bySize[size, default: []].append(URL(fileURLWithPath: String(cString: e.fts_path)))
                seen += 1; if seen % 2000 == 0 { progress(seen) }
            default: continue // links, unreadable folders, special files
            }
        }
        return bySize.values.filter { $0.count > 1 }.flatMap { $0 }
    }

    /// SHA-256 of the first and last 64 KB with the size: different fingerprints mean different files, without reading the middle.
    static func fingerprint(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        var hash = SHA256(); hash.update(data: withUnsafeBytes(of: size) { Data($0) })
        try? handle.seek(toOffset: 0); hash.update(data: (try? handle.read(upToCount: 65_536)) ?? Data())
        if size > 131_072 { try? handle.seek(toOffset: size - 65_536); hash.update(data: (try? handle.read(upToCount: 65_536)) ?? Data()) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The full search: candidates by size, narrowed by fingerprint, confirmed by full SHA-256 (hard links are never counted as copies).
    public static func find(in home: URL, minimumBytes: Int64 = defaultMinimumBytes, token: CancellationToken = CancellationToken(),
                            progress: (String) -> Void = { _ in }) throws -> DuplicateResult {
        let root = try FileSafety.root(home)
        let sameSize = try sameSizeFiles(in: root, minimumBytes: minimumBytes, token: token) { progress("\($0)") }
        var byPrint: [String: [URL]] = [:]
        for (index, url) in sameSize.enumerated() {
            try token.check(); if index % 100 == 0 { progress("\(index)/\(sameSize.count)") }
            if let print = fingerprint(url) { byPrint[print, default: []].append(url) }
        }
        let candidates = byPrint.values.filter { $0.count > 1 }.flatMap { $0 }.compactMap { try? FileRecord(url: $0) }
        return try ExactDuplicates.find(candidates, root: root, token: token)
    }
    /// Space the extra copies take: every member but one per group.
    public static func extraBytes(_ groups: [DuplicateGroup]) -> Int64 { groups.reduce(0) { $0 + $1.extras.reduce(0) { $0 + $1.allocatedBytes } } }
}
