import Foundation

/// Why a folder was found. Each detector encodes one principle for finding space, independent of fixed paths.
public enum FindingKind: Equatable {
    /// The folder's name says it holds data its app or tool regenerates (caches, previews, build products, dependency folders).
    case regenerable(pattern: String)
    /// A data folder in the usual app-data places whose app is not installed.
    case leftover(owner: String)
    /// A large folder whose newest file is older than the cutoff; `months` is how long nothing inside changed.
    case untouched(months: Int)
}

/// One folder worth a look, with what the map measured. Only `.regenerable` findings are ever offered for Trash;
/// the rest are for review, because a folder that looks forgotten may still be someone's only copy.
public struct Finding: Equatable {
    public let url: URL
    public let bytes: Int64
    public let files: Int
    public let newestModified: Int64
    public let kind: FindingKind
    public var isRegenerable: Bool { if case .regenerable = kind { return true }; return false }
    /// Size weighted by how safe the step is, so a large forgotten folder can still outrank a small cache.
    public var score: Double {
        switch kind {
        case .regenerable: return Double(bytes)
        case .leftover: return Double(bytes) * 0.5
        case .untouched: return Double(bytes) * 0.3
        }
    }
}

/// An app found on this Mac: its display name and bundle identifier, read from its Info.plist.
public struct InstalledApp: Equatable {
    public let name: String
    public let bundleID: String
    public init(name: String, bundleID: String) { self.name = name; self.bundleID = bundleID }
}

public struct FindingOptions {
    public var minimumRegenerableBytes: Int64 = 50_000_000
    public var minimumLeftoverBytes: Int64 = 100_000_000
    public var minimumUntouchedBytes: Int64 = 1_000_000_000
    public var untouchedMonths = 6
    public var now = Date()
    public init() {}
}

public enum InstalledApps {
    /// The usual places apps live. Only app bundles' Info.plist files are read.
    public static func defaultRoots(home: URL) -> [URL] {
        ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            + [home.appendingPathComponent("Applications", isDirectory: true)]
    }
    /// Apps directly in each root and one folder deeper (vendors often install "Vendor App 2025/Vendor App.app").
    public static func scan(roots: [URL]) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        func add(_ url: URL) {
            guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) else { return }
            let id = info["CFBundleIdentifier"] as? String ?? ""
            let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
            apps.append(InstalledApp(name: name, bundleID: id))
            let file = url.deletingPathExtension().lastPathComponent
            if file != name { apps.append(InstalledApp(name: file, bundleID: id)) }
        }
        for root in roots {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { continue }
            for name in names where !name.hasPrefix(".") {
                let url = root.appendingPathComponent(name)
                if name.hasSuffix(".app") { add(url); continue }
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
                      (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                      let inner = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { continue }
                for app in inner where app.hasSuffix(".app") { add(url.appendingPathComponent(app)) }
            }
        }
        return apps
    }
    /// Whether a data folder's owner (a bundle identifier or an app or vendor name) matches an installed app.
    /// Deliberately generous: a doubtful match counts as installed, so fewer folders are called leftovers.
    public static func matches(_ owner: String, in apps: [InstalledApp]) -> Bool {
        func squash(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let lower = owner.lowercased()
        let parts = lower.split(separator: ".").map(String.init)
        if parts.count >= 2 {
            // Reverse-DNS: the same identifier, a helper of an installed app, or the same vendor (com.vendor.*).
            let vendor = parts.prefix(2).joined(separator: ".")
            return apps.contains { app in
                let id = app.bundleID.lowercased()
                return id == lower || lower.hasPrefix(id + ".") || id.hasPrefix(lower + ".") || (!id.isEmpty && id.split(separator: ".").prefix(2).joined(separator: ".") == vendor)
                    || squash(app.name) == squash(parts.last ?? "")
            }
        }
        let key = squash(owner)
        guard key.count >= 3 else { return true } // too short to judge: never call it a leftover
        return apps.contains { app in
            let name = squash(app.name)
            return name.contains(key) || (name.count >= 3 && key.contains(name)) || app.bundleID.lowercased().split(separator: ".").contains { squash(String($0)) == key }
        }
    }
}

