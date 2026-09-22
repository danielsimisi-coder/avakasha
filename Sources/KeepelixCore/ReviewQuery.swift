import Foundation

public enum ReviewSort: Int, CaseIterable {
    case largest, smallest, oldest, newest, name, nameDescending
}

/// Installer and archive families for the "Downloads quick clean" view. Classification is by file extension only;
/// it says nothing about whether the payload is still needed.
public enum InstallerKind: String, CaseIterable {
    case diskImage, package, archive
}

public enum ReviewQuery {
    public static func older(_ files: [FileRecord], than cutoff: Date) -> [FileRecord] {
        files.filter { Date(timeIntervalSince1970: Double($0.identity.modifiedSeconds)) < cutoff }
    }

    /// Classifies a URL by its last path extension, case-insensitively ("Setup.DMG", "backup.tar.gz" -> archive via "gz").
    /// Returns nil for anything that is not a disk image, installer package or archive, so callers never treat an
    /// unrecognised file as disposable.
    public static func installerKind(_ url: URL) -> InstallerKind? {
        switch url.pathExtension.lowercased() {
        case "dmg", "iso", "sparseimage": return .diskImage
        case "pkg", "mpkg", "xip": return .package
        case "zip", "tar", "gz", "tgz", "bz2", "xz", "rar", "7z": return .archive
        default: return nil
        }
    }

    /// Installer and archive files whose modification time is strictly before `cutoff`, in input order.
    /// Honesty rule: an installer is only disposable if the app is installed, and an archive only if it was extracted.
    /// The app cannot know either, so this query only surfaces candidates for review; the user decides what goes.
    public static func installers(_ files: [FileRecord], olderThan cutoff: Date) -> [FileRecord] {
        files.filter { installerKind($0.url) != nil && Date(timeIntervalSince1970: Double($0.identity.modifiedSeconds)) < cutoff }
    }

    public static func sorted(_ files: [FileRecord], by order: ReviewSort) -> [FileRecord] {
        files.sorted { a, b in
            switch order {
            case .largest, .smallest:
                if a.allocatedBytes != b.allocatedBytes {
                    return order == .largest ? a.allocatedBytes > b.allocatedBytes : a.allocatedBytes < b.allocatedBytes
                }
            case .oldest, .newest:
                if a.identity.modifiedSeconds != b.identity.modifiedSeconds {
                    return order == .oldest ? a.identity.modifiedSeconds < b.identity.modifiedSeconds : a.identity.modifiedSeconds > b.identity.modifiedSeconds
                }
            case .name, .nameDescending:
                let comparison = a.name.localizedStandardCompare(b.name)
                if comparison != .orderedSame { return order == .name ? comparison == .orderedAscending : comparison == .orderedDescending }
            }
            return a.id < b.id
        }
    }
}
