import Foundation

struct CPUTicks {
    let busy: UInt64
    let idle: UInt64
}

struct CPUTracker {
    private var previous: CPUTicks?
    private var previousTime: TimeInterval?
    private var smoothed: Double?
    private var level: ResourceLevel = .green
    private var pendingLevel: ResourceLevel?
    private var pendingSince: TimeInterval?

    mutating func reset() { self = CPUTracker() }

    mutating func sample(_ ticks: CPUTicks?, time: TimeInterval) -> CPUReading {
        guard let ticks else {
            reset()
            return CPUReading(usage: nil, level: .unknown)
        }
        if let previousTime, time - previousTime > 5 { reset() }
        defer { previous = ticks; previousTime = time }
        guard let previous, let previousTime,
              ticks.busy >= previous.busy, ticks.idle >= previous.idle,
              time > previousTime else {
            return CPUReading(usage: nil, level: .unknown)
        }
        let busy = ticks.busy - previous.busy
        let idle = ticks.idle - previous.idle
        guard busy + idle > 0 else { return CPUReading(usage: smoothed, level: smoothed == nil ? .unknown : level) }
        let usage = Double(busy) / Double(busy + idle)
        let weight = 1 - exp(-(time - previousTime) / 5)
        let value = smoothed.map { $0 + weight * (usage - $0) } ?? usage
        smoothed = value
        let desired: ResourceLevel
        switch level {
        case .red: desired = value >= 0.80 ? .red : (value >= 0.55 ? .amber : .green)
        case .amber: desired = value >= 0.90 ? .red : (value >= 0.55 ? .amber : .green)
        case .green, .unknown: desired = value >= 0.90 ? .red : (value >= 0.65 ? .amber : .green)
        }
        if desired == level {
            pendingLevel = nil
            pendingSince = nil
        } else if pendingLevel != desired {
            pendingLevel = desired
            pendingSince = time
        } else if let pendingSince, time - pendingSince >= (desired == .green ? 5 : 8) {
            level = desired
            pendingLevel = nil
            self.pendingSince = nil
        }
        return CPUReading(usage: value, level: level)
    }
}
