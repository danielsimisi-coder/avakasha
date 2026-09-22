import Foundation

/// How a known location can be emptied without losing anything the user made.
public enum CleanupSafety: String, CaseIterable {
    /// Caches and downloads the owning app recreates on demand. Contents can go to Trash from the app.
    case rebuildable
    /// The owning app has its own cleanup that keeps its bookkeeping consistent; use that, not the file system.
    case cleanInsideApp
    /// A developer tool must do it (simulators, package stores); the app shows the command to copy, it never runs it.
    case commandOnly
    /// Temporary system data that macOS clears on restart.
    case restartClears
    /// Personal or app data that only looks like clutter; review file by file or leave it alone.
    case keepOrReview
}

/// One place macOS lumps into "System Data" or hides in a dot folder. Paths are relative to the home folder;
/// nothing here is measured or listed until the user asks.
public struct KnownLocation: Equatable, Identifiable {
    public let id: String
    public let relativePath: String
    public let category: String
    public let safety: CleanupSafety
    /// Command to copy for `.commandOnly` entries; never executed by the app.
    public let command: String?
    public init(id: String, relativePath: String, category: String, safety: CleanupSafety, command: String? = nil) {
        self.id = id; self.relativePath = relativePath; self.category = category; self.safety = safety; self.command = command
    }
    public func url(home: URL) -> URL { home.appendingPathComponent(relativePath, isDirectory: true) }
}

public struct LocationMeasurement: Equatable {
    public let location: KnownLocation
    public let bytes: Int64
    public let files: Int
    public let cancelled: Bool
    public let error: String?
}

public enum KnownLocations {
    public static let developer = "developer", ai = "ai", apps = "apps", installers = "installers", messaging = "messaging", browser = "browser", system = "system", backups = "backups"

