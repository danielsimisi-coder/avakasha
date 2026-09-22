import XCTest
import Foundation
@testable import KeepelixCore

final class FolderTrashTests: XCTestCase {
    var base: URL!; var root: URL!; var trash: URL!
    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("keepelix-folder-" + UUID().uuidString)
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
        Thread.sleep(forTimeInterval: 0.02); try Data("late".utf8).write(to: f.appendingPathComponent("added.txt")) // changes the folder's own mtime
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
    func testRestoreRefusesADifferentTrashItemOrALinkedParent() throws {
        let f = try folder("nested/deep"); let backend = FakeTrash(directory: trash)
        let ticket = try XCTUnwrap(FolderTrash.move(f, root: root, expected: try FolderTrash.check(f, root: root), backend: backend).ticket)
        // Trash item replaced by another folder with the same name.
        try FileManager.default.removeItem(at: ticket.trashed); try FileManager.default.createDirectory(at: ticket.trashed, withIntermediateDirectories: true)
        XCTAssertFalse(FolderTrash.restore(ticket, root: root, backend: backend).restored)
        // Parent replaced by a symbolic link.
        let parent = root.appendingPathComponent("nested"); let moved = base.appendingPathComponent("moved-parent")
        try FileManager.default.moveItem(at: parent, to: moved); try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: moved)
        XCTAssertFalse(FolderTrash.restore(ticket, root: root, backend: backend).restored)
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
}
