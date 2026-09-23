import XCTest
@testable import AvakashaCore

final class OffloadTests: XCTestCase {
    var base: URL!
    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("avakasha-offload-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: base.appendingPathComponent("home/Project/locked.bin").path)
        try? FileManager.default.removeItem(at: base)
    }
    @discardableResult func fixture() throws -> URL {
        let project = base.appendingPathComponent("home/Project", isDirectory: true)
        for (path, size) in [("a.bin", 40_000), ("Footage/b.mov", 120_000), ("Footage/Day 2/c.mov", 80_000), ("notes.txt", 12)] {
            let url = project.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((0..<size).map { UInt8(($0 * 31 + path.count) % 251) }).write(to: url)
        }
        try FileManager.default.createDirectory(at: project.appendingPathComponent("Empty"), withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_500_000_000)], ofItemAtPath: project.appendingPathComponent("a.bin").path)
        return project
    }
    var drive: URL { base.appendingPathComponent("drive/" + Offloader.folderName, isDirectory: true) }

    func testCopyVerifiesEveryFileAndLeavesTheOriginal() throws {
        let project = try fixture()
        let result = try Offloader.copy(project, into: drive, allowSameDrive: true)
        XCTAssertEqual(result.folder.lastPathComponent, "Project")
        XCTAssertEqual(result.manifest.files.count, 4); XCTAssertEqual(result.manifest.directories, ["Empty", "Footage", "Footage/Day 2"])
        for entry in result.manifest.files {
            XCTAssertEqual(try Data(contentsOf: result.folder.appendingPathComponent(entry.path)), try Data(contentsOf: project.appendingPathComponent(entry.path)))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.folder.appendingPathComponent("Empty").path))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: result.folder.appendingPathComponent("a.bin").path)[.modificationDate] as? Date)?.timeIntervalSince1970, 1_500_000_000, "Dates are kept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.appendingPathComponent("Footage/b.mov").path), "The original is never touched")
        XCTAssertEqual(try Offloader.verify(result.folder), result.manifest)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: drive.path).contains { $0.hasSuffix(".partial") })
        XCTAssertEqual(try Offloader.copy(project, into: drive, allowSameDrive: true).folder.lastPathComponent, "Project 2", "Never overwrites an earlier copy")
    }
    func testRefusals() throws {
        let project = try fixture()
        XCTAssertThrowsError(try Offloader.copy(project, into: drive)) { XCTAssertEqual($0 as? OffloadError, .sameDrive) }
        try FileManager.default.createSymbolicLink(at: project.appendingPathComponent("link"), withDestinationURL: project.appendingPathComponent("a.bin"))
        XCTAssertThrowsError(try Offloader.copy(project, into: drive, allowSameDrive: true)) { XCTAssertEqual($0 as? OffloadError, .unsupportedItem("link")) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: drive.appendingPathComponent("Project").path))
    }
    func testFailureRemovesThePartialCopyOnly() throws {
        let project = try fixture()
        let locked = project.appendingPathComponent("locked.bin"); try Data("secret".utf8).write(to: locked)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        XCTAssertThrowsError(try Offloader.copy(project, into: drive, allowSameDrive: true))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: drive.path), [], "No partial copy is left behind")
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.appendingPathComponent("a.bin").path))
    }
    func testCancelLeavesNothing() throws {
        let project = try fixture(); let token = CancellationToken(); token.cancel()
        XCTAssertThrowsError(try Offloader.copy(project, into: drive, allowSameDrive: true, token: token)) { XCTAssertEqual($0 as? OffloadError, .cancelled) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: drive.appendingPathComponent("Project").path))
    }
    func testVerifyCatchesADamagedCopy() throws {
        let copy = try Offloader.copy(try fixture(), into: drive, allowSameDrive: true).folder
        try Data("changed-same".utf8).write(to: copy.appendingPathComponent("notes.txt")) // same size, different bytes: only the hash can tell
        XCTAssertThrowsError(try Offloader.verify(copy)) { XCTAssertEqual($0 as? OffloadError, .verifyFailed("notes.txt")) }
        try Data("shorter".utf8).write(to: copy.appendingPathComponent("notes.txt"))
        XCTAssertThrowsError(try Offloader.verify(copy)) { XCTAssertEqual($0 as? OffloadError, .verifyFailed("notes.txt"), "A size change fails before any hashing") }
        try FileManager.default.removeItem(at: copy.appendingPathComponent("notes.txt"))
        XCTAssertThrowsError(try Offloader.checkShape(copy), "A missing file is noticed")
        try FileManager.default.removeItem(at: copy.appendingPathComponent(OffloadManifest.fileName))
        XCTAssertThrowsError(try Offloader.verify(copy)) { XCTAssertEqual($0 as? OffloadError, .manifestMissing) }
    }
    func testBringBackNeverOverwrites() throws {
        let project = try fixture()
        let copy = try Offloader.copy(project, into: drive, allowSameDrive: true).folder
        let record = OffloadRecord(name: "Project", originalPath: project.path, destinationPath: copy.path, volumeName: "Drive", volumeUUID: nil, date: Date(), bytes: 1, files: 4)
        XCTAssertTrue(record.isAvailable)
        let target = Offloader.bringBackTarget(for: record)
        XCTAssertEqual(target.lastPathComponent, "Project (brought back)", "The original is still there, so it comes back beside it")
        try Offloader.bringBack(copy, to: target)
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("Footage/Day 2/c.mov")), try Data(contentsOf: project.appendingPathComponent("Footage/Day 2/c.mov")))
        XCTAssertThrowsError(try Offloader.bringBack(copy, to: target), "Never onto an existing folder")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.appendingPathComponent(OffloadManifest.fileName).path), "The drive copy stays")
        try FileManager.default.removeItem(at: project)
        XCTAssertEqual(Offloader.bringBackTarget(for: record).path, project.path, "The original place, once it is free")
    }
    func testIndexRoundTrip() throws {
        let url = base.appendingPathComponent("support/offload-index.json")
        let records = [OffloadRecord(name: "A", originalPath: "/x/A", destinationPath: "/Volumes/D/A", volumeName: "D", volumeUUID: "U", date: Date(timeIntervalSince1970: 1_790_000_000), bytes: 5, files: 1)]
        try OffloadIndex.save(records, to: url)
        XCTAssertEqual(OffloadIndex.load(from: url), records)
        XCTAssertEqual(OffloadIndex.load(from: url.appendingPathExtension("missing")), [])
    }
    /// A real second drive: a small disk image, attached and detached by the test.
    func testCopyToAnotherDrive() throws {
        let image = base.appendingPathComponent("drive.sparseimage"), mount = base.appendingPathComponent("mnt", isDirectory: true)
        func run(_ args: [String]) -> Int32 { let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil"); p.arguments = args; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice; try? p.run(); p.waitUntilExit(); return p.terminationStatus }
        guard run(["create", "-size", "400m", "-type", "SPARSE", "-fs", "APFS", "-volname", "AvakashaTest", image.path]) == 0 else { throw XCTSkip("hdiutil cannot create images here") }
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        guard run(["attach", image.path, "-mountpoint", mount.path, "-nobrowse", "-quiet"]) == 0 else { throw XCTSkip("hdiutil cannot attach images here") }
        defer { _ = run(["detach", mount.path, "-force", "-quiet"]) }
        let project = try fixture()
        let result = try Offloader.copy(project, into: mount.appendingPathComponent(Offloader.folderName))
        XCTAssertEqual(try Offloader.verify(result.folder), result.manifest)
        var a = stat(), b = stat(); stat(project.path, &a); stat(result.folder.path, &b); XCTAssertNotEqual(a.st_dev, b.st_dev)
    }
    func testReviewFixes() throws {
        let project = try fixture()
        // A file named like the manifest (any case) would be replaced on the drive: refused before copying.
        try Data("mine".utf8).write(to: project.appendingPathComponent("avakasha MANIFEST.json"))
        XCTAssertThrowsError(try Offloader.copy(project, into: drive, allowSameDrive: true)) { XCTAssertEqual($0 as? OffloadError, .unsupportedItem("avakasha MANIFEST.json")) }
        try FileManager.default.removeItem(at: project.appendingPathComponent("avakasha MANIFEST.json"))
        let result = try Offloader.copy(project, into: drive, allowSameDrive: true)
        XCTAssertEqual(Offloader.matches(project, result.inventory), true)
        // Files macOS adds on its own (Finder's .DS_Store, "._" metadata on exFAT) never fail a copy.
        try Data("finder".utf8).write(to: result.folder.appendingPathComponent(".DS_Store")); try Data("meta".utf8).write(to: result.folder.appendingPathComponent("Footage/._b.mov"))
        XCTAssertEqual(try Offloader.verify(result.folder), result.manifest)
        try Data("edited".utf8).write(to: project.appendingPathComponent("Footage/Day 2/c.mov"))
        XCTAssertEqual(Offloader.matches(project, result.inventory), false, "A change after the copy is noticed")
        XCTAssertNil(Offloader.matches(base.appendingPathComponent("missing"), result.inventory), "Unreadable: unknown, not a false alarm")
        // Bringing back never removes a folder it did not create, even one that looks like a working folder.
        let stranger = project.deletingLastPathComponent().appendingPathComponent(".Project (brought back).partial", isDirectory: true)
        try FileManager.default.createDirectory(at: stranger, withIntermediateDirectories: true); try Data("keep".utf8).write(to: stranger.appendingPathComponent("keep.txt"))
        try Offloader.bringBack(result.folder, to: project.deletingLastPathComponent().appendingPathComponent("Project (brought back)"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stranger.appendingPathComponent("keep.txt").path))
        // A manifest that points outside the copy is refused.
        let manifestURL = result.folder.appendingPathComponent(OffloadManifest.fileName)
        let text = try String(contentsOf: manifestURL, encoding: .utf8).replacingOccurrences(of: "\"notes.txt\"", with: #""..\/..\/notes.txt""#)
        try text.write(to: manifestURL, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try Offloader.verify(result.folder))
    }
    func testDamagedIndexIsSetAside() throws {
        let url = base.appendingPathComponent("support/offload-index.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(OffloadIndex.load(from: url), [])
        let aside = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path).filter { $0.contains("damaged") }
        XCTAssertEqual(aside.count, 1, "The damaged list is kept aside, not overwritten")
    }
}
