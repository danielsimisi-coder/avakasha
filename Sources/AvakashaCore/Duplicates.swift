import Foundation
import Darwin
import CryptoKit
import ImageIO
import CoreGraphics

public struct DuplicateGroup {
    public let members: [FileRecord]
    public let anchor: FileRecord
    public init(members: [FileRecord]) { self.anchor = members[0]; self.members = members.sorted { $0.id < $1.id } }
    public var keeper: FileRecord { members[0] }
    public var extras: [FileRecord] { Array(members.dropFirst()) }
}
public struct DuplicateResult { public let groups: [DuplicateGroup]; public let skipped: Int }

public enum ExactDuplicates {
    public static func digest(_ file: FileRecord, root: URL, token: CancellationToken) throws -> String {
        try FileSafety.validate(file, root: root)
        let handle = try FileHandle(forReadingFrom: file.url); defer { try? handle.close() }
        var hash = SHA256()
        while true {
            try token.check()
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }; hash.update(data: data)
        }
        try FileSafety.validate(file, root: root)
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func find(_ files: [FileRecord], root: URL, token: CancellationToken,
                            progress: (Int, Int) -> Void = { _, _ in }) throws -> DuplicateResult {
        let bySize = Dictionary(grouping: files.filter { $0.identity.size > 0 }, by: { $0.identity.size })
        let candidates = bySize.values.filter { $0.count > 1 }.flatMap { $0 }
        var hashed: [String: [FileRecord]] = [:]; var skipped = 0
        var inodes = Set<String>()
        for (index, file) in candidates.enumerated() {
            try token.check(); progress(index + 1, candidates.count)
            // Hard links share data. Do not suggest them as separately reclaimable copies.
            let inodeKey = "\(file.identity.device):\(file.identity.inode)"
            if !inodes.insert(inodeKey).inserted { continue }
            do { let digest = try digest(file, root: root, token: token); hashed[digest, default: []].append(file) }
            catch TriageError.cancelled { throw TriageError.cancelled }
            catch { skipped += 1 }
        }
        let groups = hashed.values.filter { $0.count > 1 }.map { DuplicateGroup(members: $0) }
            .sorted { $0.keeper.identity.size > $1.keeper.identity.size }
        return DuplicateResult(groups: groups, skipped: skipped)
    }
    /// Include extended attributes/resource forks; conservatively skip unreadable or large metadata.
    public static func safeToAutoSelect(_ a: FileRecord, _ b: FileRecord) -> Bool {
        func attributes(_ f: FileRecord) -> [String: Data]? {
            let count = f.url.withUnsafeFileSystemRepresentation { listxattr($0,nil,0,XATTR_NOFOLLOW) }
            guard count >= 0, count < 1_000_000 else { return nil }
            if count == 0 { return [:] }
            var names = [CChar](repeating:0,count:count)
            guard f.url.withUnsafeFileSystemRepresentation({ listxattr($0,&names,count,XATTR_NOFOLLOW) }) == count else { return nil }
            var result: [String:Data] = [:]
            for bytes in names.split(separator:0) {
                let name = String(decoding:bytes.map{UInt8(bitPattern:$0)},as:UTF8.self)
                let size = f.url.withUnsafeFileSystemRepresentation { getxattr($0,name,nil,0,0,XATTR_NOFOLLOW) }
                guard size >= 0, size <= 32_000_000 else { return nil }
                var data = Data(count:size)
                let read = data.withUnsafeMutableBytes { buffer in f.url.withUnsafeFileSystemRepresentation { getxattr($0,name,buffer.baseAddress,size,0,XATTR_NOFOLLOW) } }
                guard read == size else { return nil }; result[name] = data
            }
            return result
        }
        guard let ax = attributes(a), let bx = attributes(b), ax == bx,
              let aa = try? FileManager.default.attributesOfItem(atPath:a.id), let bb = try? FileManager.default.attributesOfItem(atPath:b.id) else { return false }
        // ACL-bearing files require manual review, even if their data forks match.
        for file in [a,b] {
            guard let acl = acl_get_file(file.id, ACL_TYPE_EXTENDED) else { if errno == ENOENT { continue }; return false }
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            var entry: acl_entry_t?
            guard acl_valid(acl) == 0, acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) == -1, errno == EINVAL else { return false }
        }
        return (aa[.posixPermissions] as? NSNumber) == (bb[.posixPermissions] as? NSNumber)
    }
    public static func selectExtras(_ groups: [DuplicateGroup], visible: Set<String>) -> (ids: Set<String>, keepers: [String: FileRecord]) {
        var ids = Set<String>(); var keepers: [String: FileRecord] = [:]
        for group in groups {
            for file in group.extras where visible.contains(file.id) && safeToAutoSelect(file, group.keeper) { ids.insert(file.id); keepers[file.id] = group.keeper }
        }
        return (ids, keepers)
    }
}

