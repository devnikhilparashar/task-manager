import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var blocks: [ActivityBlock] = []
    @Published var rules: [ExclusionRule] = []
    @Published var status = "Starting"
    @Published var errorMessage: String?
    @Published var permissions = CapturePermissions(accessibility: false, screenRecording: false)
    @Published var selectedDay = Date()
    @Published var lastCaptureAt: Date?

    let store: SQLiteTimelineStore
    let coordinator: CaptureCoordinator
    private var hasStarted = false

    static func make() -> AppModel {
        do {
            let policy = CapturePolicy()
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("AmbiantMemory", isDirectory: true)
            let store = try SQLiteTimelineStore(url: base.appendingPathComponent("journal.sqlite3"), blockGap: policy.blockGap)
            let source = MacActivitySource()
            let coordinator = CaptureCoordinator(source: source, accessibility: MacAccessibilityExtractor(policy: policy), ocr: ScreenOCRExtractor(), processor: ObservationProcessor(), store: store, policy: policy, ownBundleID: Bundle.main.bundleIdentifier ?? "local.ambiant-memory")
            return AppModel(store: store, coordinator: coordinator)
        } catch {
            fatalError("Unable to initialize AmbiantMemory: \(error)")
        }
    }

    init(store: SQLiteTimelineStore, coordinator: CaptureCoordinator) {
        self.store = store
        self.coordinator = coordinator
        coordinator.onStatus = { [weak self] in self?.status = $0 }
        coordinator.onError = { [weak self] in self?.errorMessage = $0 }
        coordinator.onSaved = { [weak self] in
            self?.lastCaptureAt = Date()
            self?.errorMessage = nil
            Task { await self?.refresh() }
        }
        // MenuBarExtra builds its content lazily. Start from the model lifecycle so
        // capture begins at application launch, even if the menu is never opened.
        Task { @MainActor [weak self] in self?.start() }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        coordinator.start()
        refreshPermissions()
        Task { await refresh() }
    }

    func toggleCapture() { coordinator.isPaused ? coordinator.start() : coordinator.stop() }
    func pause15Minutes() { coordinator.pause(for: 15 * 60) }

    func refresh() async {
        do {
            blocks = try await store.blocks(for: selectedDay)
            rules = try await store.exclusionRules()
        } catch { errorMessage = error.localizedDescription }
    }

    func refreshPermissions(prompt: Bool = false) { permissions = coordinator.permissions(promptForAccessibility: prompt) }
    func requestScreenRecording() { coordinator.requestScreenRecording(); refreshPermissions() }

    func addRule(kind: ExclusionKind, value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            try? await store.addExclusion(kind: kind, value: trimmed)
            await coordinator.refreshRules()
            await refresh()
        }
    }

    func removeRule(_ id: Int64) {
        Task {
            try? await store.removeExclusion(id: id)
            await coordinator.refreshRules()
            await refresh()
        }
    }

    func export(_ format: ExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "activity-\(Self.dayFormatter.string(from: selectedDay)).\(format.rawValue)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do { try await store.export(day: selectedDay, format: format, to: url) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; return formatter
    }()
}
