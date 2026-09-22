import XCTest
import Foundation
import Darwin
@testable import AvakashaCore

/// Synthetic folders only: every fixture lives under a fresh temporary directory that tearDown removes.
final class LargestFilesTests: XCTestCase {
    var base: URL!; var root: URL!
    override func setUpWithError() throws {
        base=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        root=base.appendingPathComponent("chosen")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at:base) }
    @discardableResult func file(_ name:String,_ count:Int=4) throws -> FileRecord {
        let url=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data(String(repeating:"x",count:count).utf8).write(to:url);return try FileRecord(url:url)
    }
    func names(_ result:StorageMapResult) -> [String] { result.largestFiles.map { $0.url.lastPathComponent } }

    func testLargestFilesAreSortedBySizeThenPathAndCappedByLimit()throws {
        try file("medium.bin",20_000);try file("small.bin",5_000);try file("huge.bin",60_000);try file("sub/large.bin",40_000)
        try file("tie-b.bin",100);try file("tie-a.bin",100)
        let all=try StorageMapper.map(root:root,token:CancellationToken())
        XCTAssertEqual(names(all),["huge.bin","large.bin","medium.bin","small.bin","tie-a.bin","tie-b.bin"])
        XCTAssertEqual(all.largestFiles.map(\.bytes),all.largestFiles.map(\.bytes).sorted(by:>))
        XCTAssertEqual(all.largestFiles[0].bytes,try FileRecord(url:root.appendingPathComponent("huge.bin")).allocatedBytes,"Sizes are allocated bytes, like the map itself")
        let capped=try StorageMapper.map(root:root,token:CancellationToken(),limit:3)
        XCTAssertEqual(names(capped),["huge.bin","large.bin","medium.bin"])
        XCTAssertEqual(Array(all.largestFiles.prefix(3)),capped.largestFiles)
        XCTAssertEqual(all.root.files,6,"The map still counts every file")
    }
    func testTiesAtTheCutoffResolveByPathWhateverTheWalkOrder()throws {
        for n in ["k","c","z","a","m"] { try file("\(n).bin",100) }
        let result=try StorageMapper.map(root:root,token:CancellationToken(),limit:2)
        XCTAssertEqual(names(result),["a.bin","c.bin"])
    }
    func testFileInSubfolderIsReportedWithItsFullURLUnderTheRoot()throws {
        try file("one/two/deep.bin",8_000)
        let result=try StorageMapper.map(root:root,token:CancellationToken())
        XCTAssertEqual(result.largestFiles.count,1)
        let url=result.largestFiles[0].url
        XCTAssertEqual(url,result.root.url.appendingPathComponent("one/two/deep.bin"))
        XCTAssertTrue(url.path.hasPrefix(result.root.url.path+"/"))
        XCTAssertEqual(url.resolvingSymlinksInPath().path,root.appendingPathComponent("one/two/deep.bin").resolvingSymlinksInPath().path)
        XCTAssertTrue(FileManager.default.fileExists(atPath:url.path))
    }
    func testHiddenFilesAndFilesUnderHiddenFoldersAreExcluded()throws {
        try file(".hidden.bin",50_000);try file(".cache/blob.bin",40_000);try file("visible/.secret/deep.bin",30_000);try file("visible/.dotfile",20_000)
        try file("flagged/inside.bin",25_000);try file("flagged-file.bin",22_000);try file("shown.bin",1_000)
        XCTAssertEqual(chflags(root.appendingPathComponent("flagged").path,UInt32(UF_HIDDEN)),0)
        XCTAssertEqual(chflags(root.appendingPathComponent("flagged-file.bin").path,UInt32(UF_HIDDEN)),0)
        let result=try StorageMapper.map(root:root,token:CancellationToken())
        XCTAssertEqual(names(result),["shown.bin"])
        XCTAssertEqual(result.root.files,7,"Hidden files still take space in the map")
        XCTAssertTrue(try XCTUnwrap(result.root.children.first{$0.name=="flagged"}).isHidden)
    }
    func testPackageContentsAndDatabaseExtensionsAreExcluded()throws {
        try file("Album.app/Contents/big.bin",60_000);try file("Photos.photoslibrary/database/Photos.sqlite",50_000)
        for ext in ["sqlite","sqlite-wal","sqlite-shm","db","db-wal","db-shm","thumb","mmsthumb","favicon"] { try file("store.\(ext)",30_000) }
        try file("upper.SQLITE",30_000);try file("upper.DB",30_000) // distinct names: the temp volume is case-insensitive
        try file("movie.mov",10_000)
        let result=try StorageMapper.map(root:root,token:CancellationToken())
        XCTAssertEqual(names(result),["movie.mov"])
        XCTAssertTrue(try XCTUnwrap(result.root.children.first{$0.name=="Album.app"}).isPackage)
        XCTAssertEqual(result.root.files,14,"Excluded files are still measured")
    }
    func testHardLinkedDataIsListedOnce()throws {
        let a=try file("a.bin",10_000)
        try FileManager.default.linkItem(at:a.url,to:root.appendingPathComponent("a-link.bin"))
        try file("b.bin",4_000)
        let result=try StorageMapper.map(root:root,token:CancellationToken())
        XCTAssertEqual(result.sharedFiles,1)
        XCTAssertEqual(result.largestFiles.count,2)
        XCTAssertEqual(result.largestFiles[0].bytes,a.allocatedBytes)
        XCTAssertTrue(["a.bin","a-link.bin"].contains(result.largestFiles[0].url.lastPathComponent))
        XCTAssertEqual(result.largestFiles[1].url.lastPathComponent,"b.bin")
    }
    func testCancelledWalkReturnsThePartialListCollectedSoFar()throws {
        for i in 0..<600 { try file("d\(i%20)/f\(i).bin",4) }
        let token=CancellationToken();token.cancel()
        let result=try StorageMapper.map(root:root,token:token,limit:1000)
        XCTAssertTrue(result.cancelled)
        XCTAssertGreaterThan(result.largestFiles.count,0);XCTAssertLessThan(result.largestFiles.count,600)
        XCTAssertEqual(result.largestFiles.count,result.root.files,"The partial list matches the files the partial map counted")
        XCTAssertEqual(result.largestFiles,result.largestFiles.sorted { $0.bytes == $1.bytes ? $0.url.path < $1.url.path : $0.bytes > $1.bytes })
        let full=try StorageMapper.map(root:root,token:CancellationToken(),limit:1000)
        XCTAssertFalse(full.cancelled);XCTAssertEqual(full.largestFiles.count,600)
    }
    func testLimitZeroGivesAnEmptyListButStillMaps()throws {
        try file("a.bin",10_000);try file("sub/b.bin",5_000)
        let result=try StorageMapper.map(root:root,token:CancellationToken(),limit:0)
        XCTAssertTrue(result.largestFiles.isEmpty);XCTAssertEqual(result.root.files,2);XCTAssertGreaterThan(result.root.bytes,0)
        XCTAssertTrue(try StorageMapper.map(root:root,token:CancellationToken(),limit:-5).largestFiles.isEmpty)
    }
    func testLargeFileIsEquatableOnURLAndBytes()throws {
        let u=root.appendingPathComponent("x.bin")
        XCTAssertEqual(LargeFile(url:u,bytes:1),LargeFile(url:u,bytes:1));XCTAssertNotEqual(LargeFile(url:u,bytes:1),LargeFile(url:u,bytes:2))
    }
}
