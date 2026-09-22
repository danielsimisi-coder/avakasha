import XCTest
@testable import AvakashaCore

final class KnownLocationsTests: XCTestCase {
    var home: URL!
    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("avakasha-home-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }
    func make(_ relative: String, files: Int = 1, size: Int = 4000) throws -> URL {
        let url = home.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for i in 0..<files { try Data(repeating: 0x61, count: size).write(to: url.appendingPathComponent("f\(i).bin")) }
        return url
    }

    func testCatalogueIsWellFormed() {
        let ids = KnownLocations.all.map(\.id)
        for location in KnownLocations.all where location.safety == .rebuildable {
            XCTAssertFalse(location.relativePath.hasPrefix(".."), "Rebuildable entries stay inside the home folder: " + location.id)
        }
        XCTAssertEqual(Set(ids).count, ids.count, "ids are unique")
        for location in KnownLocations.all {
            XCTAssertFalse(location.relativePath.hasPrefix("/"), location.id)
            XCTAssertEqual(location.command != nil, location.safety == .commandOnly, location.id + " has a command only when command-only")
            if let command = location.command { XCTAssertFalse(command.contains("rm -rf"), "The catalogue never suggests permanent deletion: " + location.id) }
        }
        XCTAssertTrue(KnownLocations.all.contains { $0.id == "xcode.deviceSupport" && $0.safety == .rebuildable })
        XCTAssertTrue(KnownLocations.all.contains { $0.id == "mail" && $0.safety == .cleanInsideApp })
    }
    func testPresentListsOnlyExistingRealDirectories() throws {
        _ = try make("Library/Developer/Xcode/DerivedData")
        _ = try make("Library/Application Support/Claude/vm_bundles")
        try Data("not a folder".utf8).write(to: home.appendingPathComponent("go")) // a file where a catalogue folder would be
        let realCache = try make("elsewhere/cache")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".cache"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".cache/huggingface"), withDestinationURL: realCache)
        let present = KnownLocations.present(in: home).map(\.id)
        XCTAssertEqual(Set(present), ["xcode.derivedData", "claude.vmBundles"], "\(present)")
    }
    func testCacheFoldersListPerAppCachesButNotCuratedOrHiddenOnes() throws {
        _ = try make("Library/Caches/com.example.app")
        _ = try make("Library/Caches/com.apple.dt.Xcode")     // curated already
        _ = try make("Library/Caches/Google/Chrome")          // parent of a curated clean-inside-app entry
        _ = try make("Library/Caches/.hidden")
        let linkTarget = try make("elsewhere/linked"); try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Library/Caches/linked"), withDestinationURL: linkTarget)
        try Data("x".utf8).write(to: home.appendingPathComponent("Library/Caches/loose.txt"))
        let found = KnownLocations.cacheFolders(in: home)
        XCTAssertEqual(found.map(\.id), ["cache.com.example.app"])
        XCTAssertEqual(found[0].safety, .rebuildable); XCTAssertEqual(found[0].relativePath, "Library/Caches/com.example.app")
        XCTAssertTrue(KnownLocations.cacheFolders(in: home.appendingPathComponent("missing")).isEmpty)
    }
    func testMeasureReportsAllocatedBytesAndErrors() throws {
        let url = try make("Library/Developer/Xcode/iOS DeviceSupport", files: 3, size: 10_000)
        let location = try XCTUnwrap(KnownLocations.all.first { $0.id == "xcode.deviceSupport" })
        let measured = KnownLocations.measure(location, home: home, token: CancellationToken())
        XCTAssertNil(measured.error); XCTAssertEqual(measured.files, 3); XCTAssertGreaterThanOrEqual(measured.bytes, 30_000); XCTAssertFalse(measured.cancelled)
        XCTAssertEqual(location.url(home: home).path, url.path)
        let missing = KnownLocations.measure(try XCTUnwrap(KnownLocations.all.first { $0.id == "mail" }), home: home, token: CancellationToken())
        XCTAssertNotNil(missing.error); XCTAssertEqual(missing.bytes, 0)
    }
}
