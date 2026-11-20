import Foundation
import SignalboxCore

protocol ProcessNamer: Sendable {
    func availability() async -> String?
    func label(for identity: ProcessIdentity) async throws -> ProcessLabel?
}

actor ProcessLabelService {
    private let cache: ProcessLabelCache
    private let namer: any ProcessNamer
    private var retryAfter: [String: Date] = [:]
    private var inferenceBusy = false

    init(cache: ProcessLabelCache = ProcessLabelCache(), namer: any ProcessNamer = OnDeviceProcessNamer()) {
        self.cache = cache
        self.namer = namer
    }

    func localLabels(for identities: [ProcessIdentity]) async -> [String: ProcessLabel] {
        var result: [String: ProcessLabel] = [:]
        for identity in identities {
            guard !Task.isCancelled else { break }
            if let label = ProcessMetadataResolver.resolve(identity) {
                result[identity.cacheKey] = label
            } else if let label = await cache.label(for: identity) {
                result[identity.cacheKey] = label
            }
        }
        return result
    }

    func availability() async -> String? { await namer.availability() }

    func infer(for identity: ProcessIdentity) async -> ProcessLabel? {
        if let label = await cache.label(for: identity) { return label }
        guard !Task.isCancelled, !inferenceBusy,
              retryAfter[identity.cacheKey, default: .distantPast] <= Date() else { return nil }
        inferenceBusy = true
        defer { inferenceBusy = false }
        guard await namer.availability() == nil, !Task.isCancelled else { return nil }
        do {
            let label = try await namer.label(for: identity)
            try Task.checkCancellation()
            if let label {
                await cache.store(label, for: identity)
                retryAfter.removeValue(forKey: identity.cacheKey)
                return label
            }
        } catch is CancellationError {
            return nil
        } catch {
            if Task.isCancelled { return nil }
        }
        // Uncertainty and transient failures are retried later, never persisted.
        retryAfter = retryAfter.filter { $0.value > Date() }
        if retryAfter.count >= 512 { retryAfter.removeAll(keepingCapacity: true) }
        retryAfter[identity.cacheKey] = Date().addingTimeInterval(300)
        return nil
    }
}