public struct ImageFingerprint {
    public let bits: UInt64
    public let aspect: Double
    public init(bits: UInt64, aspect: Double) { self.bits = bits; self.aspect = aspect }
    public func resembles(_ other: ImageFingerprint, distance: Int = 5) -> Bool {
        abs(aspect - other.aspect) / max(aspect, other.aspect) < 0.04 && (bits ^ other.bits).nonzeroBitCount <= distance
    }
}
public enum SimilarImages {
    /// Local 64-bit difference hash. A suggestion, never a proof that a picture is disposable.
    public static func fingerprint(_ file: FileRecord, root: URL) throws -> ImageFingerprint? {
        try FileSafety.validate(file, root: root)
        guard file.kind == .image, file.identity.size <= 100_000_000,
              let source = CGImageSourceCreateWithURL(file.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue * height.doubleValue <= 100_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 128,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        var pixels = [UInt8](repeating: 0, count: 72)
        let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let c = CGContext(data: buffer.baseAddress, width: 9, height: 8, bitsPerComponent: 8, bytesPerRow: 9,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            c.interpolationQuality = .high; c.draw(image, in: CGRect(x: 0, y: 0, width: 9, height: 8)); return true
        }
        guard ok else { return nil }
        var bits: UInt64 = 0
        for y in 0..<8 { for x in 0..<8 { if pixels[y*9+x] > pixels[y*9+x+1] { bits |= UInt64(1) << (y*8+x) } } }
        try FileSafety.validate(file, root: root)
        return ImageFingerprint(bits: bits, aspect: Double(image.width) / Double(image.height))
    }
    public static func find(_ files: [FileRecord], root: URL, token: CancellationToken,
                            progress: (Int, Int) -> Void = { _, _ in }) throws -> DuplicateResult {
        let images = files.filter { $0.kind == .image }; var anchors: [ImageFingerprint] = []
        var groups: [[FileRecord]] = []; var buckets: [UInt16: [Int]] = [:]; var skipped = 0
        for (index, file) in images.enumerated() {
            try token.check(); progress(index+1, images.count)
            do {
                guard let fp = try fingerprint(file, root: root) else { skipped += 1; continue }
                // With <=5 differing bits, at least one of the eight byte bands is identical.
                let keys = (0..<8).map { UInt16($0 << 8) | UInt16((fp.bits >> ($0*8)) & 255) }
                let candidates = Set(keys.flatMap { buckets[$0] ?? [] })
                if let group = candidates.sorted().first(where: { anchors[$0].resembles(fp) }) {
                    groups[group].append(file)
                } else {
                    let group = groups.count; groups.append([file]); anchors.append(fp)
                    for key in keys { buckets[key, default: []].append(group) }
                }
            } catch { skipped += 1 }
        }
        return DuplicateResult(groups: groups.filter { $0.count > 1 }.map { DuplicateGroup(members: $0) }, skipped: skipped)
    }
}
