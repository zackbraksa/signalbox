import Foundation

public struct ProcessGroup: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let appPath: String?
    public let members: [ProcessReading]
    public let cpuPercent: Double
    public let residentBytes: UInt64

    public var representative: ProcessReading { members[0] }
}

public struct AppConsumers: Sendable {
    public let cpu: [ProcessGroup]
    public let memory: [ProcessGroup]
    public let unavailable: Bool

    public init(cpu: [ProcessGroup], memory: [ProcessGroup], unavailable: Bool) {
        self.cpu = cpu
        self.memory = memory
        self.unavailable = unavailable
    }
}

public enum ProcessGrouper {
    public static func topConsumers(in readings: [ProcessReading], limit: Int = 5) -> AppConsumers {
        var members: [String: [ProcessReading]] = [:]
        var appPaths: [String: String] = [:]
        var seen = Set<Int32>()
        // ps emits each PID once; sorting also makes duplicate input deterministic.
        for reading in readings.sorted(by: precedes) where seen.insert(reading.pid).inserted {
            let appPath = owningAppPath(reading.executablePath)
            let identity = ProcessIdentity(reading)
            let id = appPath.map { "app:\($0)" }
                ?? (reading.executablePath.isEmpty ? "pid:\(reading.pid)" : "process:\(identity.cacheKey)")
            members[id, default: []].append(reading)
            if let appPath { appPaths[id] = appPath }
        }
        let groups = members.map { id, rows in
            let appPath = appPaths[id]
            let name = appPath.map(appName) ?? rows[0].name
            let cpu = rows.reduce(0.0) { total, row in
                let sum = total + row.cpuPercent
                return sum.isFinite ? sum : Double.greatestFiniteMagnitude
            }
            let memory = rows.reduce(UInt64(0)) { total, row in
                let sum = total.addingReportingOverflow(row.residentBytes)
                return sum.overflow ? UInt64.max : sum.partialValue
            }
            return ProcessGroup(id: id, name: name, appPath: appPath, members: rows,
                                cpuPercent: cpu, residentBytes: memory)
        }
        let count = max(0, min(limit, 20))
        return AppConsumers(
            cpu: Array(groups.sorted { $0.cpuPercent == $1.cpuPercent ? $0.id < $1.id : $0.cpuPercent > $1.cpuPercent }.prefix(count)),
            memory: Array(groups.sorted { $0.residentBytes == $1.residentBytes ? $0.id < $1.id : $0.residentBytes > $1.residentBytes }.prefix(count)),
            unavailable: false
        )
    }

    private static func precedes(_ lhs: ProcessReading, _ rhs: ProcessReading) -> Bool {
        if lhs.pid != rhs.pid { return lhs.pid < rhs.pid }
        if lhs.executablePath != rhs.executablePath { return lhs.executablePath < rhs.executablePath }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        if lhs.cpuPercent != rhs.cpuPercent { return lhs.cpuPercent > rhs.cpuPercent }
        return lhs.residentBytes > rhs.residentBytes
    }

    private static func owningAppPath(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        guard let index = components.firstIndex(where: { $0.lowercased().hasSuffix(".app") }) else { return nil }
        return NSString.path(withComponents: Array(components.prefix(index + 1)))
    }

    private static func appName(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        if let bundle = Bundle(url: url) {
            for key in ["CFBundleDisplayName", "CFBundleName"] {
                if let name = bundle.object(forInfoDictionaryKey: key) as? String,
                   ProcessLabel.isValidText(name) { return name }
            }
        }
        return url.deletingPathExtension().lastPathComponent
    }
}
