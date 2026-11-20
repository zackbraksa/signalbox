import Foundation
import Testing
import SignalboxCore
@testable import Signalbox

private actor FakeNamer: ProcessNamer {
    var calls = 0
    let result: ProcessLabel?
    init(result: ProcessLabel? = ProcessLabel(text: "Example helper", isInferred: true)) { self.result = result }
    func availability() -> String? { nil }
    func label(for identity: ProcessIdentity) -> ProcessLabel? { calls += 1; return result }
}

private func temporaryCache() -> ProcessLabelCache {
    ProcessLabelCache(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("labels.json"))
}

@Test func repeatedProcessIdentityUsesCachedInference() async {
    let namer = FakeNamer()
    let service = ProcessLabelService(cache: temporaryCache(), namer: namer)
    let identity = ProcessIdentity(name: "exampled", executablePath: "/usr/local/bin/exampled")
    let first = await service.infer(for: identity)
    let second = await service.infer(for: identity)
    #expect(first?.text == "Example helper")
    #expect(first == second)
    #expect(await namer.calls == 1)
}

@Test func uncertainModelDoesNotRunEveryRefresh() async {
    let namer = FakeNamer(result: nil)
    let service = ProcessLabelService(cache: temporaryCache(), namer: namer)
    let identity = ProcessIdentity(name: "unfamiliar", executablePath: "/tmp/unfamiliar")
    #expect(await service.infer(for: identity) == nil)
    #expect(await service.infer(for: identity) == nil)
    #expect(await namer.calls == 1)
}

@Test func metadataLabelsBypassTheModel() async {
    let namer = FakeNamer()
    let service = ProcessLabelService(cache: temporaryCache(), namer: namer)
    let identity = ProcessIdentity(name: "siriactionsd", executablePath: "/System/Library/PrivateFrameworks/AssistantServices.framework/Support/siriactionsd")
    let labels = await service.localLabels(for: [identity])
    #expect(labels[identity.cacheKey]?.isInferred == false)
    #expect(await namer.calls == 0)
}

@Test func cancelledInferenceDoesNotCacheItsResponse() async {
    let namer = FakeNamer()
    let cache = temporaryCache()
    let service = ProcessLabelService(cache: cache, namer: namer)
    let identity = ProcessIdentity(name: "cancelled", executablePath: "/tmp/cancelled")
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return await service.infer(for: identity)
    }
    #expect(await task.value == nil)
    #expect(await cache.label(for: identity) == nil)
    #expect(await namer.calls == 0)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SIGNALBOX_TEST_LOCAL_MODEL"] == "1"))
func onDeviceModelGeneratesAProcessLabel() async throws {
    let namer = OnDeviceProcessNamer()
    #expect(await namer.availability() == nil)
    let label = try await namer.label(for: ProcessIdentity(name: "launchd", executablePath: "/sbin/launchd"))
    #expect(label?.isInferred == true)
    print("On-device label for launchd: \(label?.text ?? "unrecognized")")
}

private actor SuspendedNamer: ProcessNamer {
    var started = false
    var calls = 0
    private var continuation: CheckedContinuation<ProcessLabel?, Never>?
    func availability() -> String? { nil }
    func label(for identity: ProcessIdentity) async -> ProcessLabel? {
        calls += 1
        return await withCheckedContinuation {
            continuation = $0
            started = true
        }
    }
    func finish() {
        continuation?.resume(returning: ProcessLabel(text: "Delayed worker", isInferred: true))
        continuation = nil
    }
}

@Test func cancelledInFlightInferenceIsDiscardedAndDoesNotOverlap() async throws {
    let namer = SuspendedNamer()
    let cache = temporaryCache()
    let service = ProcessLabelService(cache: cache, namer: namer)
    let identity = ProcessIdentity(name: "delayed", executablePath: "/tmp/delayed")
    let task = Task { await service.infer(for: identity) }
    for _ in 0..<200 where !(await namer.started) { try await Task.sleep(for: .milliseconds(1)) }
    #expect(await namer.started)
    #expect(await service.infer(for: identity) == nil)
    #expect(await namer.calls == 1)
    task.cancel()
    await namer.finish()
    #expect(await task.value == nil)
    #expect(await cache.label(for: identity) == nil)
}

private actor UnavailableNamer: ProcessNamer {
    var calls = 0
    func availability() -> String? { "Apple Intelligence disabled" }
    func label(for identity: ProcessIdentity) -> ProcessLabel? { calls += 1; return nil }
}

@Test func unavailableModelLeavesCachedAndMetadataLabelsUsable() async {
    let namer = UnavailableNamer()
    let cache = temporaryCache()
    let identity = ProcessIdentity(name: "cached", executablePath: "/tmp/cached")
    let saved = ProcessLabel(text: "Cached worker", isInferred: true)
    await cache.store(saved, for: identity)
    let service = ProcessLabelService(cache: cache, namer: namer)
    #expect(await service.localLabels(for: [identity])[identity.cacheKey] == saved)
    #expect(await service.availability() == "Apple Intelligence disabled")
    #expect(await service.infer(for: ProcessIdentity(name: "new", executablePath: "/tmp/new")) == nil)
    #expect(await namer.calls == 0)
}
