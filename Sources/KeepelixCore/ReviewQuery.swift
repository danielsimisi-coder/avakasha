import Foundation

public enum ReviewSort: Int, CaseIterable {
    case largest, smallest, oldest, newest, name, nameDescending
}

public enum ReviewQuery {
    public static func older(_ files: [FileRecord], than cutoff: Date) -> [FileRecord] {
        files.filter { Date(timeIntervalSince1970: Double($0.identity.modifiedSeconds)) < cutoff }
    }

    public static func sorted(_ files: [FileRecord], by order: ReviewSort) -> [FileRecord] {
        files.sorted { a, b in
            switch order {
            case .largest, .smallest:
                if a.allocatedBytes != b.allocatedBytes {
                    return order == .largest ? a.allocatedBytes > b.allocatedBytes : a.allocatedBytes < b.allocatedBytes
                }
            case .oldest, .newest:
                if a.identity.modifiedSeconds != b.identity.modifiedSeconds {
                    return order == .oldest ? a.identity.modifiedSeconds < b.identity.modifiedSeconds : a.identity.modifiedSeconds > b.identity.modifiedSeconds
                }
            case .name, .nameDescending:
                let comparison = a.name.localizedStandardCompare(b.name)
                if comparison != .orderedSame { return order == .name ? comparison == .orderedAscending : comparison == .orderedDescending }
            }
            return a.id < b.id
        }
    }
}
