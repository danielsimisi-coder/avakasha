import XCTest
import Foundation
import Darwin
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import FileTriageCore

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
        XCTAssertEqual(bytes.withUnsafeBytes{setxattr(b.id,"org.filetriage.fixture",$0.baseAddress,$0.count,0,0)},0)
        let selection=ExactDuplicates.selectExtras([DuplicateGroup(members:[a,b])],visible:[a.id,b.id])
        XCTAssertTrue(selection.ids.isEmpty)
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
}
