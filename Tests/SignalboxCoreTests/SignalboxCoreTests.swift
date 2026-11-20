import Foundation
import Testing
@testable import SignalboxCore

@Test func cpuNeedsBaselineAndResetDiscardsIt() {
    var tracker = CPUTracker()
    #expect(tracker.sample(CPUTicks(busy: 100, idle: 100), time: 0).usage == nil)
    let reading = tracker.sample(CPUTicks(busy: 125, idle: 175), time: 2)
    #expect(reading.usage == 0.25)
    #expect(reading.level == .green)
    tracker.reset()
    #expect(tracker.sample(CPUTicks(busy: 130, idle: 180), time: 4).usage == nil)
}

@Test func briefCPUActivityDoesNotRaiseAlertAndSustainedActivityDoes() {
    var tracker = CPUTracker()
    _ = tracker.sample(CPUTicks(busy: 0, idle: 0), time: 0)
    for step in 1...4 {
        let reading = tracker.sample(CPUTicks(busy: UInt64(step * 100), idle: 0), time: Double(step * 2))
        #expect(reading.level == .green)
    }
    #expect(tracker.sample(CPUTicks(busy: 500, idle: 0), time: 10).level == .red)
    let recovery = tracker.sample(CPUTicks(busy: 500, idle: 100), time: 12)
    #expect(recovery.usage! > 0.6)
    #expect(recovery.level == .red)
    var final = recovery
    for step in 7...20 { final = tracker.sample(CPUTicks(busy: 500, idle: UInt64((step - 5) * 100)), time: Double(step * 2)) }
    #expect(final.level == .green)
}

@Test func sustainedAmberAndHysteresis() {
    var tracker = CPUTracker()
    _ = tracker.sample(CPUTicks(busy: 0, idle: 0), time: 0)
    for step in 1...5 { _ = tracker.sample(CPUTicks(busy: UInt64(step * 70), idle: UInt64(step * 30)), time: Double(step * 2)) }
    #expect(tracker.sample(CPUTicks(busy: 420, idle: 180), time: 12).level == .amber)
    for step in 1...20 {
        let result = tracker.sample(CPUTicks(busy: UInt64(420 + step * 60), idle: UInt64(180 + step * 40)), time: Double(12 + step * 2))
        #expect(result.level == .amber)
    }
}

@Test func missingCountersAreUnavailable() {
    var tracker = CPUTracker()
    #expect(tracker.sample(nil, time: 0).level == .unknown)
    #expect(tracker.sample(CPUTicks(busy: 1, idle: 1), time: 2).usage == nil)
}

@Test func longSamplingGapStartsFreshBaseline() {
    var tracker = CPUTracker()
    _ = tracker.sample(CPUTicks(busy: 0, idle: 0), time: 0)
    _ = tracker.sample(CPUTicks(busy: 100, idle: 0), time: 2)
    #expect(tracker.sample(CPUTicks(busy: 100, idle: 1000), time: 20).usage == nil)
    #expect(tracker.sample(CPUTicks(busy: 125, idle: 1075), time: 22).usage == 0.25)
}

@Test func diskHysteresisAvoidsThresholdFlicker() {
    var tracker = DiskTracker()
    let total: UInt64 = 1_000_000_000_000
    #expect(tracker.sample(available: 49_000_000_000, total: total) == .red)
    #expect(tracker.sample(available: 60_000_000_000, total: total) == .red)
    #expect(tracker.sample(available: 80_000_000_000, total: total) == .amber)
    #expect(tracker.sample(available: 110_000_000_000, total: total) == .amber)
    #expect(tracker.sample(available: 130_000_000_000, total: total) == .green)
    #expect(tracker.sample(available: nil, total: total) == .unknown)
}

@Test func processParsingPreservesNamesAndConvertsRSS() {
    let rows = ProcessInspector.parse(" 42 125.5 2048 /Applications/My App.app/Contents/MacOS/My App\n 51 0.2 100 /usr/bin/test\ninvalid\n 7 nan 12 /bad\n")
    #expect(rows.count == 2)
    #expect(rows[0].pid == 42)
    #expect(rows[0].cpuPercent == 125.5)
    #expect(rows[0].residentBytes == 2_097_152)
    #expect(rows[0].name == "My App")
}

@Test func realSamplerProvidesBoundedReadings() {
    let sampler = SignalboxSampler()
    let snapshot = sampler.sample()
    #expect(snapshot.cpu.usage == nil)
    #expect(snapshot.memory.totalBytes == ProcessInfo.processInfo.physicalMemory)
    if let used = snapshot.memory.usedBytes, let total = snapshot.memory.totalBytes { #expect(used <= total) }
    if let available = snapshot.disk.availableBytes, let total = snapshot.disk.totalBytes { #expect(available <= total) }
    #expect(snapshot.thermal.state != .unknown)
}

@Test func firstSampleIncludesCurrentMemoryPressureWithoutNotification() {
    #expect(SignalboxSampler().sample().memory.pressure != .unknown)
}

@Test func memoryPressureMapsKernelValuesAndRejectsUnknownValues() {
    #expect(MemoryPressureReader.level(for: 1) == .green)
    #expect(MemoryPressureReader.level(for: 2) == .amber)
    #expect(MemoryPressureReader.level(for: 4) == .red)
    for value: Int32 in [0, 3, 5, -1, 8] {
        #expect(MemoryPressureReader.level(for: value) == .unknown)
    }
}
