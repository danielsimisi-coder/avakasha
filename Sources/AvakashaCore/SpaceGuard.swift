import Foundation

/// One day's numbers: free space on the startup disk and, when something was measured that day, sizes by key
/// ("loc:<catalogue id>" for known locations, "home:<folder>" for the home folder's own folders). Sizes only, never contents.
public struct SpaceSample: Codable, Equatable {
    public var date: Date
    public var free: Int64
    public var sizes: [String: Int64]
    public init(date: Date, free: Int64, sizes: [String: Int64] = [:]) { self.date = date; self.free = free; self.sizes = sizes }
}

/// What grew between two samples: the change in free space and the keys that grew the most.
public struct SpaceGrowth: Equatable {
    public let since: Date
    public let freeChange: Int64
    public let grown: [(key: String, delta: Int64)]
    public static func == (a: SpaceGrowth, b: SpaceGrowth) -> Bool { a.since == b.since && a.freeChange == b.freeChange && a.grown.map(\.key) == b.grown.map(\.key) && a.grown.map(\.delta) == b.grown.map(\.delta) }
}

/// A local, bounded history: one sample per day, at most `limit` days. Kept only while the user has the space guard or the weekly check on.
public struct SpaceHistory: Codable, Equatable {
    public private(set) var samples: [SpaceSample] = []
    public static let limit = 180
    public init(samples: [SpaceSample] = []) { self.samples = samples.sorted { $0.date < $1.date } }

    /// Adds today's numbers; a second sample on the same day updates free space and merges sizes into the first.
    public mutating func record(_ sample: SpaceSample, calendar: Calendar = .current) {
        if let last = samples.last, calendar.isDate(last.date, inSameDayAs: sample.date) {
            var merged = last; merged.date = sample.date; merged.free = sample.free
            merged.sizes.merge(sample.sizes) { _, new in new }
            samples[samples.count - 1] = merged
        } else {
            samples.append(sample); samples.sort { $0.date < $1.date }
        }
        if samples.count > Self.limit { samples.removeFirst(samples.count - Self.limit) }
    }

    /// Growth from the newest sample back to the latest sample at least `days` old (or the oldest one), comparing only keys measured in both.
    public func growth(days: Int = 7, now: Date = Date(), top: Int = 3, minimum: Int64 = 100_000_000) -> SpaceGrowth? {
        guard let newest = samples.last, samples.count >= 2 else { return nil }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let older = samples.dropLast().last { $0.date <= cutoff } ?? samples.first!
        guard older.date < newest.date else { return nil }
        // Sizes come from different days' measurements; use the newest value of each key and the older sample's value for the same key.
        var latest: [String: Int64] = [:]
        for s in samples where s.date > older.date { latest.merge(s.sizes) { _, new in new } }
        let grown = latest.compactMap { key, value -> (key: String, delta: Int64)? in
            guard let before = older.sizes[key] else { return nil }
            let delta = value - before
            return delta >= minimum ? (key, delta) : nil
        }.sorted { $0.delta == $1.delta ? $0.key < $1.key : $0.delta > $1.delta }
        return SpaceGrowth(since: older.date, freeChange: newest.free - older.free, grown: Array(grown.prefix(top)))
    }
}

public enum SpaceHistoryStore {
    public static func load(from url: URL) -> SpaceHistory {
        guard let data = try? Data(contentsOf: url), let history = try? JSONDecoder().decode(SpaceHistory.self, from: data) else { return SpaceHistory() }
        return history
    }
    public static func save(_ history: SpaceHistory, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(history).write(to: url, options: .atomic)
    }
}

public enum SpaceForecast {
    /// Days until free space falls below `floor` at the pace of the last `window` days (least squares over daily samples),
    /// or nil when there are too few samples, they span under three days, or free space is not shrinking.
    public static func daysUntil(floor: Int64, history: SpaceHistory, now: Date = Date(), window: Int = 30) -> Double? {
        let start = now.addingTimeInterval(-Double(window) * 86_400)
        let points = history.samples.filter { $0.date >= start }.map { ($0.date.timeIntervalSince(now) / 86_400, Double($0.free)) }
        guard points.count >= 3, let first = points.first, let last = points.last, last.0 - first.0 >= 3 else { return nil }
        let n = Double(points.count)
        let mx = points.map(\.0).reduce(0, +) / n, my = points.map(\.1).reduce(0, +) / n
        let sxx = points.map { ($0.0 - mx) * ($0.0 - mx) }.reduce(0, +)
        guard sxx > 0 else { return nil }
        let slope = points.map { ($0.0 - mx) * ($0.1 - my) }.reduce(0, +) / sxx // bytes per day
        guard slope < -1_000_000 else { return nil } // shrinking by more than 1 MB a day
        let current = my + slope * (0 - mx)
        let days = (Double(floor) - current) / slope
        return max(0, days)
    }
}

/// One candidate step for a plan: a Free up space row, its size, and whether the app may move it to Trash.
public struct PlanItem: Equatable {
    public let id: String
    public let bytes: Int64
    public let movable: Bool
    public init(id: String, bytes: Int64, movable: Bool) { self.id = id; self.bytes = bytes; self.movable = movable }
}

/// The safest way to reach a target: only data the owning apps rebuild goes into the plan, largest first so the plan has few steps;
/// anything else is only suggested for review. The plan is a proposal; every move still goes through the confirmation.
public struct CleanupPlan: Equatable {
    public let target: Int64
    public let steps: [PlanItem]
    public let reviewSuggestions: [PlanItem]
    public var total: Int64 { steps.reduce(0) { $0 + $1.bytes } }
    public var shortfall: Int64 { max(0, target - total) }

    public static func make(target: Int64, items: [PlanItem], suggestions limit: Int = 3) -> CleanupPlan {
        var remaining = items.filter { $0.movable && $0.bytes > 0 }.sorted { $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes }
        var steps: [PlanItem] = [], total: Int64 = 0
        while total < target, !remaining.isEmpty {
            // The smallest item that closes the gap ends the plan; otherwise take the largest, so the plan has few steps.
            let gap = target - total
            let next = remaining.filter { $0.bytes >= gap }.min { $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes < $1.bytes } ?? remaining[0]
            remaining.removeAll { $0 == next }; steps.append(next); total += next.bytes
        }
        let rest = total >= target ? [] : Array(items.filter { !$0.movable && $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }.prefix(limit))
        return CleanupPlan(target: target, steps: steps, reviewSuggestions: rest)
    }
}

public enum SpaceGuard {
    /// When to speak up: below the floor, or the forecast reaches it within `horizon` days. The app adds a quiet period between notices.
    public static func needsAttention(free: Int64, floor: Int64, forecastDays: Double?, horizon: Double = 7) -> Bool {
        floor > 0 && (free < floor || (forecastDays.map { $0 <= horizon } ?? false))
    }
    /// How much to plan for: back above the floor with a 10% margin, and at least 5 GB so a plan is worth a notification.
    public static func target(free: Int64, floor: Int64) -> Int64 { max(5_000_000_000, Int64(Double(max(0, floor - free)) * 1.1)) }
}
