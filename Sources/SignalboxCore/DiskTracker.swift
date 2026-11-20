import Foundation

struct DiskTracker {
    private var level: ResourceLevel = .green

    mutating func sample(available: UInt64?, total: UInt64?) -> ResourceLevel {
        guard let available, let total, total > 0 else { return .unknown }
        let fraction = Double(available) / Double(total)
        if fraction < 0.05 || available < 5_000_000_000 {
            level = .red
        } else if level == .red && (fraction <= 0.07 || available <= 7_000_000_000) {
            level = .red
        } else if fraction < 0.10 || available < 20_000_000_000 {
            level = .amber
        } else if level != .green && (fraction <= 0.12 || available <= 22_000_000_000) {
            level = .amber
        } else {
            level = .green
        }
        return level
    }
}
