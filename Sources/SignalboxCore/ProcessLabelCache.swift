import Foundation

public actor ProcessLabelCache {
    private struct Entry: Codable {
        let label: ProcessLabel
        let updatedAt: Date
    }
    private struct Contents: Codable {
        let version: Int
        let entries: [String: Entry]
    }

    public static let capacity = 512
    private let fileURL: URL
    private var entries: [String: Entry]

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Signalbox", isDirectory: true).appendingPathComponent("process-labels.json")
        if let data = try? Data(contentsOf: self.fileURL), data.count <= 2_000_000,
           let contents = try? JSONDecoder().decode(Contents.self, from: data), contents.version == 1 {
            let valid = contents.entries.filter { $0.value.label.isValid && $0.key.count <= 8_192 }
            self.entries = Dictionary(uniqueKeysWithValues: valid.sorted { $0.value.updatedAt > $1.value.updatedAt }.prefix(Self.capacity).map { ($0.key, $0.value) })
        } else {
            self.entries = [:]
        }
    }

    public var count: Int { entries.count }

    public func label(for identity: ProcessIdentity) -> ProcessLabel? {
        entries[identity.cacheKey]?.label
    }

    public func store(_ label: ProcessLabel, for identity: ProcessIdentity) {
        guard label.isValid, identity.cacheKey.count <= 8_192 else { return }
        entries[identity.cacheKey] = Entry(label: label, updatedAt: Date())
        if entries.count > Self.capacity, let oldest = entries.min(by: { $0.value.updatedAt < $1.value.updatedAt })?.key {
            entries.removeValue(forKey: oldest)
        }
        guard let data = try? JSONEncoder().encode(Contents(version: 1, entries: entries)) else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Labels remain useful for this run when persistence is unavailable.
        }
    }
}
