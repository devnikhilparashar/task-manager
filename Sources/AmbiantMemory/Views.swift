import SwiftUI
import AppKit
import Combine

struct MenuContentView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.status, systemImage: statusIcon)
                .font(.headline)
            permissionSummary
            if let lastCaptureAt = model.lastCaptureAt {
                Text("Last captured \(lastCaptureAt, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Button(model.coordinator.isPaused ? "Start Recording" : "Pause Recording") { model.toggleCapture() }
            Button("Pause for 15 Minutes") { model.pause15Minutes() }
                .disabled(model.coordinator.isPaused)
            Button("Open Today") { openWindow(id: "timeline") }
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit AmbiantMemory") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 270)
        .onAppear { model.refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions()
        }
    }

    private var statusIcon: String {
        if model.coordinator.isPaused { return "pause.circle.fill" }
        if !model.permissions.accessibility && !model.permissions.screenRecording { return "exclamationmark.triangle.fill" }
        return "record.circle.fill"
    }

    private var permissionSummary: some View {
        Text(permissionText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var permissionText: String {
        switch (model.permissions.accessibility, model.permissions.screenRecording) {
        case (true, true): return "Accessibility with OCR fallback"
        case (true, false): return "Accessibility only — OCR unavailable"
        case (false, true): return "OCR and app titles only"
        case (false, false): return "App and window titles only"
        }
    }
}

struct TimelineView: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if filteredBlocks.isEmpty {
                    ContentUnavailableView("No activity yet", systemImage: "clock", description: Text("Activity captured on this day will appear here."))
                } else {
                    List(filteredBlocks) { block in
                        DisclosureGroup {
                            Text(block.text.isEmpty ? "No readable content was available." : block.text)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                                .padding(.vertical, 6)
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(block.workLabel).font(.headline)
                                    Text("\(block.appName) · \(duration(block))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(block.start, style: .time).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("AmbiantMemory")
            .searchable(text: $searchText, prompt: "Search app, title, or captured text")
            .toolbar {
                ToolbarItemGroup {
                    DatePicker("Day", selection: $model.selectedDay, displayedComponents: .date)
                        .labelsHidden()
                        .onChange(of: model.selectedDay) { _, _ in Task { await model.refresh() } }
                    Menu("Export") {
                        Button("JSON") { model.export(.json) }
                        Button("CSV") { model.export(.csv) }
                    }
                    Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 480)
    }

    private func duration(_ block: ActivityBlock) -> String {
        Duration.seconds(max(0, block.end.timeIntervalSince(block.start))).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
    }

    private var filteredBlocks: [ActivityBlock] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.blocks }
        return model.blocks.filter {
            [$0.appName, $0.representativeTitle, $0.workLabel, $0.text]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
}

struct JournalSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var ruleKind: ExclusionKind = .bundleID
    @State private var ruleValue = ""

    var body: some View {
        Form {
            Section("Permissions") {
                permissionRow("Accessibility", granted: model.permissions.accessibility) {
                    model.refreshPermissions(prompt: true)
                    openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                }
                permissionRow("Screen Recording", granted: model.permissions.screenRecording) {
                    model.requestScreenRecording()
                    openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
                }
                Button("Recheck Permissions") { model.refreshPermissions() }
            }
            Section("Never capture") {
                ForEach(model.rules) { rule in
                    HStack {
                        Text(rule.kind == .bundleID ? "App" : "Window title")
                            .foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                        Text(rule.value)
                        Spacer()
                        Button(role: .destructive) { model.removeRule(rule.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Picker("Type", selection: $ruleKind) {
                        Text("Bundle ID").tag(ExclusionKind.bundleID)
                        Text("Window title contains").tag(ExclusionKind.windowTitle)
                    }
                    .labelsHidden().frame(width: 170)
                    TextField(ruleKind == .bundleID ? "com.example.app" : "Private", text: $ruleValue)
                    Button("Add") { model.addRule(kind: ruleKind, value: ruleValue); ruleValue = "" }
                        .disabled(ruleValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Section {
                Text("Screenshots exist only in memory during OCR and are never saved. Keyboard, mouse, clipboard, and audio activity are not captured.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 440)
        .onAppear { model.refreshPermissions(); Task { await model.refresh() } }
    }

    @ViewBuilder
    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange)
            Spacer()
            if !granted { Button("Enable…", action: action) }
        }
    }

    private func openSettings(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}
