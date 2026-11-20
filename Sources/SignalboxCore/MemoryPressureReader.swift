import Darwin
import Dispatch

struct MemoryPressureReader {
    static func current() -> ResourceLevel {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0)
        guard result == 0, size == MemoryLayout<Int32>.size else { return .unknown }
        return level(for: value)
    }

    // XNU exports Dispatch pressure values here, not its internal pressure enum.
    static func level(for value: Int32) -> ResourceLevel {
        switch value {
        case Int32(DispatchSource.MemoryPressureEvent.normal.rawValue): .green
        case Int32(DispatchSource.MemoryPressureEvent.warning.rawValue): .amber
        case Int32(DispatchSource.MemoryPressureEvent.critical.rawValue): .red
        default: .unknown
        }
    }
}
