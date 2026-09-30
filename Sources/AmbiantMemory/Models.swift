import Foundation
import ApplicationServices

enum CaptureSource: String, Codable, Sendable {
    case accessibility
    case ocr
    case combined
    case metadata
}

struct ElementMetadata: Codable, Hashable, Sendable {
    var role: String
    var label: String
    var frame: CGRect?
}

struct ActiveWindowContext: @unchecked Sendable {
    var pid: pid_t
    var bundleID: String
    var appName: String
    var windowTitle: String
    var accessibilityWindow: AXUIElement?
}

struct SemanticSnapshot: Sendable {
    var context: ActiveWindowContext
    var timestamp: Date
    var text: [String]
    var elements: [ElementMetadata]
    var quality: Double
}

struct OCRSnapshot: Sendable {
    var text: [String]
    var averageConfidence: Double
}

struct CapturedSnapshot: Sendable {
    var timestamp: Date
    var context: ActiveWindowContext
    var text: [String]
    var elements: [ElementMetadata]
    var source: CaptureSource
    var quality: Double
}

struct ObservationCandidate: Sendable {
    var timestamp: Date
    var bundleID: String
    var appName: String
    var windowTitle: String
    var normalizedText: String
    var source: CaptureSource
    var contentHash: String
    var quality: Double
    var workLabel: String
}

struct Observation: Identifiable, Codable, Sendable {
    var id: Int64
    var timestamp: Date
    var duration: TimeInterval
    var bundleID: String
    var appName: String
    var windowTitle: String
    var normalizedText: String
    var source: CaptureSource
    var contentHash: String
    var quality: Double
}

struct ActivityBlock: Identifiable, Codable, Sendable {
    var id: Int64
    var start: Date
    var end: Date
    var bundleID: String
    var appName: String
    var representativeTitle: String
    var workLabel: String
    var text: String
}

enum ExclusionKind: String, Codable, Sendable {
    case bundleID
    case windowTitle
}

struct ExclusionRule: Identifiable, Codable, Sendable {
    var id: Int64
    var kind: ExclusionKind
    var value: String
}

struct CapturePermissions: Sendable {
    var accessibility: Bool
    var screenRecording: Bool
}

enum CaptureTrigger: Sendable {
    case activated
    case accessibilityChanged
    case poll
    case sessionLocked
    case sessionUnlocked
}

enum ExportFormat: String, Sendable {
    case json
    case csv
}
