import Foundation
import Testing
@testable import SignalboxCore

private func temporaryLabelDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func processParserRetainsExecutablePathWithSpaces() {
    let path = "/Applications/My App.app/Contents/MacOS/My App"
    let rows = ProcessInspector.parse("42 12.5 512 \(path)\n")
    #expect(rows.first?.executablePath == path)
    #expect(rows.first?.name == "My App")
}

@Test func metadataUsesOutermostAppAndHelperRole() throws {
    let directory = try temporaryLabelDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let app = directory.appendingPathComponent("Example.app")
    let contents = app.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist: [String: Any] = ["CFBundleName": "Internal", "CFBundleDisplayName": "Example", "CFBundleIdentifier": "test.example"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
    let path = app.appendingPathComponent("Contents/Frameworks/Example Helper.app/Contents/MacOS/Example Helper (Renderer)").path
    let label = ProcessMetadataResolver.resolve(ProcessIdentity(name: "Example Helper (Renderer)", executablePath: path))
    #expect(label == ProcessLabel(text: "Example · Renderer", isInferred: false))
    let cli = ProcessMetadataResolver.resolve(ProcessIdentity(name: "code", executablePath: app.appendingPathComponent("Contents/Resources/app/bin/code").path))
    #expect(cli?.text == "Example")
}

@Test func ambiguousProcessNamesDoNotClaimSystemIdentity() {
    #expect(ProcessMetadataResolver.resolve(ProcessIdentity(name: "siriactionsd", executablePath: "/tmp/siriactionsd")) == nil)
    #expect(ProcessMetadataResolver.resolve(ProcessIdentity(name: "siriactionsd", executablePath: "")) == nil)
    #expect(ProcessMetadataResolver.resolve(ProcessIdentity(name: "siriactionsd", executablePath: "/System/Library/PrivateFrameworks/SiriActions.framework/siriactionsd"))?.text == "Siri background service")
    #expect(ProcessMetadataResolver.resolve(ProcessIdentity(name: "BackgroundShortcutRunner", executablePath: "/System/Library/CoreServices/BackgroundShortcutRunner"))?.text == "Shortcuts background runner")
    #expect(ProcessMetadataResolver.resolve(ProcessIdentity(name: "SpringBoard", executablePath: "/tmp/SpringBoard.app/SpringBoard")) == nil)
    #expect(ProcessMetadataResolver.resolve(ProcessIdentity(name: "SpringBoard", executablePath: "/Library/Developer/CoreSimulator/Volumes/iOS/Applications/SpringBoard.app/SpringBoard"))?.text == "iOS Simulator Home Screen")
}

@Test func inferredLabelsRequireShortSingleLineText() {
    #expect(ProcessLabel.validatedInference("Background image worker")?.isInferred == true)
    for invalid in ["", " unknown", "unknown", "null", "two\nlines", "two\u{2028}lines", "bad\u{0}text", String(repeating: "a", count: 61)] {
        #expect(ProcessLabel.validatedInference(invalid) == nil)
    }
}

@Test func labelCacheRoundTripsWithoutProcessMetricsAndSeparatesPaths() async throws {
    let directory = try temporaryLabelDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("cache.json")
    let identity = ProcessIdentity(name: "worker", executablePath: "/one/worker")
    let cache = ProcessLabelCache(fileURL: url)
    let label = ProcessLabel(text: "Example worker", isInferred: true)
    await cache.store(label, for: identity)
    let restored = ProcessLabelCache(fileURL: url)
    #expect(await restored.label(for: identity) == label)
    #expect(await restored.label(for: ProcessIdentity(name: "worker", executablePath: "/two/worker")) == nil)
    let json = try String(contentsOf: url, encoding: .utf8)
    #expect(!json.contains("cpuPercent"))
    #expect(!json.contains("residentBytes"))
}

@Test func labelCacheRejectsCorruptionAndUnknownVersions() async throws {
    let directory = try temporaryLabelDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("cache.json")
    let cache = ProcessLabelCache(fileURL: url)
    await cache.store(ProcessLabel(text: "Worker", isInferred: true), for: ProcessIdentity(name: "worker", executablePath: "/worker"))
    let saved = try String(contentsOf: url, encoding: .utf8)
    let wrongVersion = saved.replacingOccurrences(of: "\"version\":1", with: "\"version\":2")
    #expect(saved != wrongVersion)
    for content in ["broken", wrongVersion] {
        try Data(content.utf8).write(to: url)
        let cache = ProcessLabelCache(fileURL: url)
        #expect(await cache.count == 0)
    }
}

@Test func labelCacheBoundsEntriesAndRejectsInvalidLabels() async throws {
    let directory = try temporaryLabelDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("cache.json")
    let cache = ProcessLabelCache(fileURL: url)
    for index in 0...ProcessLabelCache.capacity {
        await cache.store(ProcessLabel(text: "Worker", isInferred: true), for: ProcessIdentity(name: "worker", executablePath: "/\(index)/worker"))
    }
    #expect(await cache.count == ProcessLabelCache.capacity)
    let invalid = ProcessIdentity(name: "bad", executablePath: "/bad")
    await cache.store(ProcessLabel(text: "two\nlines", isInferred: true), for: invalid)
    #expect(await cache.label(for: invalid) == nil)
    #expect(await ProcessLabelCache(fileURL: url).count == ProcessLabelCache.capacity)
}
