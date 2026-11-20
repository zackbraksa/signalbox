import Foundation

public enum ProcessMetadataResolver {
    public static func resolve(_ identity: ProcessIdentity) -> ProcessLabel? {
        let path = identity.executablePath
        guard path.hasPrefix("/") else { return nil }
        let executable = URL(fileURLWithPath: path).standardizedFileURL
        let name = executable.lastPathComponent
        if name == "SpringBoard", path.contains("/CoreSimulator/"), path.contains("/SpringBoard.app/") {
            return ProcessLabel(text: "iOS Simulator Home Screen", isInferred: false)
        }
        let known: [String: String] = [
            "siriactionsd": "Siri background service",
            "BackgroundShortcutRunner": "Shortcuts background runner",
            "WindowServer": "Window display service",
            "kernel_task": "macOS kernel",
            "mds": "Spotlight indexing service",
            "mdworker_shared": "Spotlight indexing worker",
            "coreaudiod": "Audio service"
        ]
        if (path.hasPrefix("/System/") || path.hasPrefix("/usr/libexec/")), let label = known[name] {
            return ProcessLabel(text: label, isInferred: false)
        }
        let components = executable.pathComponents
        if let index = components.firstIndex(where: { $0.hasSuffix(".app") }) {
            let appURL = URL(fileURLWithPath: NSString.path(withComponents: Array(components.prefix(index + 1))))
            if let bundle = Bundle(url: appURL),
               let owner = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String),
               ProcessLabel.isValidText(owner) {
                let role = helperRole(identity.name)
                let label = role.map { "\(owner) · \($0)" } ?? owner
                if ProcessLabel.isValidText(label) { return ProcessLabel(text: label, isInferred: false) }
            }
        }
        return nil
    }

    private static func helperRole(_ name: String) -> String? {
        let roles = ["Renderer", "GPU", "Utility", "Plugin", "Network", "Crashpad"]
        if let role = roles.first(where: { name.hasSuffix("(\($0))") }) { return role }
        if name.hasSuffix(" Helper") { return "Helper" }
        return nil
    }
}
