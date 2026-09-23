import XCTest
@testable import AvakashaCore

final class HomeDuplicatesTests: XCTestCase {
    var home: URL!
    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("avakasha-homedup-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }
    func put(_ relative: String, _ data: Data) throws {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
    func blob(_ seed: UInt8, _ size: Int = 300_000) -> Data { Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 7) ^ seed }) }

    func testFindsCopiesAcrossFoldersAndSkipsAppData() throws {
        try put("Downloads/video.mov", blob(1)); try put("Documents/Projects/video copy.mov", blob(1)); try put("Desktop/video.mov", blob(1))
        try put("Downloads/other.mov", blob(2)) // same size, different bytes
        var middle = blob(3); try put("Documents/a.bin", middle); middle[150_000] ^= 0xFF; try put("Documents/b.bin", middle) // same head and tail, different middle
        try put("Library/Caches/app/video.mov", blob(1)); try put(".hidden/video.mov", blob(1)); try put("Pictures/Photos Library.photoslibrary/originals/video.mov", blob(1))
        try put("Downloads/small1.txt", Data(repeating: 1, count: 10)); try put("Downloads/small2.txt", Data(repeating: 1, count: 10)) // under the minimum
        try FileManager.default.linkItem(at: home.appendingPathComponent("Downloads/other.mov"), to: home.appendingPathComponent("Documents/other hard link.mov"))
        let result = try HomeDuplicates.find(in: home, minimumBytes: 100_000)
        XCTAssertEqual(result.groups.count, 1, "\(result.groups.map { $0.members.map(\.name) })")
        let names = Set(result.groups[0].members.map { $0.url.path.replacingOccurrences(of: home.resolvingSymlinksInPath().path + "/", with: "") })
        XCTAssertEqual(names, ["Downloads/video.mov", "Documents/Projects/video copy.mov", "Desktop/video.mov"], "Library, hidden folders and bundles are never searched; hard links are not copies")
        XCTAssertEqual(HomeDuplicates.extraBytes(result.groups), result.groups[0].extras.reduce(0) { $0 + $1.allocatedBytes })
    }
    func testSameSizeNeedsNoContents() throws {
        try put("A/x.bin", blob(4)); try put("B/y.bin", blob(5)); try put("C/z.bin", blob(6, 200_000))
        let same = try HomeDuplicates.sameSizeFiles(in: home, minimumBytes: 100_000)
        XCTAssertEqual(Set(same.map(\.lastPathComponent)), ["x.bin", "y.bin"])
        XCTAssertNotEqual(HomeDuplicates.fingerprint(same[0]), HomeDuplicates.fingerprint(same[1]))
    }
    func testCancel() throws {
        try put("A/x.bin", blob(1)); let token = CancellationToken(); token.cancel()
        XCTAssertThrowsError(try HomeDuplicates.find(in: home, token: token))
    }
}
