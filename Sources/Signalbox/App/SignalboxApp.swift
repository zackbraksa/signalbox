import AppKit
import SwiftUI
import SignalboxCore

@main
struct SignalboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private let store = MonitorStore()
    private let updater = AppUpdater()
    private var detailsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: 0)
        item.isVisible = false
        item.button?.target = self
        item.button?.action = #selector(toggle)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MonitorView(store: store, updater: updater))
        store.didUpdate = { [weak self] in self?.updateIndicator() }
        updateIndicator()
        store.start()
    }
    @objc private func toggle() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            NSApp.activate(ignoringOtherApps: true)
            store.opened()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    func popoverDidClose(_ notification: Notification) {
        if detailsWindow?.isVisible != true { store.closed() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if detailsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: MonitorView(store: store, updater: updater)))
            window.title = "Signalbox"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            detailsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        store.opened()
        detailsWindow?.makeKeyAndOrderFront(nil)
        return false
    }
    func windowWillClose(_ notification: Notification) {
        if !popover.isShown { store.closed() }
    }
    private func updateIndicator() {
        let s = store.snapshot
        let levels: [ResourceLevel] = [s?.cpu.level ?? .unknown, s?.memory.pressure ?? .unknown, s?.disk.level ?? .unknown, s?.thermal.level ?? .unknown]
        let symbols = ["cpu", "memorychip", "internaldrive", "thermometer.medium"]
        let names = zip(["CPU", "Memory pressure", "Disk space", "Thermal state"], levels).enumerated().map { index, entry in
            "\(entry.0): \(index == 1 ? entry.1.memoryTitle : entry.1.label)"
        }.joined(separator: ", ")
        item.button?.setAccessibilityLabel("Signalbox. \(names). Open system monitor")
        item.button?.toolTip = names
        let visible = levels.enumerated().filter { $0.element == .amber || $0.element == .red }
        item.isVisible = !visible.isEmpty
        guard !visible.isEmpty else {
            item.length = 0
            item.button?.image = nil
            if popover.isShown { popover.performClose(nil) }
            return
        }
        let width = CGFloat(visible.count * 17 - 4)
        item.length = width + 6
        let image = NSImage(size: NSSize(width: width, height: 18), flipped: false) { rect in
            for (position, entry) in visible.enumerated() {
                guard let symbol = NSImage(systemSymbolName: symbols[entry.offset], accessibilityDescription: nil) else { continue }
                let tinted = NSImage(size: NSSize(width: 13, height: 14))
                tinted.lockFocus()
                symbol.draw(in: NSRect(x: 0, y: 0, width: 13, height: 14))
                entry.element.nsColor.setFill()
                NSRect(x: 0, y: 0, width: 13, height: 14).fill(using: .sourceIn)
                tinted.unlockFocus()
                tinted.draw(in: NSRect(x: position * 17, y: 2, width: 13, height: 14))
            }
            return true
        }
        image.isTemplate = false
        item.button?.image = image

    }
}

extension ResourceLevel {
    var nsColor: NSColor {
        switch self { case .green: .systemGreen; case .amber: .systemOrange; case .red: .systemRed; case .unknown: .secondaryLabelColor }
    }
    var color: Color { Color(nsColor: nsColor) }
    var label: String {
        switch self { case .green: "Normal"; case .amber: "Elevated"; case .red: "Critical"; case .unknown: "Unavailable" }
    }
}
