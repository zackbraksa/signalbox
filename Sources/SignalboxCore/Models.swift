import Foundation

public enum ResourceLevel: String, Sendable, CaseIterable {
    case unknown, green, amber, red
}

public struct CPUReading: Sendable {
    public let usage: Double?
    public let level: ResourceLevel
}

public struct MemoryReading: Sendable {
    public let usedBytes: UInt64?
    public let totalBytes: UInt64?
    public let pressure: ResourceLevel
    public let compressedBytes: UInt64?
    public let swapUsedBytes: UInt64?

    public init(usedBytes: UInt64?, totalBytes: UInt64?, pressure: ResourceLevel, compressedBytes: UInt64? = nil, swapUsedBytes: UInt64? = nil) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.pressure = pressure
        self.compressedBytes = compressedBytes
        self.swapUsedBytes = swapUsedBytes
    }
}

public struct DiskReading: Sendable {
    public let availableBytes: UInt64?
    public let totalBytes: UInt64?
    public let level: ResourceLevel
}

public enum ThermalState: String, Sendable {
    case unknown, nominal, fair, serious, critical
}

public struct ThermalReading: Sendable {
    public let state: ThermalState
    public let level: ResourceLevel
}

public struct SystemSnapshot: Sendable {
    public let timestamp: Date
    public let cpu: CPUReading
    public let memory: MemoryReading
    public let disk: DiskReading
    public let thermal: ThermalReading
}

public struct ProcessReading: Sendable, Identifiable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    public let executablePath: String
    /// Percentage of one CPU core, as reported by ps; may exceed 100.
    public let cpuPercent: Double
    public let residentBytes: UInt64

    public init(pid: Int32, name: String, cpuPercent: Double, residentBytes: UInt64, executablePath: String = "") {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.residentBytes = residentBytes
        self.executablePath = executablePath
    }
}

public struct ProcessConsumers: Sendable {
    public let cpu: [ProcessReading]
    public let memory: [ProcessReading]
    public let unavailable: Bool
}
