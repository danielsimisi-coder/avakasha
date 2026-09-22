import XCTest
import Foundation
import Darwin
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SQLite3
@testable import KeepelixCore

final class CoreTests: XCTestCase {
    var base: URL!; var root: URL!; var trash: URL!
    override func setUpWithError() throws {
        base=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        root=base.appendingPathComponent("chosen");trash=base.appendingPathComponent("fake-trash")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        try FileManager.default.createDirectory(at:trash,withIntermediateDirectories:true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at:base) }
    func file(_ name:String,_ data:String="test") throws -> FileRecord {
        let url=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data(data.utf8).write(to:url);return try FileRecord(url:url)
    }
    struct FakeTrash:TrashBackend {
        let directory:URL;var reject:String?=nil
        func moveToTrash(_ url:URL)throws->URL{
            if url.lastPathComponent==reject{throw NSError(domain:"Synthetic failure",code:1)}
            let target=directory.appendingPathComponent(UUID().uuidString+"-"+url.lastPathComponent)
            try FileManager.default.moveItem(at:url,to:target);return target
        }
        func restore(_ source:URL,to destination:URL)throws{try FileManager.default.moveItem(at:source,to:destination)}
    }
    func testScanSkipsLinksPackagesDatabasesAndHiddenFiles()throws{
        let good=try file("photo.jpg");_ = try file(".hidden.txt");_ = try file("App.app/inside.txt");_ = try file("private.db")
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("link.jpg"),withDestinationURL:good.url)
        let result=try Scanner.scan(root:root,token:CancellationToken())
        XCTAssertEqual(result.files.map(\.id),[good.id]);XCTAssertGreaterThanOrEqual(result.skipped,2)
    }
    func testCancelledScanReturnsPartialStatus()throws{
        _ = try file("a.txt");let token=CancellationToken();token.cancel()
        XCTAssertTrue(try Scanner.scan(root:root,token:token).cancelled)
    }
    func testSystemTrashRoundTripWithOwnedSyntheticFile()throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FILETRIAGE_SYSTEM_TRASH_TEST"] == "1", "Opt-in integration test; uses only this test's generated file")
        let a=try file("Keepelix-synthetic-"+UUID().uuidString+".txt","Disposable Keepelix integration fixture")
        let result=TrashService.move([a],root:root)
        XCTAssertTrue(result.failures.isEmpty, result.failures.map(\.message).joined(separator:"; "))
        XCTAssertEqual(result.tickets.count,1)
        let restored=TrashService.undo(result.tickets,root:root)
        XCTAssertTrue(restored.failures.isEmpty);XCTAssertEqual(restored.restored,[a.url])
        XCTAssertEqual(try String(contentsOf:a.url),"Disposable Keepelix integration fixture")
    }
    func testChangedFileIsNotMoved()throws{
        let r=try file("changed.txt");try Data("new bytes".utf8).write(to:r.url)
        let result=TrashService.move([r],root:root,backend:FakeTrash(directory:trash))
        XCTAssertTrue(result.tickets.isEmpty);XCTAssertEqual(result.failures.count,1);XCTAssertTrue(FileManager.default.fileExists(atPath:r.id))
    }
    func testSiblingRootPrefixIsRejected()throws{
        let other=base.appendingPathComponent("chosen-other");try FileManager.default.createDirectory(at:other,withIntermediateDirectories:true)
        let url=other.appendingPathComponent("outside.txt");try Data("private".utf8).write(to:url)
        let result=TrashService.move([try FileRecord(url:url)],root:root,backend:FakeTrash(directory:trash))
        XCTAssertEqual(result.failures.count,1);XCTAssertTrue(FileManager.default.fileExists(atPath:url.path))
    }
    func testParentReplacedBySymlinkIsRejected()throws{
        let r=try file("nested/a.txt");let original=root.appendingPathComponent("nested");let moved=base.appendingPathComponent("moved")
        try FileManager.default.moveItem(at:original,to:moved);try FileManager.default.createSymbolicLink(at:original,withDestinationURL:moved)
        XCTAssertThrowsError(try FileSafety.validate(r,root:root))
    }
    func testBatchMoveReportsPartialFailureAndUndoRestores()throws{
        let a=try file("a.txt"),b=try file("b.txt")
        let result=TrashService.move([a,b],root:root,backend:FakeTrash(directory:trash,reject:"b.txt"))
        XCTAssertEqual(result.tickets.count,1);XCTAssertEqual(result.failures.count,1)
        XCTAssertFalse(FileManager.default.fileExists(atPath:a.id));XCTAssertTrue(FileManager.default.fileExists(atPath:b.id))
        let undo=TrashService.undo(result.tickets,root:root,backend:FakeTrash(directory:trash))
        XCTAssertEqual(undo.restored,[a.url]);XCTAssertTrue(undo.pending.isEmpty)
        XCTAssertEqual(try Data(contentsOf:a.url),Data("test".utf8))
    }
    func testUndoNeverOverwritesAndCanRetry()throws{
        let a=try file("a.txt");let result=TrashService.move([a],root:root,backend:FakeTrash(directory:trash))
        try Data("new file".utf8).write(to:a.url)
        let first=TrashService.undo(result.tickets,root:root,backend:FakeTrash(directory:trash))
        XCTAssertEqual(first.pending.count,1);XCTAssertEqual(try String(contentsOf:a.url),"new file")
        try FileManager.default.removeItem(at:a.url)
        let second=TrashService.undo(first.pending,root:root,backend:FakeTrash(directory:trash));XCTAssertEqual(second.restored.count,1)
    }
    func testUndoRejectsChangedTrashFile()throws{
        let a=try file("a.txt");let result=TrashService.move([a],root:root,backend:FakeTrash(directory:trash))
        try Data("replacement".utf8).write(to:result.tickets[0].trashed)
        XCTAssertEqual(TrashService.undo(result.tickets,root:root,backend:FakeTrash(directory:trash)).pending.count,1)
    }
    func testExactCopiesKeepOneAndIgnoreSameSizeDifferentData()throws{
        let a=try file("a.txt","identical"),b=try file("b.txt","identical"),c=try file("c.txt","different")
        let result=try ExactDuplicates.find([a,b,c],root:root,token:CancellationToken())
        XCTAssertEqual(result.groups.count,1);XCTAssertEqual(result.groups[0].members.count,2)
        let selection=ExactDuplicates.selectExtras(result.groups,visible:Set([a.id,b.id,c.id]))
        XCTAssertEqual(selection.ids,[b.id]);XCTAssertEqual(selection.keepers[b.id]?.id,a.id)
        let moved=TrashService.move([b],root:root,keepers:selection.keepers,backend:FakeTrash(directory:trash))
        XCTAssertEqual(moved.tickets.count,1);XCTAssertTrue(FileManager.default.fileExists(atPath:a.id))
    }
    func testMissingKeeperPreventsAutomaticExtraMove()throws{
        let a=try file("a.txt"),b=try file("b.txt");try FileManager.default.removeItem(at:a.url)
        let result=TrashService.move([b],root:root,keepers:[b.id:a],backend:FakeTrash(directory:trash))
        XCTAssertTrue(result.tickets.isEmpty);XCTAssertTrue(FileManager.default.fileExists(atPath:b.id))
    }
    func testSelectedKeeperBlocksExtras()throws{
        let a=try file("a.txt"),b=try file("b.txt")
        let result=TrashService.move([b,a],root:root,keepers:[b.id:a],backend:FakeTrash(directory:trash))
        XCTAssertEqual(result.failures.count,2);XCTAssertTrue(result.tickets.isEmpty);XCTAssertTrue(FileManager.default.fileExists(atPath:a.id));XCTAssertTrue(FileManager.default.fileExists(atPath:b.id))
    }
    func testDuplicateSelectionHonorsVisibleFiles()throws{
        let a=try file("a.txt"),b=try file("b.txt"),c=try file("c.txt")
        let s=ExactDuplicates.selectExtras([DuplicateGroup(members:[a,b,c])],visible:[c.id])
        XCTAssertEqual(s.ids,[c.id]);XCTAssertEqual(s.keepers[c.id]?.id,a.id)
    }
    struct SwappingTrash: TrashBackend {
        let directory: URL
        func moveToTrash(_ url:URL)throws->URL {
            try Data("replacement during move".utf8).write(to:url,options:.atomic)
            return try FakeTrash(directory:directory).moveToTrash(url)
        }
        func restore(_ source:URL,to destination:URL)throws { try FileManager.default.moveItem(at:source,to:destination) }
    }
    func testConcurrentReplacementRollsBack()throws {
        let a=try file("a.txt")
        let result=TrashService.move([a],root:root,backend:SwappingTrash(directory:trash))
        XCTAssertTrue(result.tickets.isEmpty);XCTAssertEqual(result.failures.count,1)
        XCTAssertEqual(try String(contentsOf:a.url),"replacement during move")
    }
    func testSameSizeChangedKeeperIsNotEquivalent()throws {
        let a=try file("a.txt","aaaa"),b=try file("b.txt","aaaa")
        let date=try FileManager.default.attributesOfItem(atPath:a.id)[.modificationDate]!
        let handle=try FileHandle(forWritingTo:a.url);try handle.write(contentsOf:Data("bbbb".utf8));try handle.close()
        try FileManager.default.setAttributes([.modificationDate:date],ofItemAtPath:a.id)
        let current=try FileRecord(url:a.url)
        let result=TrashService.move([b],root:root,keepers:[b.id:current],backend:FakeTrash(directory:trash))
        XCTAssertTrue(result.tickets.isEmpty);XCTAssertTrue(FileManager.default.fileExists(atPath:b.id))
    }
    func testDifferentExtendedAttributesBlockAutoSelection()throws {
        let a=try file("a.txt"),b=try file("b.txt")
        let bytes=Array("unique tag".utf8)
        XCTAssertEqual(bytes.withUnsafeBytes{setxattr(b.id,"org.keepelix.fixture",$0.baseAddress,$0.count,0,0)},0)
        let selection=ExactDuplicates.selectExtras([DuplicateGroup(members:[a,b])],visible:[a.id,b.id])
        XCTAssertTrue(selection.ids.isEmpty)
    }
    func testOlderFilesUsesModificationDateNotAccessDate()throws {
        let old=try file("old.txt"),fresh=try file("fresh.txt")
        try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:946684800)],ofItemAtPath:old.id)
        let updated=try FileRecord(url:old.url)
        XCTAssertEqual(ReviewQuery.older([updated,fresh],than:Date(timeIntervalSince1970:1609459200)).map(\.id),[old.id])
        XCTAssertEqual(ReviewQuery.sorted([fresh,updated],by:.oldest).first?.id,old.id)
        XCTAssertEqual(ReviewQuery.sorted([fresh,updated],by:.newest).last?.id,old.id)
    }
    func testSizeSortIsDeterministicAndReversible()throws {
        let small=try file("a.txt"),large=try file("b.txt",String(repeating:"x",count:100_000))
        XCTAssertGreaterThan(large.allocatedBytes,small.allocatedBytes)
        XCTAssertEqual(ReviewQuery.sorted([small,large],by:.largest).first?.id,large.id)
        XCTAssertEqual(ReviewQuery.sorted([small,large],by:.smallest).first?.id,small.id)
    }
    func testHistoryUndoRedoRoundTrip()throws {
        let a=try file("a.txt"),history=TrashHistory(),backend=FakeTrash(directory:trash)
        XCTAssertEqual(history.move([a],root:root,backend:backend).tickets.count,1)
        XCTAssertTrue(history.canUndo);XCTAssertFalse(history.canRedo)
        XCTAssertEqual(history.undo(backend:backend)?.restored,[a.url])
        XCTAssertFalse(history.canUndo);XCTAssertTrue(history.canRedo)
        XCTAssertEqual(history.redo(backend:backend)?.tickets.count,1)
        XCTAssertTrue(history.canUndo);XCTAssertFalse(history.canRedo)
        XCTAssertEqual(history.undo(backend:backend)?.restored,[a.url])
    }
    func testNewMoveClearsRedoHistory()throws {
        let a=try file("a.txt"),b=try file("b.txt"),history=TrashHistory(),backend=FakeTrash(directory:trash)
        _=history.move([a],root:root,backend:backend);_=history.undo(backend:backend)
        _=history.move([b],root:root,backend:backend)
        XCTAssertFalse(history.canRedo);XCTAssertNil(history.redo(backend:backend))
        XCTAssertTrue(FileManager.default.fileExists(atPath:a.id))
    }
    func testRedoRejectsChangedRestoredFile()throws {
        let a=try file("a.txt"),history=TrashHistory(),backend=FakeTrash(directory:trash)
        _=history.move([a],root:root,backend:backend);_=history.undo(backend:backend)
        try Data("New unrelated replacement".utf8).write(to:a.url,options:.atomic)
        let result=history.redo(backend:backend)!
        XCTAssertTrue(result.tickets.isEmpty);XCTAssertEqual(result.failures.count,1)
        XCTAssertEqual(try String(contentsOf:a.url),"New unrelated replacement")
    }
    func testRedoRetainsDuplicateKeeperProtection()throws {
        let a=try file("a.txt"),b=try file("b.txt"),history=TrashHistory(),backend=FakeTrash(directory:trash)
        XCTAssertEqual(history.move([b],root:root,keepers:[b.id:a],backend:backend).tickets.count,1)
        _=history.undo(backend:backend);try FileManager.default.removeItem(at:a.url)
        XCTAssertTrue(history.redo(backend:backend)!.tickets.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath:b.id))
    }
    func testPartialUndoOnlyRedoesRestoredFiles()throws {
        let a=try file("a.txt"),b=try file("b.txt"),history=TrashHistory(),backend=FakeTrash(directory:trash)
        _=history.move([a,b],root:root,backend:backend)
        try Data("keep this new file".utf8).write(to:b.url)
        XCTAssertEqual(history.undo(backend:backend)?.restored,[a.url])
        XCTAssertFalse(history.canUndo,"The conflicting item waits for retry instead of blocking Undo");XCTAssertEqual(history.blockedCount,1);XCTAssertTrue(history.canRedo)
        XCTAssertEqual(history.redo(backend:backend)?.tickets.map{ $0.original },[a.url])
        XCTAssertEqual(try String(contentsOf:b.url),"keep this new file")
    }
    func testHardLinksAreNotExtraCopies()throws{
        let a=try file("a.txt");let link=root.appendingPathComponent("b.txt");try FileManager.default.linkItem(at:a.url,to:link)
        let result=try ExactDuplicates.find([a,try FileRecord(url:link)],root:root,token:CancellationToken())
        XCTAssertTrue(result.groups.isEmpty)
    }
    func testDuplicateHashCanCancel()throws{
        let a=try file("a.txt"),b=try file("b.txt");let t=CancellationToken();t.cancel()
        XCTAssertThrowsError(try ExactDuplicates.find([a,b],root:root,token:t))
    }
    func testSimilarityThresholdAndAspectGuard(){
        let a=ImageFingerprint(bits:0,aspect:1)
        XCTAssertTrue(a.resembles(ImageFingerprint(bits:31,aspect:1)))
        XCTAssertFalse(a.resembles(ImageFingerprint(bits:63,aspect:1)))
        XCTAssertFalse(a.resembles(ImageFingerprint(bits:0,aspect:2)))
    }
    func image(_ name:String,width:Int,height:Int)throws->FileRecord{
        let url=root.appendingPathComponent(name)
        let c=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0..<width {c.setFillColor(CGColor(gray:CGFloat(x)/CGFloat(width),alpha:1));c.fill(CGRect(x:x,y:0,width:1,height:height))}
        let dest=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
        CGImageDestinationAddImage(dest,c.makeImage()!,nil);XCTAssertTrue(CGImageDestinationFinalize(dest));return try FileRecord(url:url)
    }
    func testImageComparisonUsesSyntheticFixturesOnly()throws{
        let a=try image("a.png",width:90,height:80),b=try image("b.png",width:180,height:160),c=try image("c.png",width:160,height:80)
        let result=try SimilarImages.find([a,b,c],root:root,token:CancellationToken())
        XCTAssertEqual(result.groups.count,1);XCTAssertEqual(Set(result.groups[0].members.map(\.id)),[a.id,b.id])
    }
    func testMalformedImageIsSkipped()throws{
        let bad=try file("bad.jpg","not an image")
        let result=try SimilarImages.find([bad],root:root,token:CancellationToken());XCTAssertTrue(result.groups.isEmpty);XCTAssertEqual(result.skipped,1)
    }

    // MARK: Blocked restores
    func testBlockedRestoreDoesNotBlockEarlierBatches()throws {
        let a=try file("a.txt"),b=try file("b.txt"),history=TrashHistory(),backend=FakeTrash(directory:trash)
        _=history.move([a],root:root,backend:backend);_=history.move([b],root:root,backend:backend)
        try Data("new b".utf8).write(to:b.url) // a different file now occupies b's original path
        let first=history.undo(backend:backend)!
        XCTAssertEqual(first.pending.count,1);XCTAssertEqual(history.blockedCount,1)
        XCTAssertTrue(history.canUndo,"The earlier batch must stay reachable")
        XCTAssertEqual(history.undo(backend:backend)?.restored,[a.url])
        XCTAssertFalse(history.canUndo);XCTAssertEqual(history.blockedCount,1)
        XCTAssertEqual(try String(contentsOf:b.url),"new b")
        let stillBlocked=history.retryBlocked(backend:backend)!
        XCTAssertTrue(stillBlocked.restored.isEmpty);XCTAssertEqual(stillBlocked.failures.count,1);XCTAssertEqual(history.blockedCount,1)
        XCTAssertEqual(try String(contentsOf:b.url),"new b","Retry must never overwrite")
        try FileManager.default.removeItem(at:b.url)
        let resolved=history.retryBlocked(backend:backend)!
        XCTAssertEqual(resolved.restored,[b.url]);XCTAssertEqual(history.blockedCount,0);XCTAssertNil(history.retryBlocked(backend:backend))
        XCTAssertEqual(try String(contentsOf:b.url),"test")
        XCTAssertTrue(history.canRedo);XCTAssertEqual(history.redo(backend:backend)?.tickets.map{$0.original},[b.url])
    }
    func testNewMoveKeepsBlockedRestoresAndListsTrashLocations()throws {
        let a=try file("a.txt"),c=try file("c.txt"),history=TrashHistory(),backend=FakeTrash(directory:trash)
        let moved=history.move([a],root:root,backend:backend)
        try Data("occupied".utf8).write(to:a.url);_=history.undo(backend:backend)
        XCTAssertEqual(history.blockedCount,1)
        _=history.move([c],root:root,backend:backend)
        XCTAssertEqual(history.blockedCount,1);XCTAssertFalse(history.canRedo)
        XCTAssertEqual(history.blockedItems.map{$0.trashed},moved.tickets.map{$0.trashed})
        XCTAssertTrue(FileManager.default.fileExists(atPath:moved.tickets[0].trashed.path))
    }
    func testRetryRejectsChangedTrashItem()throws {
        let a=try file("a.txt"),history=TrashHistory(),backend=FakeTrash(directory:trash)
        let moved=history.move([a],root:root,backend:backend)
        try Data("occupied".utf8).write(to:a.url);_=history.undo(backend:backend)
        try FileManager.default.removeItem(at:a.url)
        try Data("tampered".utf8).write(to:moved.tickets[0].trashed)
        XCTAssertTrue(history.retryBlocked(backend:backend)!.restored.isEmpty);XCTAssertEqual(history.blockedCount,1)
        XCTAssertFalse(FileManager.default.fileExists(atPath:a.id))
    }

    // MARK: Storage map
    func testStorageMapAggregatesFoldersAndDirectFiles()throws {
        _=try file("big/video.mov",String(repeating:"v",count:20_000));_=try file("big/nested/clip.mov",String(repeating:"c",count:8_000))
        _=try file("small/note.txt","hi");_=try file("loose.txt",String(repeating:"l",count:5_000))
        let result=try StorageMapper.map(root:root,token:CancellationToken())
        XCTAssertFalse(result.cancelled);let r=result.root
        XCTAssertEqual(r.children.map(\.name),["big","small"],"Children sort by size")
        let big=r.children[0]
        XCTAssertEqual(big.files,2);XCTAssertEqual(big.directFiles,1);XCTAssertEqual(big.children.map(\.name),["nested"])
        XCTAssertEqual(big.bytes,big.directBytes+big.children[0].bytes);XCTAssertGreaterThanOrEqual(big.bytes,28_000)
        XCTAssertEqual(r.bytes,big.bytes+r.children[1].bytes+r.directBytes)
        XCTAssertEqual(r.directFiles,1);XCTAssertEqual(r.files,4);XCTAssertEqual(r.directories,3)
        XCTAssertEqual(big.children[0].trail.map(\.name),[r.name,"big","nested"]);XCTAssertFalse(r.hasCaveats)
    }
    func testStorageMapCountsHardLinksOnceAndDoesNotFollowSymlinks()throws {
        let a=try file("a.bin",String(repeating:"a",count:10_000))
        try FileManager.default.linkItem(at:a.url,to:root.appendingPathComponent("a-link.bin"))
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("sym.bin"),withDestinationURL:a.url)
        let outside=base.appendingPathComponent("outside");try FileManager.default.createDirectory(at:outside,withIntermediateDirectories:true)
        try Data(String(repeating:"o",count:50_000).utf8).write(to:outside.appendingPathComponent("o.bin"))
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("outside-link"),withDestinationURL:outside)
        let result=try StorageMapper.map(root:root,token:CancellationToken())
        XCTAssertEqual(result.sharedFiles,1);XCTAssertEqual(result.root.files,2)
        XCTAssertEqual(result.root.bytes,a.allocatedBytes,"Hard-linked data counts once; links add nothing")
        XCTAssertTrue(result.root.children.isEmpty,"A symlinked folder is not entered")
    }
    func testStorageMapMeasuresPackagesWithoutOpeningThem()throws {
        _=try file("Album.app/Contents/big.bin",String(repeating:"p",count:12_000));_=try file("Album.app/Contents/Resources/x.txt","x")
        let result=try StorageMapper.map(root:root,token:CancellationToken())
        let package=result.root.children[0]
        XCTAssertTrue(package.isPackage);XCTAssertTrue(package.children.isEmpty)
        XCTAssertEqual(package.files,2);XCTAssertGreaterThanOrEqual(package.bytes,12_000);XCTAssertEqual(result.root.bytes,package.bytes)
    }
    func testStorageMapReportsUnreadableAndHiddenFolders()throws {
        _=try file(".cache/blob.bin",String(repeating:"h",count:4_000))
        let locked=root.appendingPathComponent("locked");try FileManager.default.createDirectory(at:locked,withIntermediateDirectories:true)
        try FileManager.default.setAttributes([.posixPermissions:0],ofItemAtPath:locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:locked.path) }
        let result=try StorageMapper.map(root:root,token:CancellationToken())
        XCTAssertEqual(result.root.inaccessible,1);XCTAssertTrue(result.root.hasCaveats)
        let lockedNode=try XCTUnwrap(result.root.children.first{$0.name=="locked"})
        XCTAssertTrue(lockedNode.isUnreadable);XCTAssertEqual(lockedNode.bytes,0)
        XCTAssertTrue(try XCTUnwrap(result.root.children.first{$0.name==".cache"}).isHidden)
    }
    func testStorageMapCancelledReturnsConsistentPartialResult()throws {
        for i in 0..<600 { _=try file("d\(i%20)/f\(i).txt","x") }
        let token=CancellationToken();token.cancel()
        let result=try StorageMapper.map(root:root,token:token)
        XCTAssertTrue(result.cancelled);XCTAssertLessThan(result.root.files,600)
        XCTAssertEqual(result.root.files,result.root.directFiles+result.root.children.reduce(0){$0+$1.files})
        XCTAssertFalse(try StorageMapper.map(root:root,token:CancellationToken()).cancelled)
    }
    func testStorageMapSkippedFolderAtDepthTwoKeepsHierarchy()throws {
        // fts re-reports a skipped directory as FTS_DP; the walker must not pop its parent early.
        _=try file("a/one.bin",String(repeating:"1",count:5_000));_=try file("a/mnt/inside.bin",String(repeating:"m",count:50_000))
        _=try file("a/two.bin",String(repeating:"2",count:5_000));_=try file("a/sub/g.bin",String(repeating:"g",count:5_000));_=try file("b/three.bin","3")
        let mount=root.appendingPathComponent("a/mnt").path
        let result=try StorageMapper.map(root:root,token:CancellationToken(),progress:{_,_ in},treatAsOtherVolume:{ $0 == mount })
        let a=try XCTUnwrap(result.root.children.first{$0.name=="a"})
        XCTAssertEqual(result.root.directFiles,0);XCTAssertEqual(result.root.children.map(\.name),["a","b"])
        XCTAssertEqual(a.files,3);XCTAssertEqual(a.directFiles,2);XCTAssertEqual(a.directories,1);XCTAssertEqual(a.otherVolumes,1)
        XCTAssertEqual(a.children.map(\.name),["sub"]);XCTAssertEqual(a.bytes,a.directBytes+a.children[0].bytes);XCTAssertLessThan(a.bytes,50_000)
        XCTAssertEqual(result.root.bytes,a.bytes+result.root.children[1].bytes)
    }
    func testStorageMapNestedUnreadableFolderKeepsHierarchy()throws {
        _=try file("a/one.bin","1");_=try file("a/after.bin","2");_=try file("b/x.bin","3")
        let locked=root.appendingPathComponent("a/locked");try FileManager.default.createDirectory(at:locked,withIntermediateDirectories:true)
        try FileManager.default.setAttributes([.posixPermissions:0],ofItemAtPath:locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:locked.path) }
        let result=try StorageMapper.map(root:root,token:CancellationToken())
        let a=try XCTUnwrap(result.root.children.first{$0.name=="a"})
        XCTAssertEqual(result.root.directFiles,0);XCTAssertEqual(a.directFiles,2);XCTAssertEqual(a.inaccessible,1)
        XCTAssertEqual(a.children.map(\.name),["locked"]);XCTAssertTrue(a.children[0].isUnreadable)
        XCTAssertEqual(result.root.children.map(\.name).sorted(),["a","b"])
    }
    func testBlockedTicketWhoseTrashItemVanishedIsReportedNotStuck()throws {
        let a=try file("a.txt"),history=TrashHistory(),backend=FakeTrash(directory:trash)
        let moved=history.move([a],root:root,backend:backend)
        try Data("occupied".utf8).write(to:a.url);_=history.undo(backend:backend)
        XCTAssertEqual(history.blockedCount,1)
        try FileManager.default.removeItem(at:moved.tickets[0].trashed) // restored in Finder or Trash emptied
        let retry=history.retryBlocked(backend:backend)!
        XCTAssertTrue(retry.restored.isEmpty);XCTAssertEqual(retry.failures.count,1);XCTAssertTrue(retry.failures[0].message.contains("no longer in Trash"))
        XCTAssertEqual(history.blockedCount,0);XCTAssertNil(history.retryBlocked(backend:backend))
        XCTAssertEqual(try String(contentsOf:a.url),"occupied")
    }
    func testRetryRejectsChangedTrashItemAndKeepsIt()throws {
        let a=try file("a.txt"),history=TrashHistory(),backend=FakeTrash(directory:trash)
        let moved=history.move([a],root:root,backend:backend)
        try Data("occupied".utf8).write(to:a.url);_=history.undo(backend:backend);try FileManager.default.removeItem(at:a.url)
        try Data("tampered".utf8).write(to:moved.tickets[0].trashed)
        XCTAssertTrue(history.retryBlocked(backend:backend)!.restored.isEmpty);XCTAssertEqual(history.blockedCount,1)
        XCTAssertEqual(try String(contentsOf:moved.tickets[0].trashed),"tampered","The ticket and its Trash item are kept")
    }
    func testChatFoldersClassifyByFolderNameOnly()throws {
        let group=try file("Message/Media/120363012345678901@g.us/Video/clip.mp4")
        let personal=try file("Message/Media/972500000000@s.whatsapp.net/Image/pic.jpg")
        let lid=try file("Message/Media/123456789@lid/doc.pdf");let status=try file("Message/Media/status@broadcast/a.jpg")
        let plain=try file("Downloads/notes@g.us.txt") // a file name is never a chat folder
        XCTAssertEqual(ChatFolders.kind(of:group.url),.group);XCTAssertEqual(ChatFolders.kind(of:personal.url),.personal)
        XCTAssertEqual(ChatFolders.kind(of:lid.url),.personal);XCTAssertEqual(ChatFolders.kind(of:status.url),.broadcast);XCTAssertNil(ChatFolders.kind(of:plain.url))
        XCTAssertEqual(ChatFolders.filter([group,personal,lid,status,plain],kind:.personal).map(\.name),["pic.jpg","doc.pdf"])
    }
    func syntheticChatDatabase(at url:URL,rows:[(String,String)],schema:String="CREATE TABLE ZWACHATSESSION (Z_PK INTEGER PRIMARY KEY, ZCONTACTJID TEXT, ZPARTNERNAME TEXT, ZSESSIONTYPE INTEGER)")throws {
        var db:OpaquePointer?;XCTAssertEqual(sqlite3_open(url.path,&db),SQLITE_OK);defer{sqlite3_close(db)}
        XCTAssertEqual(sqlite3_exec(db,schema,nil,nil,nil),SQLITE_OK)
        for (jid,name) in rows { XCTAssertEqual(sqlite3_exec(db,"INSERT INTO ZWACHATSESSION (ZCONTACTJID, ZPARTNERNAME) VALUES ('\(jid)', '\(name.replacingOccurrences(of:"'",with:"''"))')",nil,nil,nil),SQLITE_OK) }
    }
    func testChatDirectoryReadsNamesFromSyntheticDatabaseOnly()throws {
        let container=root.appendingPathComponent("Container");let media=container.appendingPathComponent("Message/Media",isDirectory:true)
        try FileManager.default.createDirectory(at:media.appendingPathComponent("120363@g.us"),withIntermediateDirectories:true)
        try syntheticChatDatabase(at:container.appendingPathComponent(ChatDirectory.databaseName),rows:[("120363@G.US","Family trip"),("972500000000@s.whatsapp.net","Dana"),("status@broadcast",""),("unknown-thing","x")])
        XCTAssertEqual(ChatDirectory.databaseURL(near:media.appendingPathComponent("120363@g.us"))?.lastPathComponent,ChatDirectory.databaseName)
        XCTAssertNil(ChatDirectory.databaseURL(near:base))
        let chats=try ChatDirectory.load(from:container.appendingPathComponent(ChatDirectory.databaseName))
        XCTAssertEqual(chats["120363@g.us"],ChatInfo(identifier:"120363@g.us",name:"Family trip",kind:.group))
        XCTAssertEqual(chats["972500000000@s.whatsapp.net"]?.name,"Dana");XCTAssertEqual(chats["status@broadcast"]?.name,"status@broadcast");XCTAssertNil(chats["unknown-thing"])
        let file=try self.file("Container/Message/Media/120363@g.us/Video/clip.mp4")
        XCTAssertEqual(ChatDirectory.identifier(of:file.url),"120363@g.us");XCTAssertNil(ChatDirectory.identifier(of:root.appendingPathComponent("plain.txt")))
        // Read-only: the database bytes are unchanged and no write-ahead files appear.
        let before=try Data(contentsOf:container.appendingPathComponent(ChatDirectory.databaseName));_=try ChatDirectory.load(from:container.appendingPathComponent(ChatDirectory.databaseName))
        XCTAssertEqual(try Data(contentsOf:container.appendingPathComponent(ChatDirectory.databaseName)),before)
        XCTAssertFalse(FileManager.default.fileExists(atPath:container.appendingPathComponent(ChatDirectory.databaseName+"-wal").path))
    }
    func testChatDirectoryRejectsUnknownSchemaAndMissingFile()throws {
        let db=root.appendingPathComponent(ChatDirectory.databaseName)
        try syntheticChatDatabase(at:db,rows:[],schema:"CREATE TABLE ZWACHATSESSION (Z_PK INTEGER PRIMARY KEY, ZSOMETHING TEXT)")
        XCTAssertThrowsError(try ChatDirectory.load(from:db)) { XCTAssertEqual($0 as? ChatDirectoryError,.unexpectedSchema) }
        XCTAssertThrowsError(try ChatDirectory.load(from:root.appendingPathComponent("missing.sqlite")))
    }
    func testStorageMapRejectsMissingRootsAndFiles()throws {
        XCTAssertThrowsError(try StorageMapper.map(root:root.appendingPathComponent("missing"),token:CancellationToken()))
        let f=try file("x.txt");XCTAssertThrowsError(try StorageMapper.map(root:f.url,token:CancellationToken()))
        let sealed=root.appendingPathComponent("sealed");try FileManager.default.createDirectory(at:sealed,withIntermediateDirectories:true)
        try FileManager.default.setAttributes([.posixPermissions:0],ofItemAtPath:sealed.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:sealed.path) }
        XCTAssertThrowsError(try StorageMapper.map(root:sealed,token:CancellationToken())) { XCTAssertEqual($0 as? TriageError,.inaccessible) }
    }
}
