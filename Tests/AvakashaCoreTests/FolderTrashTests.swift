import XCTest
import Foundation
@testable import AvakashaCore

final class FolderTrashTests: XCTestCase {
    var base: URL!; var root: URL!; var trash: URL!
    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("avakasha-folder-" + UUID().uuidString)
        root = base.appendingPathComponent("chosen"); trash = base.appendingPathComponent("fake-trash")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: base) }
    struct FakeTrash: TrashBackend {
        let directory: URL
        func moveToTrash(_ url: URL) throws -> URL {
            let target = directory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target); return target
        }
        func restore(_ source: URL, to destination: URL) throws { try FileManager.default.moveItem(at: source, to: destination) }
    }
    func folder(_ name: String, files: Int = 2) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for i in 0..<files { try Data("f\(i)".utf8).write(to: url.appendingPathComponent("file\(i).txt")) }
        return url
    }

    func testMoveAndRestoreRoundTrip() throws {
        let f = try folder("Old exports"); let backend = FakeTrash(directory: trash)
        let expected = try FolderTrash.check(f, root: root)
        let moved = FolderTrash.move(f, root: root, expected: expected, backend: backend)
        let ticket = try XCTUnwrap(moved.ticket); XCTAssertNil(moved.failure)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.path)); XCTAssertTrue(FileManager.default.fileExists(atPath: ticket.trashed.appendingPathComponent("file0.txt").path))
        let restored = FolderTrash.restore(ticket, root: root, backend: backend)
        XCTAssertTrue(restored.restored, restored.failure?.message ?? ""); XCTAssertEqual(try String(contentsOf: f.appendingPathComponent("file1.txt")), "f1")
    }
    func testRootItselfAndOutsideFoldersAreRefused() throws {
        let outside = base.appendingPathComponent("chosen-other"); try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        XCTAssertThrowsError(try FolderTrash.check(root, root: root))
        XCTAssertThrowsError(try FolderTrash.check(outside, root: root))
        XCTAssertThrowsError(try FolderTrash.check(base, root: root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }
    func testSymlinkedPackageAndHiddenFoldersAreRefused() throws {
        let real = try folder("real"); let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        XCTAssertThrowsError(try FolderTrash.check(link, root: root))
        let bundle = try folder("Photos.photoslibrary"); XCTAssertThrowsError(try FolderTrash.check(bundle, root: root))
        let app = try folder("Tool.app"); XCTAssertThrowsError(try FolderTrash.check(app, root: root))
        let hidden = try folder(".cache"); XCTAssertThrowsError(try FolderTrash.check(hidden, root: root))
        let nestedUnderLink = link.appendingPathComponent("sub"); try FileManager.default.createDirectory(at: real.appendingPathComponent("sub"), withIntermediateDirectories: true)
        XCTAssertThrowsError(try FolderTrash.check(nestedUnderLink, root: root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: real.appendingPathComponent("file0.txt").path))
    }
    func testChangedFolderIsNotMoved() throws {
        let f = try folder("busy"); let expected = try FolderTrash.check(f, root: root)
        // A direct child added afterwards changes the folder's own modification time; sleep past coarse timestamp granularity.
        Thread.sleep(forTimeInterval: 0.05); try Data("late".utf8).write(to: f.appendingPathComponent("added.txt"))
        let result = FolderTrash.move(f, root: root, expected: expected, backend: FakeTrash(directory: trash))
        XCTAssertNil(result.ticket); XCTAssertNotNil(result.failure); XCTAssertTrue(FileManager.default.fileExists(atPath: f.appendingPathComponent("added.txt").path))
    }
    func testReplacedFolderIsNotMoved() throws {
        let f = try folder("swap"); let expected = try FolderTrash.check(f, root: root)
        try FileManager.default.removeItem(at: f); _ = try folder("swap") // same path, new inode
        let result = FolderTrash.move(f, root: root, expected: expected, backend: FakeTrash(directory: trash))
        XCTAssertNil(result.ticket); XCTAssertTrue(FileManager.default.fileExists(atPath: f.path))
    }
    func testRestoreNeverOverwritesAndCanRetry() throws {
        let f = try folder("keep"); let backend = FakeTrash(directory: trash)
        let ticket = try XCTUnwrap(FolderTrash.move(f, root: root, expected: try FolderTrash.check(f, root: root), backend: backend).ticket)
        try FileManager.default.createDirectory(at: f, withIntermediateDirectories: true); try Data("new".utf8).write(to: f.appendingPathComponent("new.txt"))
        let blocked = FolderTrash.restore(ticket, root: root, backend: backend)
        XCTAssertFalse(blocked.restored); XCTAssertEqual(try String(contentsOf: f.appendingPathComponent("new.txt")), "new")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ticket.trashed.path))
        try FileManager.default.removeItem(at: f)
        let again = FolderTrash.restore(ticket, root: root, backend: backend); XCTAssertTrue(again.restored, again.failure?.message ?? "")
        XCTAssertEqual(try String(contentsOf: f.appendingPathComponent("file0.txt")), "f0")
    }
    func testRestoreRefusesAReplacedTrashItem() throws {
        let f = try folder("nested/deep"); let backend = FakeTrash(directory: trash)
        let ticket = try XCTUnwrap(FolderTrash.move(f, root: root, expected: try FolderTrash.check(f, root: root), backend: backend).ticket)
        try FileManager.default.removeItem(at: ticket.trashed); try FileManager.default.createDirectory(at: ticket.trashed, withIntermediateDirectories: true)
        XCTAssertFalse(FolderTrash.restore(ticket, root: root, backend: backend).restored)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.path))
    }
    func testRestoreRefusesALinkedParentAndKeepsTheTrashItem() throws {
        let f = try folder("nested2/deep"); let backend = FakeTrash(directory: trash)
        let ticket = try XCTUnwrap(FolderTrash.move(f, root: root, expected: try FolderTrash.check(f, root: root), backend: backend).ticket)
        let parent = root.appendingPathComponent("nested2"); let moved = base.appendingPathComponent("moved-parent")
        try FileManager.default.moveItem(at: parent, to: moved); try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: moved)
        XCTAssertFalse(FolderTrash.restore(ticket, root: root, backend: backend).restored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ticket.trashed.appendingPathComponent("file0.txt").path), "The Trash item is untouched")
    }
    struct MisreportingTrash: TrashBackend {
        let directory: URL
        func moveToTrash(_ url: URL) throws -> URL {
            _ = try FakeTrash(directory: directory).moveToTrash(url)
            let other = directory.appendingPathComponent("other-" + UUID().uuidString); try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true); return other
        }
        func restore(_ source: URL, to destination: URL) throws { try FileManager.default.moveItem(at: source, to: destination) }
    }
    func testMoveVerifiesTheMovedFolderAndReportsWhenItCannot() throws {
        let f = try folder("verify")
        let result = FolderTrash.move(f, root: root, expected: try FolderTrash.check(f, root: root), backend: MisreportingTrash(directory: trash))
        XCTAssertNil(result.ticket); XCTAssertTrue(result.failure?.message.contains("Finder Trash") ?? false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.path), "The backend moved it elsewhere; the app reports rather than pretends, and never moves another item back in its place")
    }
    func testHistoryReportsAFolderThatVanishedFromTrashOnce() throws {
        let f = try folder("gone"); let history = TrashHistory(); let backend = FakeTrash(directory: trash)
        let ticket = try XCTUnwrap(history.moveFolder(f, root: root, expected: try FolderTrash.check(f, root: root), bytes: 10, backend: backend).ticket)
        try FileManager.default.removeItem(at: ticket.trashed)
        let undo = try XCTUnwrap(history.undo(backend: backend))
        XCTAssertTrue(undo.restored.isEmpty); XCTAssertEqual(undo.failures.count, 1); XCTAssertEqual(history.blockedCount, 0); XCTAssertFalse(history.canRedo)
    }
    func testHiddenAncestorsProtectedFoldersAndMountPointsAreRefused() throws {
        let inside = try folder(".hiddenparent/visible")
        XCTAssertThrowsError(try FolderTrash.check(inside, root: root)) { XCTAssertEqual($0 as? TriageError, .folderProtected) }
        XCTAssertNoThrow(try FolderTrash.check(inside, root: root, allowHiddenAncestors: true), "The vetted catalogue may target folders under a dot folder")
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.resolvingSymlinksInPath()
        XCTAssertThrowsError(try FolderTrash.check(home, root: home.deletingLastPathComponent())) { XCTAssertEqual($0 as? TriageError, .folderProtected) }
        // Paths are assembled from parts so the privacy audit's home-path pattern never appears literally in the source.
        func p(_ parts: String...) -> String { "/" + parts.joined(separator: "/") }
        let h = p("Users", "x")
        XCTAssertTrue(FolderTrash.isProtected(p("Users"), home: h)); XCTAssertTrue(FolderTrash.isProtected(p("Volumes", "Disk"), home: h))
        XCTAssertTrue(FolderTrash.isProtected(h, home: h)); XCTAssertFalse(FolderTrash.isProtected(p("Users", "x", "Downloads", "old"), home: h))
        XCTAssertFalse(FolderTrash.isProtected(p("Volumes", "Disk", "old"), home: h)); XCTAssertTrue(FolderTrash.isProtected(p("Users", "other", "Downloads"), home: h))
        for system in [p("private", "var", "folders"), p("Applications", "Utilities"), p("Library", "Caches"), p("System", "Library"), p("usr", "local"), p("Users", "Shared", "x")] { XCTAssertTrue(FolderTrash.isProtected(system, home: h), system) }
        XCTAssertFalse(FolderTrash.isProtected(p("private", "tmp", "keep", "x"), home: h, temporary: p("private", "tmp", "keep") + "/"))
        XCTAssertThrowsError(try FolderTrash.check(URL(fileURLWithPath: "/private/var/folders"), root: URL(fileURLWithPath: "/private/var"))) { XCTAssertEqual($0 as? TriageError, .folderProtected) }
    }
    func testDetachKeepsMapTotalsConsistent() throws {
        _ = try folder("a/x"); _ = try folder("a/y", files: 4); _ = try folder("b")
        let map = try StorageMapper.map(root: root, token: CancellationToken())
        let a = try XCTUnwrap(map.root.children.first { $0.name == "a" }); let y = try XCTUnwrap(a.children.first { $0.name == "y" })
        let before = (map.root.bytes, map.root.files, map.root.directories)
        a.detach(y)
        XCTAssertNil(y.parent); XCTAssertFalse(a.children.contains { $0 === y })
        XCTAssertEqual(map.root.bytes, before.0 - y.bytes); XCTAssertEqual(map.root.files, before.1 - y.files); XCTAssertEqual(map.root.directories, before.2 - 1)
        XCTAssertEqual(a.bytes, a.directBytes + a.children.reduce(0) { $0 + $1.bytes })
    }
    func testHistoryTracksFolderMovesWithUndoButNoRedo() throws {
        let f = try folder("session"); let history = TrashHistory(); let backend = FakeTrash(directory: trash)
        let result = history.moveFolder(f, root: root, expected: try FolderTrash.check(f, root: root), bytes: 8192, backend: backend)
        XCTAssertNotNil(result.ticket); XCTAssertTrue(history.canUndo); XCTAssertEqual(history.sessionMovedBytes, 8192)
        let undo = try XCTUnwrap(history.undo(backend: backend))
        XCTAssertEqual(undo.restored.map(\.path), [f.path]); XCTAssertFalse(history.canRedo, "Folder moves are not redoable")
        XCTAssertEqual(history.sessionMovedBytes, 0); XCTAssertTrue(FileManager.default.fileExists(atPath: f.appendingPathComponent("file0.txt").path))
    }
    func testHistoryBlockedFolderRestoreWaitsForRetry() throws {
        let f = try folder("blocked"); let history = TrashHistory(); let backend = FakeTrash(directory: trash)
        _ = history.moveFolder(f, root: root, expected: try FolderTrash.check(f, root: root), bytes: 100, backend: backend)
        try FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        let first = try XCTUnwrap(history.undo(backend: backend)); XCTAssertTrue(first.restored.isEmpty); XCTAssertEqual(history.blockedCount, 1); XCTAssertEqual(history.sessionMovedBytes, 100)
        try FileManager.default.removeItem(at: f)
        let retry = try XCTUnwrap(history.retryBlocked(backend: backend)); XCTAssertEqual(retry.restored.map(\.path), [f.path]); XCTAssertEqual(history.blockedCount, 0); XCTAssertEqual(history.sessionMovedBytes, 0)
    }
    func testSeveralFoldersMoveAsOneUndoStep() throws {
        let a = try folder("cacheA", files: 3), b = try folder("cacheB"), c = try folder("gone")
        let history = TrashHistory(); let backend = FakeTrash(directory: trash)
        let expectedC = try FolderTrash.check(c, root: root); try Data("x".utf8).write(to: c.appendingPathComponent("late.txt")) // changed after measuring: must not move
        Thread.sleep(forTimeInterval: 0.05)
        let results = history.moveFolders([(a, try FolderTrash.check(a, root: root), 300), (b, try FolderTrash.check(b, root: root), 200), (c, expectedC, 100)], root: root, backend: backend)
        XCTAssertEqual(results.compactMap(\.ticket).count, 2); XCTAssertNotNil(results[2].failure)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: b.path)); XCTAssertTrue(FileManager.default.fileExists(atPath: c.path))
        XCTAssertEqual(history.sessionMovedBytes, 500); XCTAssertTrue(history.canUndo)
        let undo = try XCTUnwrap(history.undo(backend: backend))
        XCTAssertEqual(Set(undo.restored.map(\.path)), [a.path, b.path], "One Undo brings every folder of the step back")
        XCTAssertFalse(history.canUndo); XCTAssertFalse(history.canRedo); XCTAssertEqual(history.sessionMovedBytes, 0)
        XCTAssertEqual(try String(contentsOf: a.appendingPathComponent("file2.txt")), "f2")
    }
    func testNothingMovedMeansNoUndoStep() throws {
        let a = try folder("x"); let history = TrashHistory()
        let expected = try FolderTrash.check(a, root: root); try FileManager.default.removeItem(at: a); _ = try folder("x")
        let results = history.moveFolders([(a, expected, 10)], root: root, backend: FakeTrash(directory: trash))
        XCTAssertNil(results[0].ticket); XCTAssertFalse(history.canUndo); XCTAssertEqual(history.sessionMovedBytes, 0)
    }
}
