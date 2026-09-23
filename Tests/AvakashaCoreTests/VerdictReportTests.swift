import XCTest
@testable import AvakashaCore

final class VerdictReportTests: XCTestCase {
    func testPublicPathsHideYourOwnFolderNames() {
        XCTAssertEqual(VerdictReport.publicPath(id: "xcode.derivedData", relativePath: "Library/Developer/Xcode/DerivedData"), "~/Library/Developer/Xcode/DerivedData")
        XCTAssertEqual(VerdictReport.publicPath(id: "cache.com.vendor.app", relativePath: "Library/Caches/com.vendor.app"), "~/Library/Caches/com.vendor.app")
        XCTAssertEqual(VerdictReport.publicPath(id: "find.Clients/Acme Secret/web/node_modules", relativePath: "Clients/Acme Secret/web/node_modules"), "~/…/node_modules")
        XCTAssertEqual(VerdictReport.publicPath(id: "find.Library/Application Support/Chat/Code Cache", relativePath: "Library/Application Support/Chat/Code Cache"), "~/Library/Application Support/…/Code Cache")
        XCTAssertEqual(VerdictReport.publicPath(id: "find.Library/Application Support/OldEditor", relativePath: "Library/Application Support/OldEditor"), "~/Library/Application Support/OldEditor", "A leftover names the app it came from")
        XCTAssertEqual(VerdictReport.publicPath(id: "find.Movies/Wedding/Adobe Premiere Pro Audio Previews", relativePath: "Movies/Wedding/Adobe Premiere Pro Audio Previews"), "~/…/Adobe Premiere Pro Audio Previews")
    }
    func testReportCarriesNoPersonalPath() {
        let r = VerdictReport.make(id: "find.Clients/Acme Secret/web/node_modules", relativePath: "Clients/Acme Secret/web/node_modules", verdict: "Rebuildable · can go to Trash",
                                   detail: "node_modules", problem: .notSafe, comment: "  It holds patched packages.  ", appVersion: "0.1.0 beta 18", systemVersion: "macOS 26.0")
        for text in [r.title, r.body, r.url.absoluteString.removingPercentEncoding ?? ""] {
            XCTAssertFalse(text.contains("Acme"), text); XCTAssertFalse(text.contains("Clients")); XCTAssertFalse(text.contains(NSHomeDirectory())); XCTAssertFalse(text.contains(NSUserName()))
        }
        XCTAssertTrue(r.title.hasPrefix("[Verdict] ~/…/node_modules: Not safe"))
        XCTAssertTrue(r.body.contains("It holds patched packages.")); XCTAssertTrue(r.body.contains("0.1.0 beta 18"))
        XCTAssertEqual(r.url.host, "github.com"); XCTAssertEqual(r.url.path, "/danielsimisi-coder/avakasha/issues/new")
        XCTAssertTrue(VerdictReport.make(id: "mail", relativePath: "Library/Mail", verdict: "x", detail: "", problem: .other, comment: "", appVersion: "v", systemVersion: "s").body.contains("_(none given)_"))
    }
}
