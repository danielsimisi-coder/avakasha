import XCTest
import Foundation
@testable import AvakashaCore

final class ReviewedStoreTests: XCTestCase {
    var base: URL!
    var saved: [[String: String]] = []
    override func setUpWithError() throws {
        base=FileManager.default.temporaryDirectory.appendingPathComponent("ReviewedStoreTests-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true);saved=[]
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at:base) }
    func file(_ name:String,_ data:String="test") throws -> FileRecord {
        let url=base.appendingPathComponent(name);try Data(data.utf8).write(to:url);return try FileRecord(url:url)
    }
    func store(_ initial:[String:String]=[:]) -> ReviewedStore {
        ReviewedStore(load:{initial},save:{[unowned self] in saved.append($0)})
    }
    func encoded(_ r:FileRecord) -> String { "\(r.identity.size):\(r.identity.modifiedSeconds):\(r.identity.modifiedNanos)" }

    func testMarkUnmarkAndCount()throws{
        let a=try file("a.txt"),b=try file("b.txt");let s=store()
        XCTAssertFalse(s.isReviewed(a));XCTAssertEqual(s.count,0)
        s.mark([a,b]);XCTAssertTrue(s.isReviewed(a));XCTAssertTrue(s.isReviewed(b));XCTAssertEqual(s.count,2)
        s.unmark([a]);XCTAssertFalse(s.isReviewed(a));XCTAssertTrue(s.isReviewed(b));XCTAssertEqual(s.count,1)
        s.mark([b]);XCTAssertEqual(s.count,1, "re-marking replaces instead of duplicating")
    }
    func testToggleMarksAllWhenAnyUnreviewedOtherwiseUnmarksAll()throws{
        let a=try file("a.txt"),b=try file("b.txt");let s=store()
        s.mark([a])
        XCTAssertTrue(s.toggle([a,b]));XCTAssertTrue(s.isReviewed(a));XCTAssertTrue(s.isReviewed(b))
        XCTAssertFalse(s.toggle([a,b]));XCTAssertFalse(s.isReviewed(a));XCTAssertFalse(s.isReviewed(b));XCTAssertEqual(s.count,0)
        let before=saved.count;XCTAssertFalse(s.toggle([]));XCTAssertEqual(saved.count,before, "empty toggle neither marks nor saves")
    }
    func testRewrittenFileWithDifferentSizeIsNotReviewed()throws{
        let a=try file("a.txt","short");let s=store();s.mark([a])
        try Data("much longer contents".utf8).write(to:a.url)
        let current=try FileRecord(url:a.url)
        XCTAssertNotEqual(current.identity.size,a.identity.size)
        XCTAssertTrue(s.isReviewed(a), "the stale record still matches its own stored identity")
        XCTAssertFalse(s.isReviewed(current));XCTAssertEqual(s.count,1)
    }
    func testRewrittenFileWithSameSizeDifferentMtimeIsNotReviewed()throws{
        let a=try file("a.txt","same");let s=store();s.mark([a])
        try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:1_000_000)],ofItemAtPath:a.url.path)
        let current=try FileRecord(url:a.url)
        XCTAssertEqual(current.identity.size,a.identity.size);XCTAssertNotEqual(current.identity.modifiedSeconds,a.identity.modifiedSeconds)
        XCTAssertFalse(s.isReviewed(current))
        s.mark([current]);XCTAssertTrue(s.isReviewed(current));XCTAssertFalse(s.isReviewed(a))
    }
    func testForgetRemovesEntriesAndSavesOnlyWhenSomethingChanged()throws{
        let a=try file("a.txt"),b=try file("b.txt"),c=try file("c.txt");let s=store();s.mark([a,b,c])
        let before=saved.count
        s.forget(paths:[a.id,b.id,base.appendingPathComponent("missing.txt").path])
        XCTAssertFalse(s.isReviewed(a));XCTAssertFalse(s.isReviewed(b));XCTAssertTrue(s.isReviewed(c));XCTAssertEqual(s.count,1)
        XCTAssertEqual(saved.count,before+1);XCTAssertEqual(saved.last,[c.id:encoded(c)])
        s.forget(paths:["/nowhere/x.txt"]);XCTAssertEqual(saved.count,before+1, "no-op forget does not save")
    }
    func testMalformedStoredValuesAreIgnored()throws{
        let a=try file("a.txt"),b=try file("b.txt")
        let s=store([a.id:encoded(a), b.id:"garbage", "/x/y.txt":"1:2", "/x/z.txt":"1:2:3:4", "/x/w.txt":"a:b:c", "/x/v.txt":"", "/x/u.txt":"1::3"])
        XCTAssertTrue(s.isReviewed(a));XCTAssertFalse(s.isReviewed(b));XCTAssertEqual(s.count,1)
        XCTAssertTrue(saved.isEmpty, "loading never triggers a save")
    }
    func testLoadedEntriesSurviveAndMatchOnlyIdenticalIdentity()throws{
        let a=try file("a.txt");let s=store([a.id:encoded(a)])
        XCTAssertTrue(s.isReviewed(a))
        let s2=store([a.id:"\(a.identity.size+1):\(a.identity.modifiedSeconds):\(a.identity.modifiedNanos)"])
        XCTAssertFalse(s2.isReviewed(a))
        let s3=store([a.id:"\(a.identity.size):\(a.identity.modifiedSeconds):\(a.identity.modifiedNanos+1)"])
        XCTAssertFalse(s3.isReviewed(a))
    }
    func testSaveReceivesFullDictionaryOnEveryChange()throws{
        let a=try file("a.txt"),b=try file("b.txt");let s=store()
        s.mark([a]);XCTAssertEqual(saved.last,[a.id:encoded(a)])
        s.mark([b]);XCTAssertEqual(saved.last,[a.id:encoded(a),b.id:encoded(b)])
        s.unmark([a]);XCTAssertEqual(saved.last,[b.id:encoded(b)])
        s.toggle([b]);XCTAssertEqual(saved.last,[:])
        XCTAssertEqual(saved.count,4)
        s.mark([]);XCTAssertEqual(saved.count,4, "empty mark does not save")
    }
}
