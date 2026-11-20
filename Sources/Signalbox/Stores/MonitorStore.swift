import AppKit
import Observation
import SignalboxCore

actor SamplingWorker {
    let sampler = SignalboxSampler()
    func sample(reset: Bool) -> SystemSnapshot {
        if reset { sampler.reset() }
        return sampler.sample()
    }
    func processes() -> AppConsumers { ProcessInspector.topAppConsumers() }
}

@MainActor @Observable
final class MonitorStore {
    var snapshot: SystemSnapshot?
    var history: [SystemSnapshot] = []
    var consumers: AppConsumers?
    var isOpen = false
    var processLabels: [String: ProcessLabel] = [:]
    var labelStatus = "App names and local labels"
    private let labelService = ProcessLabelService()
    private var labelTask: Task<Void, Never>?
    private var labelGeneration = 0
    private var labelIdentities: [ProcessIdentity] = []
    private let worker = SamplingWorker()
    private var loop: Task<Void, Never>?
    private var resetPending = true
    private var lastProcesses = Date.distantPast
    private var sleeping = false
    private var generation = 0
    var didUpdate: (() -> Void)?

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(sleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.sleeping { await self.refresh() }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    @objc private func sleep() { sleeping = true; resetPending = true; generation += 1; stopLabeling() }
    @objc private func wake() {
        sleeping = false
        resetPending = true
        history = []
        consumers = nil
        lastProcesses = .distantPast
    }
    func opened() { isOpen = true; lastProcesses = .distantPast }
    func closed() { isOpen = false; stopLabeling() }
    private func stopLabeling() {
        labelGeneration += 1
        labelTask?.cancel()
        labelTask = nil
    }

    private func beginLabeling(_ consumers: AppConsumers) {
        var seen = Set<String>()
        let identities = (consumers.cpu + consumers.memory).filter { $0.appPath == nil }.map { ProcessIdentity($0.representative) }.filter { seen.insert($0.cacheKey).inserted }
        if identities == labelIdentities, labelTask != nil { return }
        stopLabeling()
        labelIdentities = identities
        let token = labelGeneration
        labelTask = Task { [weak self, labelService] in
            let local = await labelService.localLabels(for: identities)
            guard let self, !Task.isCancelled, self.labelGeneration == token, self.isOpen else { return }
            self.processLabels = local
            let unavailable = await labelService.availability()
            guard !Task.isCancelled, self.labelGeneration == token, self.isOpen else { return }
            if let unavailable {
                self.labelStatus = unavailable
            } else {
                self.labelStatus = "AI suggestions are inferred · Hover for original names"
                for identity in identities where local[identity.cacheKey] == nil {
                    guard !Task.isCancelled else { break }
                    let label = await labelService.infer(for: identity)
                    guard !Task.isCancelled, self.labelGeneration == token, self.isOpen else { return }
                    if let label { self.processLabels[identity.cacheKey] = label }
                }
            }
            if self.labelGeneration == token { self.labelTask = nil }
        }
    }

    private func refresh() async {
        let currentGeneration = generation
        let reset = resetPending
        resetPending = false
        let value = await worker.sample(reset: reset)
        guard !sleeping, currentGeneration == generation else { return }
        snapshot = value
        history.append(value)
        if history.count > 60 { history.removeFirst(history.count - 60) }
        didUpdate?()
        if isOpen && Date().timeIntervalSince(lastProcesses) >= 10 {
            lastProcesses = Date()
            let value = await worker.processes()
            if isOpen, !sleeping, currentGeneration == generation {
                consumers = value
                beginLabeling(value)
            }
        }
    }
}
