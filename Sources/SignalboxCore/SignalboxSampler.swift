import Darwin
import Foundation

/// Call sample and reset from one serial worker.
public final class SignalboxSampler: @unchecked Sendable {
    private var cpu = CPUTracker()
    private var disk = DiskTracker()
    private let diskURL: URL
    private let host = mach_host_self()

    public init() {
        let data = URL(fileURLWithPath: "/System/Volumes/Data", isDirectory: true)
        diskURL = FileManager.default.fileExists(atPath: data.path) ? data : URL(fileURLWithPath: "/", isDirectory: true)
    }

    public func reset() { cpu.reset() }

    deinit { mach_port_deallocate(mach_task_self_, host) }

    public func sample() -> SystemSnapshot {
        let memory = memoryUsage()
        let freshDiskURL = URL(fileURLWithPath: diskURL.path, isDirectory: true)
        let values = try? freshDiskURL.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
        let available = values?.volumeAvailableCapacity.flatMap { $0 >= 0 ? UInt64($0) : nil }
        let total = values?.volumeTotalCapacity.flatMap { $0 > 0 ? UInt64($0) : nil }
        let diskLevel = disk.sample(available: available, total: total)
        let thermal: ThermalReading
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = ThermalReading(state: .nominal, level: .green)
        case .fair: thermal = ThermalReading(state: .fair, level: .green)
        case .serious: thermal = ThermalReading(state: .serious, level: .amber)
        case .critical: thermal = ThermalReading(state: .critical, level: .red)
        @unknown default: thermal = ThermalReading(state: .unknown, level: .unknown)
        }
        return SystemSnapshot(timestamp: Date(), cpu: cpu.sample(cpuTicks(), time: ProcessInfo.processInfo.systemUptime), memory: MemoryReading(usedBytes: memory?.used, totalBytes: ProcessInfo.processInfo.physicalMemory, pressure: MemoryPressureReader.current(), compressedBytes: memory?.compressed, swapUsedBytes: swapUsage()), disk: DiskReading(availableBytes: available, totalBytes: total, level: diskLevel), thermal: thermal)
    }

    private func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard status == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        return CPUTicks(busy: UInt64(ticks.0) + UInt64(ticks.1) + UInt64(ticks.3), idle: UInt64(ticks.2))
    }

    private func memoryUsage() -> (used: UInt64, compressed: UInt64)? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        guard status == KERN_SUCCESS else { return nil }
        let pages = UInt64(info.active_count) + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        return (min(ProcessInfo.processInfo.physicalMemory, pages * UInt64(pageSize)), UInt64(info.compressor_page_count) * UInt64(pageSize))
    }

    private func swapUsage() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let status = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard status == 0, size == MemoryLayout<xsw_usage>.size else { return nil }
        return usage.xsu_used
    }
}
