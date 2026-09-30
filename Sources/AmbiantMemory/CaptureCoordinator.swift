import Foundation
import ApplicationServices
import CoreGraphics

@MainActor
final class CaptureCoordinator {
    private let source: ActivitySource
    private let accessibility: AccessibilityExtracting
    private let ocr: ScreenTextExtracting
    private let processor: ObservationProcessing
    private let store: TimelineStoring
    private let policy: CapturePolicy
    private let ownBundleID: String
    private var streamTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var resumeTask: Task<Void, Never>?
    private var rules: [ExclusionRule] = []
    private var stableSamples = 0
    private var previousHash = ""
    private var lastOCR: [String: (date: Date, title: String)] = [:]
    private var sessionLocked = false
    private var captureInProgress = false
    private(set) var isPaused = false

    var onStatus: ((String) -> Void)?
    var onSaved: (() -> Void)?
    var onError: ((String) -> Void)?

    init(source: ActivitySource, accessibility: AccessibilityExtracting, ocr: ScreenTextExtracting, processor: ObservationProcessing, store: TimelineStoring, policy: CapturePolicy, ownBundleID: String) {
        self.source = source
        self.accessibility = accessibility
        self.ocr = ocr
        self.processor = processor
        self.store = store
        self.policy = policy
        self.ownBundleID = ownBundleID
    }

    func start() {
        isPaused = false
        onStatus?("Recording")
        guard streamTask == nil else {
            scheduleCapture(immediate: true)
            return
        }
        streamTask = Task { [weak self] in
            guard let self else { return }
            self.rules = (try? await self.store.exclusionRules()) ?? []
            for await trigger in self.source.observe() {
                if Task.isCancelled { return }
                self.handle(trigger)
            }
        }
    }

    func stop() {
        isPaused = true
        debounceTask?.cancel()
        debounceTask = nil
        Task { try? await store.closeOpenBlock(at: Date()) }
        onStatus?("Paused")
    }

    func pause(for duration: TimeInterval) {
        stop()
        resumeTask?.cancel()
        resumeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.start()
        }
    }

    func refreshRules() async { rules = (try? await store.exclusionRules()) ?? [] }

    func permissions(promptForAccessibility: Bool = false) -> CapturePermissions {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptForAccessibility] as CFDictionary
        return CapturePermissions(accessibility: AXIsProcessTrustedWithOptions(options), screenRecording: CGPreflightScreenCaptureAccess())
    }

    func requestScreenRecording() { _ = CGRequestScreenCaptureAccess() }

    private func handle(_ trigger: CaptureTrigger) {
        switch trigger {
        case .sessionLocked:
            sessionLocked = true
            debounceTask?.cancel()
            Task { try? await store.closeOpenBlock(at: Date()) }
            onStatus?("Session inactive")
        case .sessionUnlocked:
            sessionLocked = false
            onStatus?("Recording")
            scheduleCapture(immediate: true)
        case .activated:
            stableSamples = 0
            source.updatePollingInterval(policy.activePollingInterval)
            scheduleCapture(immediate: false)
        case .accessibilityChanged:
            scheduleCapture(immediate: false)
        case .poll:
            scheduleCapture(immediate: true)
        }
    }

    private func scheduleCapture(immediate: Bool) {
        guard !isPaused, !sessionLocked else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            if !immediate { try? await Task.sleep(for: .seconds(self.policy.debounceInterval)) }
            guard !Task.isCancelled else { return }
            await self.capture()
        }
    }

    private func capture() async {
        guard !captureInProgress else { return }
        captureInProgress = true
        defer { captureInProgress = false }
        guard let context = source.currentContext() else {
            onStatus?("Waiting for another app")
            return
        }
        guard !policy.isExcluded(context, rules: rules, ownBundleID: ownBundleID) else { return }
        onStatus?("Recording")
        let semantic = await accessibility.extract(from: context)
        var text = semantic.text
        var sourceType: CaptureSource = text.isEmpty ? .metadata : .accessibility
        var quality = semantic.quality
        let permissions = permissions()

        if !policy.hasUsefulText(text, quality: quality), permissions.screenRecording, shouldRunOCR(context) {
            do {
                let result = try await ocr.extract(window: context)
                lastOCR[context.bundleID] = (Date(), context.windowTitle)
                if !result.text.isEmpty {
                    text.append(contentsOf: result.text)
                    sourceType = semantic.text.isEmpty ? .ocr : .combined
                    quality = max(quality, result.averageConfidence)
                }
            } catch {
                onError?("OCR unavailable: \(error.localizedDescription)")
            }
        }
        let snapshot = CapturedSnapshot(timestamp: Date(), context: context, text: text, elements: semantic.elements, source: sourceType, quality: quality)
        let candidate = processor.process(snapshot: snapshot)
        do {
            try await store.save(candidate)
            updateAdaptivePolling(hash: candidate.contentHash)
            onSaved?()
        } catch {
            onError?(error.localizedDescription)
        }
    }

    private func shouldRunOCR(_ context: ActiveWindowContext) -> Bool {
        guard let last = lastOCR[context.bundleID] else { return true }
        return last.title != context.windowTitle || Date().timeIntervalSince(last.date) >= policy.ocrMinimumInterval
    }

    private func updateAdaptivePolling(hash: String) {
        if hash == previousHash { stableSamples += 1 } else { stableSamples = 0 }
        previousHash = hash
        source.updatePollingInterval(stableSamples >= policy.stableSampleThreshold ? policy.stablePollingInterval : policy.activePollingInterval)
    }
}
