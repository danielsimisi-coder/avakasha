import XCTest
@testable import AvakashaCore

final class SystemDataTests: XCTestCase {
    func testSnapshotListingIsReadOnlyAndWellFormed() throws {
        // The startup disk's Data volume: the listing may be empty; every entry has a name and a plausible date.
        guard let startup = Volumes.mounted().first(where: \.isStartup) else { throw XCTSkip("No startup volume") }
        let snapshots = LocalSnapshots.list(on: LocalSnapshots.dataVolume(for: startup))
        for s in snapshots { XCTAssertFalse(s.name.isEmpty); XCTAssertGreaterThan(s.created.timeIntervalSince1970, 1_400_000_000) }
        XCTAssertEqual(snapshots, snapshots.sorted { $0.created > $1.created })
        XCTAssertTrue(LocalSnapshots.list(on: URL(fileURLWithPath: "/nonexistent-avakasha")).isEmpty)
        XCTAssertTrue(LocalSnapshot(name: "com.apple.TimeMachine.2026-09-23-101010.local", created: Date()).isTimeMachine)
        XCTAssertFalse(LocalSnapshot(name: "com.apple.os.update-ABC", created: Date()).isTimeMachine)
        XCTAssertFalse(LocalSnapshot(name: "com.apple.TimeMachine.2026-09-23-101010.backup", created: Date()).isTimeMachine, "Snapshots on a backup disk are not local ones")
    }
    func testPurgeableIsNeverNegative() throws {
        for v in Volumes.mounted() { XCTAssertGreaterThanOrEqual(v.purgeable, 0); XCTAssertLessThanOrEqual(v.purgeable, v.total) }
    }
    func testWeeklyCheckTiming() {
        let now = Date()
        XCTAssertTrue(SpaceWatch.isDue(last: nil, now: now))
        XCTAssertFalse(SpaceWatch.isDue(last: now.addingTimeInterval(-6 * 24 * 3600), now: now))
        XCTAssertTrue(SpaceWatch.isDue(last: now.addingTimeInterval(-7 * 24 * 3600), now: now))
    }
    func testWeeklyReportOnlyWhenWorthIt() {
        XCTAssertNil(SpaceWatch.weeklyReport(previous: nil, current: 1_000_000_000), "Under 2 GB: no notification")
        XCTAssertEqual(SpaceWatch.weeklyReport(previous: nil, current: 5_000_000_000), .canGo(bytes: 5_000_000_000, grew: nil))
        XCTAssertNil(SpaceWatch.weeklyReport(previous: 5_000_000_000, current: 5_500_000_000), "Grew less than 1 GB: stay quiet")
        XCTAssertEqual(SpaceWatch.weeklyReport(previous: 5_000_000_000, current: 8_000_000_000), .canGo(bytes: 8_000_000_000, grew: 3_000_000_000))
        XCTAssertNil(SpaceWatch.weeklyReport(previous: 9_000_000_000, current: 4_000_000_000), "Shrank: nothing to say")
    }
    func testLowSpace() {
        let now = Date()
        XCTAssertTrue(SpaceWatch.isLow(available: 10_000_000_000, total: 500_000_000_000))
        XCTAssertFalse(SpaceWatch.isLow(available: 20_000_000_000, total: 250_000_000_000), "8% but 20 GB: fine")
        XCTAssertTrue(SpaceWatch.isLow(available: 11_000_000_000, total: 128_000_000_000), "Under 10% of a small disk")
        XCTAssertFalse(SpaceWatch.isLow(available: 190_000_000_000, total: 2_000_000_000_000), "A large disk under 10% but with 190 GB free never warns")
        XCTAssertFalse(SpaceWatch.isLow(available: 160_000_000_000, total: 500_000_000_000))
        XCTAssertTrue(SpaceWatch.shouldWarnLowSpace(available: 5_000_000_000, total: 500_000_000_000, lastWarned: nil, now: now))
        XCTAssertFalse(SpaceWatch.shouldWarnLowSpace(available: 5_000_000_000, total: 500_000_000_000, lastWarned: now.addingTimeInterval(-3600), now: now), "At most once a day")
    }
}