/// Detectors over a storage map of the home folder. They read only what the map measured (names, sizes, newest file
/// times), never file contents, and they never act: the app decides what to offer and every move is confirmed.
public enum Findings {
    /// Folder names (lowercased) that hold regenerable data wherever they are: build products, dependency folders, editing previews.
    public static let regenerableNames: Set<String> = [
        "deriveddata", "node_modules", "__pycache__", "media cache", "media cache files", "peak files",
    ]
    // Dot-named build caches (.gradle, .next, .turbo, …) are left out on purpose: hidden folders are never moved whole.
    /// Generic cache names, trusted only inside Library, where apps keep them; in your own folders a "cache" might be anything.
    public static let libraryCacheNames: Set<String> = [
        "cache", "caches", "cacheddata", "cachedextensions", "code cache", "gpucache", "shadercache", "dawncache", "dawngraphitecache", "dawnwebgpucache", "grshadercache",
    ]
    /// Premiere and After Effects render folders: "Adobe Premiere Pro Audio Previews", "Adobe Premiere Pro Video Previews", "<project>.PRV".
    /// A plain "… Previews" folder may hold your own exports, so the name must also start with "Adobe ".
    public static func isAdobeRender(_ lower: String) -> Bool { (lower.hasPrefix("adobe ") && lower.hasSuffix(" previews")) || (lower.hasSuffix(".prv") && lower.count > 4) }

    public static func regenerablePattern(for name: String, inLibrary: Bool = true) -> String? {
        let lower = name.lowercased()
        if lower == "node_modules" { return inLibrary ? nil : lower } // in Library it is an installed tool or plugin (pnpm global, extensions)
        if regenerableNames.contains(lower) || (inLibrary && libraryCacheNames.contains(lower)) { return lower }
        return isAdobeRender(lower) ? "adobe render" : nil
    }

    /// Where data of removed apps usually stays, relative to the home folder.
    public static let leftoverParents = ["Library/Application Support", "Library/Containers", "Library/Group Containers", "Library/Caches", "Documents/Adobe"]
    /// Never looked into: cloud-synced folders (removing them removes them everywhere), Trash, and Apple's own data.
    static let skippedRelative = ["Library/Mobile Documents", "Library/CloudStorage", ".Trash", "Library/Caches", "Library/Mail", "Library/Messages", "Library/Photos", "Library/Metadata", "Pictures/Photos Library.photoslibrary"]

    /// The app name or bundle identifier a data folder most likely belongs to, or nil for Apple and system folders, which are never reported.
    public static func owner(ofFolderNamed name: String) -> String? {
        var n = name
        if n.lowercased().hasPrefix("group.") { n.removeFirst(6) }
        // Group Containers often start with a ten-character team identifier: "ABCDE12345.com.vendor.app".
        let parts = n.split(separator: ".", maxSplits: 1).map(String.init)
        if parts.count == 2, parts[0].count == 10, parts[0].allSatisfy({ $0.isUppercase || $0.isNumber }) { n = parts[1] }
        let lower = n.lowercased()
        if n.isEmpty || lower.hasPrefix(".") || lower.hasPrefix("com.apple") || lower.hasPrefix("apple") || systemFolderNames.contains(lower) { return nil }
        return n
    }
    static let systemFolderNames: Set<String> = [
        "addressbook", "callhistorydb", "callhistorytransactions", "clouddocs", "crashreporter", "knowledge", "icloud", "fileprovider", "dock",
        "syncservices", "mobilesync", "animoji", "facetime", "photos", "networkserviceproxy", "familycircle", "identityservices",
        "accounts", "containermanager", "homeenergyd", "diskimages", "coreparsec", "cloudkit", "siri", "icdd", "remindd", "quicklook",
        "sharedfilelist", "stickies", "passkit", "metadata", "unifiedassetframework", "geoservices", "dmfiles", "tipsd", "systemdata",
        "default", "caches", "libraries", "logs", "preferences", "cloudstorage", "mobile documents", "crashreports", "diagnosticreports",
        "keychains", "cookies", "webkit", "httpstorages", "autosave information", "savedapplicationstate", "fonts", "spelling", "assistants",
    ]

