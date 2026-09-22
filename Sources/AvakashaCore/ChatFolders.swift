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

import SQLite3

public struct ChatInfo: Equatable {
    public let identifier: String
    public let name: String
    public let kind: ChatKind
    public init(identifier: String, name: String, kind: ChatKind) { self.identifier = identifier; self.name = name; self.kind = kind }
}

public enum ChatDirectoryError: Error, LocalizedError, Equatable {
    case cannotOpen(String), unexpectedSchema
    public var errorDescription: String? {
        switch self {
        case .cannotOpen(let m): return "The WhatsApp chat list could not be opened read-only: " + m
        case .unexpectedSchema: return "The WhatsApp chat list has a layout this version does not recognise. Folder identifiers stay in use."
        }
    }
}

/// Explicit, opt-in lookup of chat display names. Reads one table of WhatsApp's local database, read-only:
/// chat identifier, display name and session type. Messages, contacts and media references are never read; nothing is stored.
public enum ChatDirectory {
    public static let databaseName = "ChatStorage.sqlite"

    /// The WhatsApp container holds `Message/Media`; walk up a few levels from any reviewed folder to find its chat list.
    public static func databaseURL(near root: URL) -> URL? {
        var folder = root.standardizedFileURL
        for _ in 0..<8 {
            let candidate = folder.appendingPathComponent(databaseName)
            if FileManager.default.isReadableFile(atPath: candidate.path) { return candidate }
            let parent = folder.deletingLastPathComponent()
            if parent.path == folder.path { break }
            folder = parent
        }
        return nil
    }

    /// The folder identifier WhatsApp uses for a file's chat, or nil outside chat folders.
    public static func identifier(of url: URL) -> String? {
        for component in url.deletingLastPathComponent().pathComponents where ChatFolders.kind(of: URL(fileURLWithPath: "/" + component + "/x")) != nil { return component.lowercased() }
        return nil
    }

    /// Returns chats keyed by lowercased identifier. Opens read-only; falls back to an immutable open when the write-ahead log cannot be attached.
    public static func load(from database: URL) throws -> [String: ChatInfo] {
        var handle: OpaquePointer?
        var rc = sqlite3_open_v2(database.path, &handle, SQLITE_OPEN_READONLY, nil)
        if rc != SQLITE_OK {
            sqlite3_close(handle); handle = nil
            let uri = "file:" + database.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)! + "?immutable=1"
            rc = sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        }
        guard rc == SQLITE_OK, let db = handle else { let m = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(rc)"; sqlite3_close(handle); throw ChatDirectoryError.cannotOpen(m) }
        defer { sqlite3_close(db) }
        var columns = Set<String>()
        var pragma: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(ZWACHATSESSION)", -1, &pragma, nil) == SQLITE_OK else { throw ChatDirectoryError.unexpectedSchema }
        while sqlite3_step(pragma) == SQLITE_ROW { if let c = sqlite3_column_text(pragma, 1) { columns.insert(String(cString: c).uppercased()) } }
        sqlite3_finalize(pragma)
        guard columns.isSuperset(of: ["ZCONTACTJID", "ZPARTNERNAME"]) else { throw ChatDirectoryError.unexpectedSchema }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT ZCONTACTJID, ZPARTNERNAME FROM ZWACHATSESSION WHERE ZCONTACTJID IS NOT NULL", -1, &statement, nil) == SQLITE_OK else { throw ChatDirectoryError.unexpectedSchema }
        defer { sqlite3_finalize(statement) }
        var chats: [String: ChatInfo] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let jid = sqlite3_column_text(statement, 0) else { continue }
            let identifier = String(cString: jid).lowercased()
            guard let kind = ChatFolders.kind(of: URL(fileURLWithPath: "/" + identifier + "/x")) else { continue }
            let name = sqlite3_column_text(statement, 1).map { String(cString: $0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            chats[identifier] = ChatInfo(identifier: identifier, name: name.isEmpty ? identifier : name, kind: kind)
        }
        return chats
    }
}
