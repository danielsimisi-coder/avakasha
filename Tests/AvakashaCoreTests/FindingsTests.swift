import XCTest
@testable import AvakashaCore

final class FindingsTests: XCTestCase {
    var home: URL!
    let old = Date(timeIntervalSince1970: 1_577_836_800) // 2020-01-01
    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("avakasha-find-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }
    @discardableResult func make(_ relative: String, size: Int = 40_000, modified: Date? = nil) throws -> URL {
        let url = home.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appendingPathComponent("data.bin")
        try Data(repeating: 0x61, count: size).write(to: file)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path) }
        return url
    }
    var small: FindingOptions { var o = FindingOptions(); o.minimumRegenerableBytes = 10_000; o.minimumLeftoverBytes = 10_000; o.minimumUntouchedBytes = 10_000; return o }
    func detect(installed: [InstalledApp] = [], excluding: [String] = [], options: FindingOptions? = nil) throws -> [Finding] {
        let map = try StorageMapper.map(root: home, token: CancellationToken())
        return Findings.detect(in: map, installed: installed, options: options ?? small, excluding: excluding)
    }
    func names(_ findings: [Finding]) -> [String] { findings.map { $0.url.path.replacingOccurrences(of: home.resolvingSymlinksInPath().path + "/", with: "") } }

    func testNewestModifiedPropagatesUp() throws {
        try make("A/B", modified: old); try make("A/C")
        let map = try StorageMapper.map(root: home, token: CancellationToken())
        let a = try XCTUnwrap(map.root.children.first { $0.name == "A" })
        let b = try XCTUnwrap(a.children.first { $0.name == "B" })
        XCTAssertEqual(b.newestModified, Int64(old.timeIntervalSince1970))
        XCTAssertGreaterThan(a.newestModified, b.newestModified)
        XCTAssertEqual(map.root.newestModified, a.newestModified)
    }
    func testBundleContentsCountAsChanges() throws {
        try make("Movies/Project/Footage", modified: old)
        try make("Movies/Project/Edit.bundle/Contents") // edited now, inside a bundle
        var options = small; options.now = Date()
        let map = try StorageMapper.map(root: home, token: CancellationToken())
        XCTAssertTrue(map.root.children.first { $0.name == "Movies" }?.children.first?.children.contains { $0.isPackage } == true)
        let found = Findings.detect(in: map, installed: [], options: options)
        XCTAssertEqual(names(found), ["Movies/Project/Footage"], "A bundle edited today keeps its folder current; only the old footage is reported")
    }
    func project(_ relative: String) throws { try make(relative); try Data("{}".utf8).write(to: home.appendingPathComponent(relative).appendingPathComponent("package.json")) }
    func testRegenerableByNameTopMostOnly() throws {
        try project("Code/web"); try project("Code/tiny")
        try make("Code/web/node_modules/react"); try make("Code/web/node_modules/lodash/node_modules/x")
        try make("Movies/Edit/Adobe Premiere Pro Audio Previews"); try make("Movies/Edit/Clip.PRV"); try make("Movies/Edit/Adobe Premiere Pro Video Previews")
        try make("Code/py/__pycache__"); try make("Documents/Notes") // an ordinary folder is never regenerable
        try make("Code/tiny/node_modules", size: 100) // under the minimum
        try make("Code/loose/node_modules") // no package.json beside it: not known to be reinstallable
        try make(".vscode/extensions/ext/node_modules"); try make(".nvm/versions/node/lib/node_modules") // tools, under hidden folders
        try make("Documents/Game/cache"); try make("Library/Application Support/Chat/Code Cache") // generic names count only in Library
        try make("Documents/Client Previews"); try make("Library/pnpm/global/5/node_modules/tool") // own exports; an installed tool
        try Data("{}".utf8).write(to: home.appendingPathComponent("Library/pnpm/global/5/package.json"))
        try make("Code/web/.next/cache"); try make("Code/.gradle/caches") // dot-folders are never moved whole, so never offered
        var flags = URLResourceValues(); flags.isHidden = true; var library = home.appendingPathComponent("Library"); try library.setResourceValues(flags) // as on a real Mac
        let found = try detect(installed: [InstalledApp(name: "Chat", bundleID: "com.chat.app")])
        XCTAssertTrue(found.contains { $0.url.lastPathComponent == "Code Cache" && $0.kind == .regenerable(pattern: "code cache") })
        XCTAssertEqual(Set(names(found.filter(\.isRegenerable))).subtracting(["Library/Application Support/Chat/Code Cache"]), ["Code/web/node_modules", "Movies/Edit/Adobe Premiere Pro Audio Previews", "Movies/Edit/Adobe Premiere Pro Video Previews", "Movies/Edit/Clip.PRV", "Code/py/__pycache__"])
    }
    func testSkipsCloudTrashAppleAndCatalogue() throws {
        try make("Library/Mobile Documents/com~apple~CloudDocs/Project/node_modules")
        try make("Library/CloudStorage/Dropbox/site/node_modules")
        try make(".Trash/old/node_modules")
        try make("Library/Containers/com.apple.Safari/Data/Library/Caches")
        try make("Library/Developer/Xcode/DerivedData/App")
        let derived = home.appendingPathComponent("Library/Developer/Xcode/DerivedData").path
        let found = try detect(excluding: [derived])
        XCTAssertTrue(found.isEmpty, "\(names(found))")
    }
    func testLeftoversNeedTheAppToBeMissing() throws {
        try make("Library/Application Support/OldEditor"); try make("Library/Application Support/Sketchy Tool")
        try make("Library/Application Support/Google/Chrome"); try make("Library/Application Support/AddressBook")
        try make("Library/Containers/com.vendor.gone"); try make("Library/Containers/com.present.app")
        try make("Library/Group Containers/ABCDE12345.com.vendor2.shared"); try make("Library/Group Containers/group.com.apple.notes")
        let installed = [InstalledApp(name: "Google Chrome", bundleID: "com.google.Chrome"), InstalledApp(name: "Present", bundleID: "com.present.app"),
                         InstalledApp(name: "Sketchy Tool", bundleID: "com.sketchy.tool")]
        let found = try detect(installed: installed)
        let leftovers = found.filter { if case .leftover = $0.kind { return true }; return false }
        XCTAssertEqual(Set(names(leftovers)), ["Library/Application Support/OldEditor", "Library/Containers/com.vendor.gone", "Library/Group Containers/ABCDE12345.com.vendor2.shared"])
        XCTAssertTrue(leftovers.contains { $0.kind == .leftover(owner: "com.vendor2.shared") }, "The team prefix is dropped from the owner")
    }
    func testOwnerMatching() {
        let apps = [InstalledApp(name: "Visual Studio Code", bundleID: "com.microsoft.VSCode"), InstalledApp(name: "Adobe Premiere Pro 2025", bundleID: "com.adobe.PremierePro.25")]
        XCTAssertTrue(InstalledApps.matches("Code", in: apps))
        XCTAssertTrue(InstalledApps.matches("Adobe", in: apps))
        XCTAssertTrue(InstalledApps.matches("com.microsoft.teams2", in: apps), "Same vendor counts as installed: doubtful means keep")
        XCTAssertTrue(InstalledApps.matches("ab", in: apps), "Too short to judge")
        XCTAssertFalse(InstalledApps.matches("OldEditor", in: apps))
        XCTAssertFalse(InstalledApps.matches("com.gone.app", in: apps))
        XCTAssertNil(Findings.owner(ofFolderNamed: "com.apple.mail")); XCTAssertNil(Findings.owner(ofFolderNamed: "CrashReporter")); XCTAssertNil(Findings.owner(ofFolderNamed: ".hidden"))
    }
    func testUntouchedIsTopMostAndNeverTheHomeTopLevel() throws {
        try make("Documents/Old project/Footage", modified: old); try make("Documents/Old project/Exports", modified: old)
        try make("Documents/Current", modified: Date())
        try make("Movies/2019 Trip", modified: old)
        try make("Library/Application Support/Keep", modified: old) // Library is covered by the other detectors only
        try make(".config/stale", modified: old) // hidden: never reported as untouched
        var options = small; options.now = Date()
        let found = try detect(installed: [InstalledApp(name: "Keep", bundleID: "com.keep.app")], options: options)
        let untouched = found.filter { if case .untouched = $0.kind { return true }; return false }
        XCTAssertEqual(Set(names(untouched)), ["Documents/Old project", "Movies/2019 Trip"], "Top-level Movies is only old in part; Documents holds a current folder")
        if case .untouched(let months) = untouched[0].kind { XCTAssertGreaterThan(months, 24) } else { XCTFail() }
    }
    func testRankingWeighsSafety() throws {
        try make("Code/a/node_modules", size: 40_000); try Data("{}".utf8).write(to: home.appendingPathComponent("Code/a/package.json"))
        try make("Library/Application Support/Gone", size: 100_000)
        try make("Archive/2018", size: 400_000, modified: old)
        let found = try detect()
        XCTAssertEqual(names(found), ["Archive/2018", "Library/Application Support/Gone", "Code/a/node_modules"], "400k×0.3 > 100k×0.5 > 40k×1")
        XCTAssertEqual(found.first?.isRegenerable, false)
    }
    func testInstalledAppsScan() throws {
        let apps = home.appendingPathComponent("Applications")
        for (path, name, id) in [("Tool.app", "Tool", "com.x.tool"), ("Vendor 2025/Vendor Editor.app", "Editor", "com.vendor.editor")] {
            let contents = apps.appendingPathComponent(path).appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            try (["CFBundleIdentifier": id, "CFBundleName": name] as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
        }
        let found = InstalledApps.scan(roots: [apps])
        XCTAssertTrue(found.contains(InstalledApp(name: "Tool", bundleID: "com.x.tool")))
        XCTAssertTrue(found.contains(InstalledApp(name: "Vendor Editor", bundleID: "com.vendor.editor")), "The file name counts as a name too")
        XCTAssertEqual(found.filter { $0.bundleID == "com.vendor.editor" }.count, 2)
    }
}
