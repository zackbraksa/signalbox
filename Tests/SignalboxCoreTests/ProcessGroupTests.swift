import Foundation
import Testing
@testable import SignalboxCore

private func process(_ pid: Int32, _ path: String, name: String? = nil, cpu: Double = 1, memory: UInt64 = 100) -> ProcessReading {
    ProcessReading(pid: pid, name: name ?? URL(fileURLWithPath: path).lastPathComponent,
                   cpuPercent: cpu, residentBytes: memory, executablePath: path)
}

@Test func appGroupsIncludeNestedHelpersBeforeRanking() {
    let rows = [
        process(1, "/Applications/Example.app/Contents/MacOS/Example", cpu: 30, memory: 100),
        process(2, "/Applications/Example.app/Contents/Frameworks/Helper.app/Contents/MacOS/Renderer", cpu: 30, memory: 100),
        process(3, "/Applications/Other.app/Contents/MacOS/Other", cpu: 50, memory: 150)
    ]
    let result = ProcessGrouper.topConsumers(in: rows, limit: 1)
    #expect(result.cpu.count == 1)
    #expect(result.cpu[0].name == "Example")
    #expect(result.cpu[0].cpuPercent == 60)
    #expect(result.memory[0].residentBytes == 200)
    #expect(result.cpu[0].members.map(\.pid) == [1, 2])
    #expect(result.cpu[0].members[1].executablePath == rows[1].executablePath)
    #expect(result.cpu[0].members[1].name == "Renderer")
    #expect(result.cpu[0].appPath == "/Applications/Example.app")
}

@Test func appIdentityUsesStandardizedOuterPath() {
    let rows = [
        process(1, "/Applications/Example.app/Contents/MacOS/Example"),
        process(2, "/Applications/./Example.app/Contents/MacOS/Helper"),
        process(3, "/Users/test/Applications/Example.app/Contents/MacOS/Example")
    ]
    let groups = ProcessGrouper.topConsumers(in: rows).cpu
    #expect(groups.count == 2)
    #expect(Set(groups.map(\.id)).count == 2)
    #expect(groups.allSatisfy { $0.name == "Example" })
    #expect(groups.first { $0.appPath == "/Applications/Example.app" }?.members.count == 2)
}

@Test func standaloneIdentityKeepsNamesPathsAndMissingPathPIDsSeparate() {
    let rows = [
        process(1, "/usr/bin/worker", name: "worker"),
        process(2, "/usr/bin/worker", name: "worker"),
        process(3, "/opt/bin/worker", name: "worker"),
        process(4, "/usr/bin/worker", name: "other"),
        process(5, "", name: "worker"),
        process(6, "", name: "worker")
    ]
    let groups = ProcessGrouper.topConsumers(in: rows, limit: 20).cpu
    #expect(groups.count == 5)
    #expect(groups.allSatisfy { $0.appPath == nil })
    #expect(groups.first { $0.members.count == 2 }?.representative.pid == 1)
}

@Test func groupingDeduplicatesPIDsAndSaturatesTotals() {
    let rows = [
        process(1, "/Applications/Example.app/Contents/MacOS/Example", cpu: .greatestFiniteMagnitude, memory: .max),
        process(2, "/Applications/Example.app/Contents/MacOS/Helper", cpu: .greatestFiniteMagnitude, memory: 1)
    ]
    let result = ProcessGrouper.topConsumers(in: rows + [rows[0]]).cpu[0]
    #expect(result.members.count == 2)
    #expect(result.residentBytes == UInt64.max)
    #expect(result.cpuPercent == Double.greatestFiniteMagnitude)
}

@Test func groupedResidentMemoryPreservesMultiGigabyteTotals() {
    let gib: UInt64 = 1_024 * 1_024 * 1_024
    let rows = [
        process(1, "/Applications/Example.app/Contents/MacOS/Example", memory: 9 * gib),
        process(2, "/Applications/Example.app/Contents/MacOS/Helper", memory: 7 * gib),
        process(3, "/Applications/Other.app/Contents/MacOS/Other", memory: 12 * gib)
    ]
    let result = ProcessGrouper.topConsumers(in: rows, limit: 1)
    #expect(result.memory[0].name == "Example")
    #expect(result.memory[0].residentBytes == 16 * gib)
}

@Test func groupingRanksMetricsIndependentlyWithStableTies() {
    let rows = [process(1, "/bin/a", cpu: 3, memory: 100), process(2, "/bin/b", cpu: 1, memory: 200), process(3, "/bin/c", cpu: 3, memory: 100)]
    let result = ProcessGrouper.topConsumers(in: rows, limit: 2)
    let reversed = ProcessGrouper.topConsumers(in: Array(rows.reversed()), limit: 2)
    #expect(result.cpu.map(\.id) == reversed.cpu.map(\.id))
    #expect(result.memory.map(\.id) == reversed.memory.map(\.id))
    #expect(result.cpu.first?.name == "a")
    #expect(result.memory.first?.name == "b")
    #expect(ProcessGrouper.topConsumers(in: rows, limit: -1).cpu.isEmpty)
}

@Test func groupNameUsesValidBundleMetadataThenFilename() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let app = root.appendingPathComponent("Filename.app")
    let contents = app.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let metadata: [String: Any] = ["CFBundleDisplayName": "Invalid\nName", "CFBundleName": "Valid Owner", "CFBundleIdentifier": "test.group.\(UUID().uuidString)"]
    let data = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    let result = ProcessGrouper.topConsumers(in: [process(1, contents.appendingPathComponent("MacOS/worker").path)])
    #expect(result.cpu[0].name == "Valid Owner")
}
