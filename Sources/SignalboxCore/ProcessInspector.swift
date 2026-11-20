import Darwin
import Foundation

public enum ProcessInspector {
    /// Run only while the dropdown is open. ps uses its lifetime-average CPU percentage.
    public static func topConsumers(limit: Int = 5) -> ProcessConsumers {
        guard let entries = readRows() else { return ProcessConsumers(cpu: [], memory: [], unavailable: true) }
        let count = max(0, min(limit, 20))
        return ProcessConsumers(cpu: Array(entries.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(count)), memory: Array(entries.sorted { $0.residentBytes > $1.residentBytes }.prefix(count)), unavailable: false)
    }

    public static func topAppConsumers(limit: Int = 5) -> AppConsumers {
        guard let entries = readRows() else { return AppConsumers(cpu: [], memory: [], unavailable: true) }
        return ProcessGrouper.topConsumers(in: entries, limit: limit)
    }

    private static func readRows() -> [ProcessReading]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,pcpu=,rss=,comm="]
        process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        let hardDeadline = DispatchWorkItem {
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: deadline)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.25, execute: hardDeadline)
        var data = Data()
        var truncated = false
        while true {
            let part = output.fileHandleForReading.availableData
            if part.isEmpty { break }
            if !truncated, data.count + part.count <= 2_000_000 { data.append(part) }
            else { truncated = true }
        }
        process.waitUntilExit()
        deadline.cancel()
        hardDeadline.cancel()
        guard !truncated, process.terminationStatus == 0, let string = String(data: data, encoding: .utf8) else { return nil }
        return parse(string)
    }

    static func parse(_ output: String) -> [ProcessReading] {
        output.split(separator: "\n").compactMap { line in
            let columns = line.split(maxSplits: 3, whereSeparator: { $0.isWhitespace })
            guard columns.count == 4, let pid = Int32(columns[0]), let cpu = Double(columns[1]), cpu.isFinite, cpu >= 0, let rss = UInt64(columns[2]), rss <= UInt64.max / 1024 else { return nil }
            let path = String(columns[3])
            let name = URL(fileURLWithPath: path).lastPathComponent
            return ProcessReading(pid: pid, name: name, cpuPercent: cpu, residentBytes: rss * 1024, executablePath: path)
        }
    }
}