    /// Curated list. Ordered roughly by how much space they usually take on a developer's Mac.
    public static let all: [KnownLocation] = [
        KnownLocation(id: "xcode.simulators", relativePath: "Library/Developer/CoreSimulator/Devices", category: developer, safety: .commandOnly, command: "xcrun simctl delete unavailable"),
        KnownLocation(id: "xcode.simulatorCaches", relativePath: "Library/Developer/CoreSimulator/Caches", category: developer, safety: .rebuildable),
        KnownLocation(id: "xcode.deviceSupport", relativePath: "Library/Developer/Xcode/iOS DeviceSupport", category: developer, safety: .rebuildable),
        KnownLocation(id: "xcode.watchDeviceSupport", relativePath: "Library/Developer/Xcode/watchOS DeviceSupport", category: developer, safety: .rebuildable),
        KnownLocation(id: "xcode.derivedData", relativePath: "Library/Developer/Xcode/DerivedData", category: developer, safety: .rebuildable),
        KnownLocation(id: "xcode.archives", relativePath: "Library/Developer/Xcode/Archives", category: developer, safety: .keepOrReview),
        KnownLocation(id: "xcode.caches", relativePath: "Library/Caches/com.apple.dt.Xcode", category: developer, safety: .rebuildable),
        KnownLocation(id: "orbstack", relativePath: "OrbStack", category: developer, safety: .cleanInsideApp),
        KnownLocation(id: "orbstack.data", relativePath: ".orbstack", category: developer, safety: .cleanInsideApp),
        KnownLocation(id: "docker.vms", relativePath: "Library/Containers/com.docker.docker/Data/vms", category: developer, safety: .cleanInsideApp),
        KnownLocation(id: "npm.cache", relativePath: ".npm/_cacache", category: developer, safety: .commandOnly, command: "npm cache clean --force"),
        KnownLocation(id: "pnpm.store", relativePath: "Library/pnpm/store", category: developer, safety: .commandOnly, command: "pnpm store prune"),
        KnownLocation(id: "yarn.cache", relativePath: "Library/Caches/Yarn", category: developer, safety: .commandOnly, command: "yarn cache clean"),
        KnownLocation(id: "homebrew.cache", relativePath: "Library/Caches/Homebrew", category: developer, safety: .commandOnly, command: "brew cleanup --prune=all"),
        KnownLocation(id: "gradle.caches", relativePath: ".gradle/caches", category: developer, safety: .rebuildable),
        KnownLocation(id: "maven.repository", relativePath: ".m2/repository", category: developer, safety: .rebuildable),
        KnownLocation(id: "cocoapods.cache", relativePath: "Library/Caches/CocoaPods", category: developer, safety: .rebuildable),
        KnownLocation(id: "pip.cache", relativePath: "Library/Caches/pip", category: developer, safety: .commandOnly, command: "pip cache purge"),
        KnownLocation(id: "cargo.registry", relativePath: ".cargo/registry", category: developer, safety: .rebuildable),
        KnownLocation(id: "go.modcache", relativePath: "go/pkg/mod", category: developer, safety: .commandOnly, command: "go clean -modcache"),
        KnownLocation(id: "codex.cache", relativePath: ".codex", category: developer, safety: .keepOrReview),
        KnownLocation(id: "claude.vmBundles", relativePath: "Library/Application Support/Claude/vm_bundles", category: apps, safety: .rebuildable),
        KnownLocation(id: "ai.huggingface", relativePath: ".cache/huggingface", category: ai, safety: .rebuildable),
        KnownLocation(id: "ai.torch", relativePath: ".cache/torch", category: ai, safety: .rebuildable),
        KnownLocation(id: "ai.whisper", relativePath: ".cache/whisper", category: ai, safety: .rebuildable),
        KnownLocation(id: "ai.ollama", relativePath: ".ollama/models", category: ai, safety: .commandOnly, command: "ollama list   # then: ollama rm <model>"),
        KnownLocation(id: "adobe.common", relativePath: "Library/Application Support/Adobe/Common", category: apps, safety: .cleanInsideApp),
        KnownLocation(id: "adobe.installers", relativePath: "Library/Application Support/Adobe/Installers", category: installers, safety: .rebuildable),
        KnownLocation(id: "adobe.uxp", relativePath: "Library/Application Support/Adobe/UXP", category: apps, safety: .keepOrReview),
        KnownLocation(id: "wondershare.installer", relativePath: "Library/Application Support/com.wondershare.Installer", category: installers, safety: .rebuildable),
        KnownLocation(id: "quicklook.thumbnails", relativePath: "Library/Containers/com.apple.quicklook.QuickLookUIService/Data/Library/Caches", category: system, safety: .rebuildable),
        KnownLocation(id: "system.caches", relativePath: "Library/Caches", category: system, safety: .keepOrReview),
        KnownLocation(id: "system.logs", relativePath: "Library/Logs", category: system, safety: .rebuildable),
        KnownLocation(id: "system.tempFolders", relativePath: "../../private/var/folders", category: system, safety: .restartClears),
        KnownLocation(id: "chrome", relativePath: "Library/Application Support/Google/Chrome", category: browser, safety: .cleanInsideApp),
        KnownLocation(id: "chrome.cache", relativePath: "Library/Caches/Google/Chrome", category: browser, safety: .cleanInsideApp),
        KnownLocation(id: "safari.cache", relativePath: "Library/Caches/com.apple.Safari", category: browser, safety: .cleanInsideApp),
        KnownLocation(id: "whatsapp.media", relativePath: "Library/Group Containers/group.net.whatsapp.WhatsApp.shared/Message/Media", category: messaging, safety: .keepOrReview),
        KnownLocation(id: "messages.attachments", relativePath: "Library/Messages/Attachments", category: messaging, safety: .cleanInsideApp),
        KnownLocation(id: "mail", relativePath: "Library/Mail", category: messaging, safety: .cleanInsideApp),
        KnownLocation(id: "iphone.backups", relativePath: "Library/Application Support/MobileSync/Backup", category: backups, safety: .cleanInsideApp),
        KnownLocation(id: "spotify.cache", relativePath: "Library/Caches/com.spotify.client", category: apps, safety: .rebuildable),
        KnownLocation(id: "slack.cache", relativePath: "Library/Application Support/Slack/Cache", category: apps, safety: .rebuildable),
        KnownLocation(id: "teams.cache", relativePath: "Library/Containers/com.microsoft.teams2/Data/Library/Caches", category: apps, safety: .rebuildable),
        KnownLocation(id: "zoom.data", relativePath: "Library/Application Support/zoom.us", category: apps, safety: .keepOrReview),
        KnownLocation(id: "trash", relativePath: ".Trash", category: system, safety: .cleanInsideApp),
    ]

    /// Entries whose folder exists under `home` (a plain directory, never a link). Nothing inside is read.
    public static func present(in home: URL) -> [KnownLocation] {
        all.filter { location in
            let url = location.url(home: home).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
            return (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
        }
    }

    /// Each app's own cache folder under Library/Caches that is not already a curated entry. Names are bundle identifiers, not personal data.
    public static func cacheFolders(in home: URL) -> [KnownLocation] {
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: caches.path) else { return [] }
        let curated = Set(all.map { $0.relativePath })
        return names.sorted().compactMap { name in
            let relative = "Library/Caches/" + name
            guard !name.hasPrefix("."), !curated.contains(relative) else { return nil }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: caches.appendingPathComponent(name).path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
            return KnownLocation(id: "cache." + name, relativePath: relative, category: apps, safety: .rebuildable)
        }
    }

    /// Measures one location with the storage-map walker (allocated bytes, no file contents, cancellable).
    public static func measure(_ location: KnownLocation, home: URL, token: CancellationToken) -> LocationMeasurement {
        do {
            let result = try StorageMapper.map(root: location.url(home: home), token: token, limit: 0)
            return LocationMeasurement(location: location, bytes: result.root.bytes, files: result.root.files, cancelled: result.cancelled, error: nil)
        } catch {
            return LocationMeasurement(location: location, bytes: 0, files: 0, cancelled: false, error: error.localizedDescription)
        }
    }
}
