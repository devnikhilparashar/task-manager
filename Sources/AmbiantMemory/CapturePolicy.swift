import Foundation

struct CapturePolicy: Sendable {
    var debounceInterval: TimeInterval = 0.75
    var activePollingInterval: TimeInterval = 5
    var stablePollingInterval: TimeInterval = 15
    var stableSampleThreshold = 3
    var ocrMinimumInterval: TimeInterval = 10
    var blockGap: TimeInterval = 120
    var unusableContentGap: TimeInterval = 300
    var minimumUsefulCharacters = 24
    var maximumAXDepth = 12
    var maximumAXNodes = 1_500
    var maximumAXDuration: TimeInterval = 0.35

    func hasUsefulText(_ lines: [String], quality: Double) -> Bool {
        let meaningful = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 && !$0.allSatisfy { $0.isPunctuation || $0.isWhitespace } }
        return meaningful.joined(separator: " ").count >= minimumUsefulCharacters && quality >= 0.2
    }

    func isExcluded(_ context: ActiveWindowContext, rules: [ExclusionRule], ownBundleID: String) -> Bool {
        if context.bundleID == ownBundleID { return true }
        return rules.contains { rule in
            switch rule.kind {
            case .bundleID:
                return context.bundleID.caseInsensitiveCompare(rule.value) == .orderedSame
            case .windowTitle:
                return context.windowTitle.range(of: rule.value, options: .caseInsensitive) != nil
            }
        }
    }
}
