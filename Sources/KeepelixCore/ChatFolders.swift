import Foundation

public enum ChatKind: String, CaseIterable {
    case group, personal, broadcast
}

/// WhatsApp for Mac keeps each chat's media in a folder named after the chat identifier.
/// Classification uses only those folder names; chat databases are never read, so contact and group names are not available.
public enum ChatFolders {
    public static func kind(of url: URL) -> ChatKind? {
        for component in url.deletingLastPathComponent().pathComponents {
            let c = component.lowercased()
            if c.hasSuffix("@g.us") { return .group }
            if c.hasSuffix("@s.whatsapp.net") || c.hasSuffix("@c.us") || c.hasSuffix("@lid") { return .personal }
            if c.hasSuffix("@broadcast") { return .broadcast }
        }
        return nil
    }
    public static func filter(_ files: [FileRecord], kind: ChatKind) -> [FileRecord] { files.filter { self.kind(of: $0.url) == kind } }
}
