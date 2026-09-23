import XCTest
@testable import AvakashaCore

final class SpaceGuardTests: XCTestCase {
    let day: TimeInterval = 86_400
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let gb: Int64 = 1_000_000_000

    func testHistoryKeepsOneSamplePerDayAndMergesSizes() {
        var h = SpaceHistory()
        h.record(SpaceSample(date: now.addingTimeInterval(-3600), free: 100 * gb, sizes: ["home:Downloads": 5 * gb]))
        h.record(SpaceSample(date: now, free: 99 * gb, sizes: ["loc:xcode.derivedData": 2 * gb]))
        XCTAssertEqual(h.samples.count, 1)
        XCTAssertEqual(h.samples[0].free, 99 * gb)
        XCTAssertEqual(h.samples[0].sizes, ["home:Downloads": 5 * gb, "loc:xcode.derivedData": 2 * gb])
        for i in 1...200 { h.record(SpaceSample(date: now.addingTimeInterval(Double(i) * day), free: gb)) }
        XCTAssertEqual(h.samples.count, SpaceHistory.limit, "Bounded")
    }
    func testGrowthComparesKeysMeasuredOnBothDays() {
        var h = SpaceHistory()
        h.record(SpaceSample(date: now.addingTimeInterval(-8 * day), free: 100 * gb, sizes: ["home:Downloads": 5 * gb, "loc:xcode.derivedData": 2 * gb, "home:Movies": 10 * gb]))
        h.record(SpaceSample(date: now.addingTimeInterval(-3 * day), free: 95 * gb, sizes: ["loc:xcode.derivedData": 9 * gb]))
        h.record(SpaceSample(date: now, free: 90 * gb, sizes: ["home:Downloads": 6 * gb, "home:Music": 3 * gb, "home:Movies": 10 * gb]))
        let g = try! XCTUnwrap(h.growth(days: 7, now: now))
        XCTAssertEqual(g.freeChange, -10 * gb)
        XCTAssertEqual(g.grown.map(\.key), ["loc:xcode.derivedData", "home:Downloads"], "Music has no earlier size; Movies did not grow")
        XCTAssertEqual(g.grown.map(\.delta), [7 * gb, 1 * gb])
        XCTAssertNil(SpaceHistory(samples: [SpaceSample(date: now, free: 1)]).growth(now: now))
    }
    func testForecast() {
        var h = SpaceHistory()
        for i in 0..<10 { h.record(SpaceSample(date: now.addingTimeInterval(Double(i - 9) * day), free: (100 - Int64(i) * 2) * gb)) } // 2 GB a day, 82 GB now
        let days = try! XCTUnwrap(SpaceForecast.daysUntil(floor: 40 * gb, history: h, now: now))
        XCTAssertEqual(days, 21, accuracy: 0.5)
        var steady = SpaceHistory()
        for i in 0..<10 { steady.record(SpaceSample(date: now.addingTimeInterval(Double(i - 9) * day), free: 100 * gb)) }
        XCTAssertNil(SpaceForecast.daysUntil(floor: 40 * gb, history: steady, now: now), "Not shrinking: no forecast")
        var short = SpaceHistory()
        for i in 0..<2 { short.record(SpaceSample(date: now.addingTimeInterval(Double(i - 1) * day), free: (100 - Int64(i) * 10) * gb)) }
        XCTAssertNil(SpaceForecast.daysUntil(floor: 40 * gb, history: short, now: now), "Too little history")
        XCTAssertEqual(SpaceForecast.daysUntil(floor: 90 * gb, history: h, now: now), 0, "Already below the floor")
    }
    func testPlanUsesOnlyMovableItemsAndFewSteps() {
        let items = [PlanItem(id: "a", bytes: 20 * gb, movable: true), PlanItem(id: "b", bytes: 8 * gb, movable: true), PlanItem(id: "c", bytes: 3 * gb, movable: true),
                     PlanItem(id: "mail", bytes: 50 * gb, movable: false), PlanItem(id: "old", bytes: 12 * gb, movable: false)]
        let plan = CleanupPlan.make(target: 22 * gb, items: items)
        XCTAssertEqual(plan.steps.map(\.id), ["a", "c"], "20 GB, then the smallest item that closes the gap")
        XCTAssertEqual(plan.total, 23 * gb); XCTAssertEqual(plan.shortfall, 0); XCTAssertTrue(plan.reviewSuggestions.isEmpty)
        XCTAssertEqual(CleanupPlan.make(target: 5 * gb, items: items).steps.map(\.id), ["b"])
        let short = CleanupPlan.make(target: 60 * gb, items: items)
        XCTAssertEqual(short.steps.map(\.id), ["a", "b", "c"]); XCTAssertEqual(short.shortfall, 29 * gb)
        XCTAssertEqual(short.reviewSuggestions.map(\.id), ["mail", "old"], "The rest is only suggested for review")
        XCTAssertFalse(short.steps.contains { !$0.movable })
    }
    func testGuardDecision() {
        XCTAssertTrue(SpaceGuard.needsAttention(free: 30 * gb, floor: 40 * gb, forecastDays: nil))
        XCTAssertTrue(SpaceGuard.needsAttention(free: 60 * gb, floor: 40 * gb, forecastDays: 5))
        XCTAssertFalse(SpaceGuard.needsAttention(free: 60 * gb, floor: 40 * gb, forecastDays: 30))
        XCTAssertFalse(SpaceGuard.needsAttention(free: 10 * gb, floor: 0, forecastDays: 1), "No floor set: never")
        XCTAssertEqual(SpaceGuard.target(free: 30 * gb, floor: 40 * gb), 11 * gb)
        XCTAssertEqual(SpaceGuard.target(free: 60 * gb, floor: 40 * gb), 5 * gb)
    }
    func testStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("avakasha-history-" + UUID().uuidString).appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var h = SpaceHistory(); h.record(SpaceSample(date: now, free: 5, sizes: ["home:A": 1]))
        try SpaceHistoryStore.save(h, to: url)
        XCTAssertEqual(SpaceHistoryStore.load(from: url), h)
        XCTAssertEqual(SpaceHistoryStore.load(from: url.appendingPathExtension("missing")), SpaceHistory())
    }
}
