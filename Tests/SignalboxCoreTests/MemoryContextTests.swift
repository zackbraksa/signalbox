import Foundation
import Testing
@testable import SignalboxCore

@Test func memoryContextPreservesUnavailableAndZeroReadings() {
    let unavailable = MemoryReading(usedBytes: nil, totalBytes: nil, pressure: .unknown)
    #expect(unavailable.compressedBytes == nil)
    #expect(unavailable.swapUsedBytes == nil)

    let zero = MemoryReading(usedBytes: 0, totalBytes: 1_024, pressure: .amber, compressedBytes: 0, swapUsedBytes: 0)
    #expect(zero.compressedBytes == 0)
    #expect(zero.swapUsedBytes == 0)
    #expect(zero.pressure == .amber)
}

@Test func liveMemoryContextIncludesBoundedCompressedMemoryAndSwap() throws {
    let memory = SignalboxSampler().sample().memory
    let compressed = try #require(memory.compressedBytes)
    let used = try #require(memory.usedBytes)
    #expect(compressed <= used)
    #expect(compressed <= ProcessInfo.processInfo.physicalMemory)
    #expect(memory.swapUsedBytes != nil)
}
