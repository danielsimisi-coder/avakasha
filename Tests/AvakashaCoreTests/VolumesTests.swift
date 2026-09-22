import XCTest
@testable import AvakashaCore

final class VolumesTests: XCTestCase {
    func testTemporaryDirectoryVolumeHasCapacity() throws {
        let info = try XCTUnwrap(Volumes.info(at: FileManager.default.temporaryDirectory))
        XCTAssertFalse(info.name.isEmpty); XCTAssertGreaterThan(info.total, 0); XCTAssertGreaterThanOrEqual(info.available, 0)
        XCTAssertLessThanOrEqual(info.available, info.total); XCTAssertEqual(info.used, info.total - info.available)
        XCTAssertTrue((0...1).contains(info.usedFraction))
    }
    func testMissingPathHasNoVolume() {
        XCTAssertNil(Volumes.info(at: URL(fileURLWithPath: "/definitely/missing/\(UUID().uuidString)")))
    }
    func testMountedVolumesIncludeTheStartupDiskFirst() throws {
        let volumes = Volumes.mounted()
        XCTAssertFalse(volumes.isEmpty); XCTAssertTrue(volumes[0].isStartup)
        XCTAssertEqual(Set(volumes.map(\.url.path)).count, volumes.count, "Each volume appears once")
        XCTAssertTrue(volumes.allSatisfy { $0.total > 0 && !$0.name.isEmpty })
    }
    func testFractionsAreClamped() {
        let odd = VolumeInfo(url: URL(fileURLWithPath: "/x"), name: "x", total: 10, available: 20, isInternal: true, isRemovable: false, isStartup: false)
        XCTAssertEqual(odd.used, 0); XCTAssertEqual(odd.usedFraction, 0)
        let empty = VolumeInfo(url: URL(fileURLWithPath: "/y"), name: "y", total: 0, available: 0, isInternal: true, isRemovable: false, isStartup: false)
        XCTAssertEqual(empty.usedFraction, 0)
    }
}
