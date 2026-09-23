import Foundation

/// A report that a Free up space verdict is wrong, prepared for a GitHub issue the user reviews and submits in their browser.
/// It names the catalogue entry or the pattern that matched, never a path with your own folder names in it.
public struct VerdictReport: Equatable {
    public enum Problem: String, CaseIterable {
        case notSafe = "Not safe to move: data would be lost"
        case couldBeSafe = "Could be marked safe: the app rebuilds it"
        case wrongDescription = "The description or next step is wrong"
        case other = "Something else"
    }
    public let title: String
    public let body: String

    public static let repository = "danielsimisi-coder/avakasha"
    /// The GitHub "new issue" page, prefilled. Opening it sends nothing; the user reads, edits and submits it there.
    public var url: URL {
        var c = URLComponents(string: "https://github.com/\(Self.repository)/issues/new")!
        c.queryItems = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "body", value: body)]
        return c.url!
    }

    /// The location as it may appear in a public report. Catalogue entries keep their fixed path; for folders found by searching,
    /// every component you named yourself becomes "…", keeping only Library's own structure and the name that matched.
    public static func publicPath(id: String, relativePath: String) -> String {
        guard id.hasPrefix("find.") else { return "~/" + relativePath }
        let parts = relativePath.split(separator: "/").map(String.init)
        guard let last = parts.last else { return "~/…" }
        var kept: [String] = []
        if parts.first == "Library", parts.count >= 2 {
            kept.append("Library")
            // Standard Library folders stay; the app folder beneath them is kept only for leftovers, where it is the point of the report.
            let standard: Set<String> = ["Application Support", "Caches", "Containers", "Group Containers", "Developer", "Logs"]
            if parts.count >= 3, standard.contains(parts[1]) { kept.append(parts[1]) }
        }
        let middleHidden = kept.count < parts.count - 1
        return "~/" + (kept + (middleHidden ? ["…"] : []) + [last]).joined(separator: "/")
    }

    public static func make(id: String, relativePath: String, verdict: String, detail: String, problem: Problem, comment: String,
                            appVersion: String, systemVersion: String) -> VerdictReport {
        let place = publicPath(id: id, relativePath: relativePath)
        let what = id.hasPrefix("find.") ? "a folder found by Find more (" + detail + ")" : "catalogue entry `" + id + "`"
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = """
        **Location:** `\(place)`
        **Entry:** \(what)
        **Avakasha says:** \(verdict)
        **What is wrong:** \(problem.rawValue)

        **Details:**
        \(trimmed.isEmpty ? "_(none given)_" : trimmed)

        ---
        Avakasha \(appVersion) · \(systemVersion)
        _Prepared by Avakasha. It contains no file names or paths from this Mac beyond what is shown above._
        """
        return VerdictReport(title: "[Verdict] " + place + ": " + problem.rawValue, body: body)
    }
}