    /// Runs the three detectors. `installed` lists the apps on this Mac; `excluding` lists paths the curated catalogue
    /// already shows, and a finding at, inside or above one of them is dropped so nothing is counted twice.
    public static func detect(in map: StorageMapResult, installed: [InstalledApp], options: FindingOptions = FindingOptions(), excluding: [String] = []) -> [Finding] {
        let homePath = map.root.url.standardizedFileURL.path
        let covered = excluding.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        let skipped = Set(skippedRelative.map { homePath + "/" + $0 })
        func inside(_ path: String, _ list: [String]) -> Bool { list.contains { path == $0 || path.hasPrefix($0 + "/") } }
        func above(_ path: String, _ list: [String]) -> Bool { list.contains { $0.hasPrefix(path + "/") } }
        func isApple(_ node: StorageNode) -> Bool { node.name.lowercased().hasPrefix("com.apple.") || node.name.lowercased().hasPrefix("group.com.apple.") }
        func usable(_ node: StorageNode) -> Bool { !node.isPackage && !node.isUnreadable && !skipped.contains(node.url.standardizedFileURL.path) && !isApple(node) }
        func finding(_ node: StorageNode, _ kind: FindingKind) -> Finding {
            Finding(url: node.url, bytes: node.bytes, files: node.files, newestModified: node.newestModified, kind: kind)
        }
        var results: [Finding] = []
        var reported: [String] = []

        // 1. Regenerable by name; the top-most match stands for everything inside it. Folders under a hidden folder
        // (tool installs such as ~/.vscode or ~/.nvm; ~/Library carries the hidden flag but is searched) are left alone: a node_modules there is the tool itself.
        // A node_modules counts only beside a package.json, the sign of a project that can install it again.
        func walkRegenerable(_ node: StorageNode, hiddenAbove: Bool, inLibrary: Bool) {
            for child in node.children where usable(child) {
                let path = child.url.standardizedFileURL.path
                if !hiddenAbove, let pattern = regenerablePattern(for: child.name, inLibrary: inLibrary), child.bytes >= options.minimumRegenerableBytes, !child.hasCaveats,
                   !inside(path, covered), !above(path, covered),
                   pattern != "node_modules" || FileManager.default.fileExists(atPath: child.url.deletingLastPathComponent().appendingPathComponent("package.json").path) {
                    results.append(finding(child, .regenerable(pattern: pattern))); reported.append(path); continue
                }
                if child.bytes >= options.minimumRegenerableBytes, !inside(path, covered) {
                    walkRegenerable(child, hiddenAbove: hiddenAbove || (child.isHidden && path != homePath + "/Library"), inLibrary: inLibrary || path == homePath + "/Library")
                }
            }
        }
        walkRegenerable(map.root, hiddenAbove: false, inLibrary: false)

        // 2. Leftovers: data folders in the usual places whose app is not installed.
        func node(at relative: String) -> StorageNode? {
            var current = map.root
            for component in relative.split(separator: "/") {
                guard let next = current.children.first(where: { $0.name == String(component) }) else { return nil }
                current = next
            }
            return current
        }
        for parent in leftoverParents {
            guard let folder = node(at: parent) else { continue }
            for child in folder.children where !child.isPackage && !child.isUnreadable && child.bytes >= options.minimumLeftoverBytes {
                let path = child.url.standardizedFileURL.path
                guard !inside(path, reported), !above(path, reported), !inside(path, covered), !above(path, covered), let owner = owner(ofFolderNamed: child.name), !InstalledApps.matches(owner, in: installed) else { continue }
                results.append(finding(child, .leftover(owner: owner))); reported.append(path)
            }
        }

        // 3. Untouched: large visible folders outside Library whose newest file is older than the cutoff; top-most only.
        // The home folder's own top level (Documents, Desktop, …) is never reported whole; the search goes one level in.
        let cutoff = Int64((Calendar.current.date(byAdding: .month, value: -options.untouchedMonths, to: options.now) ?? options.now).timeIntervalSince1970)
        func walkUntouched(_ node: StorageNode, depth: Int) {
            for child in node.children where usable(child) && !child.isHidden && child.bytes >= options.minimumUntouchedBytes {
                let path = child.url.standardizedFileURL.path
                if path == homePath + "/Library" || inside(path, reported) || inside(path, covered) { continue }
                if depth > 0, child.newestModified > 0, child.newestModified < cutoff, !child.hasCaveats, !above(path, reported), !above(path, covered) {
                    let months = max(options.untouchedMonths, Calendar.current.dateComponents([.month], from: Date(timeIntervalSince1970: TimeInterval(child.newestModified)), to: options.now).month ?? 0)
                    results.append(finding(child, .untouched(months: months))); reported.append(path); continue
                }
                walkUntouched(child, depth: depth + 1)
            }
        }
        walkUntouched(map.root, depth: 0)

        return results.sorted { a, b in a.score == b.score ? a.url.path < b.url.path : a.score > b.score }
    }
}
