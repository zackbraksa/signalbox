import Foundation

public struct ProcessIdentity: Hashable, Sendable {
    public let name: String
    public let executablePath: String

    public init(name: String, executablePath: String) {
        self.name = name
        self.executablePath = executablePath
    }

    public init(_ reading: ProcessReading) {
        self.init(name: reading.name, executablePath: reading.executablePath)
    }

    public var cacheKey: String {
        // Include the name so an absent path never aliases unrelated commands.
        "v1:\(executablePath.utf8.count):\(executablePath):\(name)"
    }
}

public struct ProcessLabel: Codable, Sendable, Equatable {
    public let text: String
    public let isInferred: Bool

    public init(text: String, isInferred: Bool) {
        self.text = text
        self.isInferred = isInferred
    }

    public static func validatedInference(_ text: String) -> ProcessLabel? {
        guard isValidText(text), !["unknown", "null", "nil", "n/a"].contains(text.lowercased()) else { return nil }
        return ProcessLabel(text: text, isInferred: true)
    }

    static func isValidText(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 60 && text == text.trimmingCharacters(in: .whitespacesAndNewlines)
            && !text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) }
    }

    var isValid: Bool {
        isInferred ? Self.validatedInference(text) != nil : Self.isValidText(text)
    }
}
