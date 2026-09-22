import XCTest
import Foundation
@testable import AvakashaCore

final class InstallersTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root=FileManager.default.temporaryDirectory.appendingPathComponent("AvakashaInstallers-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at:root) }
    func file(_ name:String,modified:Date?=nil) throws -> FileRecord {
        let url=root.appendingPathComponent(name);try Data("synthetic".utf8).write(to:url)
        if let modified { try FileManager.default.setAttributes([.modificationDate:modified],ofItemAtPath:url.path) }
        return try FileRecord(url:url)
    }
    func testDiskImageExtensions(){
        for e in ["dmg","iso","sparseimage"] { XCTAssertEqual(ReviewQuery.installerKind(URL(fileURLWithPath:"/x/a."+e)),.diskImage,e) }
    }
    func testPackageExtensions(){
        for e in ["pkg","mpkg","xip"] { XCTAssertEqual(ReviewQuery.installerKind(URL(fileURLWithPath:"/x/a."+e)),.package,e) }
    }
    func testArchiveExtensions(){
        for e in ["zip","tar","gz","tgz","bz2","xz","rar","7z"] { XCTAssertEqual(ReviewQuery.installerKind(URL(fileURLWithPath:"/x/a."+e)),.archive,e) }
        XCTAssertEqual(ReviewQuery.installerKind(URL(fileURLWithPath:"/x/backup.tar.gz")),.archive)
    }
    func testExtensionMatchingIsCaseInsensitive(){
        XCTAssertEqual(ReviewQuery.installerKind(URL(fileURLWithPath:"/x/Setup.DMG")),.diskImage)
        XCTAssertEqual(ReviewQuery.installerKind(URL(fileURLWithPath:"/x/Tool.Pkg")),.package)
        XCTAssertEqual(ReviewQuery.installerKind(URL(fileURLWithPath:"/x/Photos.ZIP")),.archive)
        XCTAssertEqual(ReviewQuery.installerKind(URL(fileURLWithPath:"/x/Photos.Tar.GZ")),.archive)
    }
    func testNonInstallersAreNil(){
        for name in ["a.jpg","b.pdf","c.txt","d.app","e","f.dmg.txt","g.zipx"] { XCTAssertNil(ReviewQuery.installerKind(URL(fileURLWithPath:"/x/"+name)),name) }
    }
    func testInstallersExcludesNonInstallersAndRespectsCutoffBoundary()throws{
        let cutoff=Date(timeIntervalSince1970:1_600_000_000)
        let older=try file("old.dmg",modified:cutoff.addingTimeInterval(-1))
        let equal=try file("equal.pkg",modified:cutoff)
        let newer=try file("new.zip",modified:cutoff.addingTimeInterval(1))
        let photo=try file("photo.jpg",modified:cutoff.addingTimeInterval(-86_400))
        XCTAssertEqual(ReviewQuery.installers([photo,newer,equal,older],olderThan:cutoff).map(\.id),[older.id])
    }
    func testInstallersPreservesInputOrder()throws{
        let past=Date(timeIntervalSince1970:946_684_800);let cutoff=Date(timeIntervalSince1970:1_600_000_000)
        let z=try file("z.zip",modified:past),a=try file("a.dmg",modified:past),m=try file("m.pkg",modified:past)
        let doc=try file("notes.txt",modified:past)
        XCTAssertEqual(ReviewQuery.installers([z,doc,a,m],olderThan:cutoff).map(\.name),["z.zip","a.dmg","m.pkg"])
        XCTAssertEqual(ReviewQuery.installers([m,a,z],olderThan:cutoff).map(\.name),["m.pkg","a.dmg","z.zip"])
        XCTAssertTrue(ReviewQuery.installers([],olderThan:cutoff).isEmpty)
    }
}
