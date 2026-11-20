import AppKit
import SwiftUI
import Charts
import SignalboxCore

struct MonitorView: View {
    let store: MonitorStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Signalbox").font(.headline)
                Spacer()
                Text("Live · 2 sec").font(.caption).foregroundStyle(.secondary)
            }
            if let s = store.snapshot {
                ResourceRow(symbol: "cpu", title: "CPU", value: s.cpu.usage.map { String(format: "%.0f%%", $0 * 100) } ?? "Collecting baseline…", level: s.cpu.level)
                MemoryStatusView(memory: s.memory)
                ResourceRow(symbol: "internaldrive", title: "Startup disk", value: "\(bytes(s.disk.availableBytes)) available", level: s.disk.level)
                Text("Startup Data volume · available space, not disk activity").font(.caption2).foregroundStyle(.secondary)
                ResourceRow(symbol: "thermometer.medium", title: "Thermal state", value: s.thermal.state.rawValue.capitalized, level: s.thermal.level)
            } else { ProgressView("Reading system…") }
            Divider()
            HistoryView(history: store.history)
            Divider()
            ConsumersView(consumers: store.consumers, labels: store.processLabels, labelStatus: store.labelStatus)
            Divider()
            HStack {
                Text("Green normal · Amber warning · Red critical\nGray means unavailable. Labels cached locally.")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
        }
        .padding(18)
        .frame(width: 370)
    }
}

func bytes<T: BinaryInteger>(_ value: T?) -> String {
    guard let value else { return "Unavailable" }
    return ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
}
func bytes<T: BinaryInteger>(_ value: T) -> String { bytes(Optional(value)) }

struct ResourceRow: View {
    let symbol: String
    let title: String
    let value: String
    let level: ResourceLevel
    var statusDescription: String? = nil
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).foregroundStyle(level.color).frame(width: 18)
            Text(title)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value), \(statusDescription ?? level.label)")
    }
}

struct HistoryView: View {
    let history: [SystemSnapshot]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text("CPU history").font(.subheadline.weight(.medium)); Spacer(); Text("Last 2 minutes").font(.caption).foregroundStyle(.secondary) }
            Chart(history, id: \.timestamp) { s in
                if let usage = s.cpu.usage {
                    LineMark(x: .value("Time", s.timestamp), y: .value("CPU", usage * 100))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(values: [0, 50, 100]) }
            .frame(height: 65)
            .accessibilityLabel("CPU utilization history, zero to one hundred percent")
            Text("CPU color follows sustained load.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct ConsumersView: View {
    let consumers: AppConsumers?
    let labels: [String: ProcessLabel]
    let labelStatus: String
    @State private var rankByMemory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apps & services").font(.subheadline.weight(.medium))
            Picker("Rank apps by resource", selection: $rankByMemory) {
                Text("Most CPU").tag(false)
                Text("Most memory").tag(true)
            }.pickerStyle(.segmented).labelsHidden()
            HStack {
                Text("App / service").frame(maxWidth: .infinity, alignment: .leading)
                Text("CPU").frame(width: 52, alignment: .trailing)
                Text("Memory").frame(width: 74, alignment: .trailing)
            }.font(.caption).foregroundStyle(.secondary)
            if let consumers {
                if consumers.unavailable {
                    Text("Process readings unavailable").font(.caption).foregroundStyle(.secondary)
                } else {
                    let groups = rankByMemory ? consumers.memory : consumers.cpu
                    if groups.isEmpty { Text("No process readings").font(.caption) }
                    ForEach(groups) { group in
                        AppConsumerRow(group: group, inferredLabel: group.appPath == nil ? labels[ProcessIdentity(group.representative).cacheKey] : nil)
                    }
                }
            } else {
                Text("Reading processes…").font(.caption).foregroundStyle(.secondary)
            }
            Text(labelStatus).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Combined CPU is a process lifetime average and can exceed 100%. Memory sums resident sizes; shared pages may count more than once. Updates every 10 sec while open.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AppConsumerRow: View {
    let group: ProcessGroup
    let inferredLabel: ProcessLabel?
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Text(inferredLabel?.text ?? group.name).lineLimit(1).truncationMode(.middle)
                    if inferredLabel?.isInferred == true {
                        Image(systemName: "sparkles").font(.caption2).foregroundStyle(.secondary)
                            .accessibilityLabel("AI-inferred label")
                    }
                }
                Text(group.members.count == 1 ? "1 process" : "\(group.members.count) processes")
                    .font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "%.1f%%", group.cpuPercent)).monospacedDigit().frame(width: 52, alignment: .trailing)
            Text(bytes(group.residentBytes)).monospacedDigit().frame(width: 74, alignment: .trailing)
        }
        .font(.caption)
        .help(memberHelp)
        .accessibilityElement(children: .combine)
    }

    private var memberHelp: String {
        let members = group.members.prefix(20).map { "\($0.name) (PID \($0.pid))\n\($0.executablePath)" }.joined(separator: "\n\n")
        let remainder = group.members.count > 20 ? "\n\nAnd \(group.members.count - 20) more processes included in totals." : ""
        let inference = inferredLabel?.isInferred == true ? "\n\nAI-inferred description; may be inaccurate." : ""
        return "\(inferredLabel?.text ?? group.name)\n\n\(members)\(remainder)\(inference)"
    }
}

struct MemoryStatusView: View {
    let memory: MemoryReading
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ResourceRow(symbol: "memorychip", title: "Memory pressure", value: memory.pressure.memoryTitle, level: memory.pressure, statusDescription: memory.pressure.memoryExplanation)
            Text(memory.pressure.memoryExplanation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Memory estimate: \(bytes(memory.usedBytes)) of \(bytes(memory.totalBytes))").font(.caption).foregroundStyle(.secondary)
            Text("Compressed: \(bytes(memory.compressedBytes)) · Swap used: \(bytes(memory.swapUsedBytes))")
                .font(.caption).foregroundStyle(.secondary)
                .help("Compression and swap are measured usage, not a pressure percentage. Swap can remain in use after pressure drops.")
        }
    }
}

extension ResourceLevel {
    var memoryTitle: String {
        switch self {
        case .green: "Healthy"
        case .amber: "Under pressure"
        case .red: "Heavy pressure"
        case .unknown: "Unavailable"
        }
    }
    var memoryExplanation: String {
        switch self {
        case .green: "macOS reports normal memory pressure."
        case .amber: "macOS reports a memory warning. Closing unused apps can reduce demand."
        case .red: "macOS reports critical memory pressure. Close unused apps to reduce demand."
        case .unknown: "macOS memory pressure could not be read."
        }
    }
}
