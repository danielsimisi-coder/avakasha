import XCTest
import Foundation
@testable import AvakashaCore

/// Session "space" summary: bytes moved to Trash this session (allocated blocks) and free space on a volume.
final class SessionSpaceTests: XCTestCase {
    var base: URL!; var root: URL!; var trash: URL!
    override func setUpWithError() throws {
        base=FileManager.default.temporaryDirectory.appendingPathComponent("SessionSpaceTests-"+UUID().uuidString)
        root=base.appendingPathComponent("chosen");trash=base.appendingPathComponent("fake-trash")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        try FileManager.default.createDirectory(at:trash,withIntermediateDirectories:true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at:base) }
    func file(_ name:String,_ data:String="test") throws -> FileRecord {
        let url=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data(data.utf8).write(to:url);return try FileRecord(url:url)
    }
    /// Minimal fake backend: moves into a synthetic folder, optionally refusing one file name.
    struct FakeTrash:TrashBackend {
        let directory:URL;var reject:String?=nil
        func moveToTrash(_ url:URL)throws->URL{
            if url.lastPathComponent==reject{throw NSError(domain:"Synthetic failure",code:1)}
            let target=directory.appendingPathComponent(UUID().uuidString+"-"+url.lastPathComponent)
            try FileManager.default.moveItem(at:url,to:target);return target
        }
        func restore(_ source:URL,to destination:URL)throws{try FileManager.default.moveItem(at:source,to:destination)}
    }

    func testMovedBytesEqualSumOfAllocatedBytes()throws {
        let a=try file("a.txt",String(repeating:"a",count:10_000)),b=try file("b.txt",String(repeating:"b",count:3_000))
        let history=TrashHistory(),backend=FakeTrash(directory:trash)
        XCTAssertEqual(history.sessionMovedBytes,0)
        XCTAssertGreaterThan(a.allocatedBytes,0);XCTAssertGreaterThan(b.allocatedBytes,0)
        XCTAssertEqual(history.move([a,b],root:root,backend:backend).tickets.count,2)
        XCTAssertEqual(history.sessionMovedBytes,a.allocatedBytes+b.allocatedBytes)
    }
    func testUndoReturnsToZeroAndRedoRaisesAgain()throws {
        let a=try file("a.txt",String(repeating:"a",count:10_000)),history=TrashHistory(),backend=FakeTrash(directory:trash)
        _=history.move([a],root:root,backend:backend)
        XCTAssertEqual(history.sessionMovedBytes,a.allocatedBytes)
        XCTAssertEqual(history.undo(backend:backend)?.restored,[a.url])
        XCTAssertEqual(history.sessionMovedBytes,0)
        XCTAssertEqual(history.redo(backend:backend)?.tickets.count,1)
        XCTAssertEqual(history.sessionMovedBytes,a.allocatedBytes)
        _=history.undo(backend:backend);XCTAssertEqual(history.sessionMovedBytes,0)
        XCTAssertNil(history.undo(backend:backend));XCTAssertEqual(history.sessionMovedBytes,0,"Never negative")
    }
    func testBlockedRestoreKeepsBytesUntilRetrySucceeds()throws {
        let a=try file("a.txt",String(repeating:"a",count:10_000)),history=TrashHistory(),backend=FakeTrash(directory:trash)
        _=history.move([a],root:root,backend:backend)
        try Data("occupied".utf8).write(to:a.url) // a different file now sits at the original path
        XCTAssertEqual(history.undo(backend:backend)?.pending.count,1);XCTAssertEqual(history.blockedCount,1)
        XCTAssertEqual(history.sessionMovedBytes,a.allocatedBytes,"Still in Trash: still counted")
        XCTAssertTrue(history.retryBlocked(backend:backend)!.restored.isEmpty)
        XCTAssertEqual(history.sessionMovedBytes,a.allocatedBytes)
        try FileManager.default.removeItem(at:a.url)
        XCTAssertEqual(history.retryBlocked(backend:backend)?.restored,[a.url])
        XCTAssertEqual(history.sessionMovedBytes,0)
    }
    func testBlockedTicketIsNotConfusedWithNewMoveOfSamePath()throws {
        let a=try file("a.txt",String(repeating:"a",count:10_000)),history=TrashHistory(),backend=FakeTrash(directory:trash)
        _=history.move([a],root:root,backend:backend)
        try Data(String(repeating:"n",count:50_000).utf8).write(to:a.url);_=history.undo(backend:backend)
        let replacement=try FileRecord(url:a.url);_=history.move([replacement],root:root,backend:backend)
        XCTAssertEqual(history.sessionMovedBytes,a.allocatedBytes+replacement.allocatedBytes)
        XCTAssertEqual(history.retryBlocked(backend:backend)?.restored,[a.url])
        XCTAssertEqual(history.sessionMovedBytes,replacement.allocatedBytes,"Only the original's bytes leave the total")
        XCTAssertEqual(history.undo(backend:backend)?.restored.count,0,"The original occupies the path again; the replacement waits")
        XCTAssertEqual(history.sessionMovedBytes,replacement.allocatedBytes)
    }
    func testPartialFailureCountsOnlyMovedFiles()throws {
        let a=try file("a.txt",String(repeating:"a",count:10_000)),b=try file("b.txt",String(repeating:"b",count:10_000))
        let history=TrashHistory(),backend=FakeTrash(directory:trash,reject:"b.txt")
        let result=history.move([a,b],root:root,backend:backend)
        XCTAssertEqual(result.tickets.count,1);XCTAssertEqual(result.failures.count,1)
        XCTAssertEqual(history.sessionMovedBytes,a.allocatedBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath:b.id))
    }
    func testPartialRedoCountsOnlyMovedFiles()throws {
        let a=try file("a.txt",String(repeating:"a",count:10_000)),b=try file("b.txt",String(repeating:"b",count:10_000))
        let history=TrashHistory(),backend=FakeTrash(directory:trash)
        _=history.move([a,b],root:root,backend:backend);_=history.undo(backend:backend)
        XCTAssertEqual(history.sessionMovedBytes,0)
        try Data("replaced".utf8).write(to:b.url,options:.atomic) // redo must refuse the changed file
        let redo=history.redo(backend:backend)!
        XCTAssertEqual(redo.tickets.map{$0.original},[a.url]);XCTAssertEqual(redo.failures.count,1)
        XCTAssertEqual(history.sessionMovedBytes,a.allocatedBytes)
    }
    func testDiskSpaceAvailableForTemporaryDirectoryAndMissingPath()throws {
        let free=DiskSpace.available(at:FileManager.default.temporaryDirectory)
        XCTAssertNotNil(free);XCTAssertGreaterThan(free ?? 0,0)
        XCTAssertNotNil(DiskSpace.available(at:root))
        XCTAssertNil(DiskSpace.available(at:base.appendingPathComponent("does-not-exist/"+UUID().uuidString)))
    }
}
