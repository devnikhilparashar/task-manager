import Foundation
import CryptoKit

struct ObservationProcessor: ObservationProcessing {
    private let chromeTerms = Set(["close", "minimize", "zoom", "toolbar", "sidebar", "scroll area"])

    func process(snapshot: CapturedSnapshot) -> ObservationCandidate {
        var seen = Set<String>()
        let cleaned = snapshot.text.compactMap { line -> String? in
            let value = line.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count > 1, !chromeTerms.contains(value.lowercased()) else { return nil }
            let key = value.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return value
        }
        let normalized = cleaned.joined(separator: "\n")
        let identity = [snapshot.context.bundleID, snapshot.context.windowTitle, normalized].joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let label = workLabel(title: snapshot.context.windowTitle, lines: cleaned, app: snapshot.context.appName)
        return ObservationCandidate(
            timestamp: snapshot.timestamp,
            bundleID: snapshot.context.bundleID,
            appName: snapshot.context.appName,
            windowTitle: snapshot.context.windowTitle,
            normalizedText: normalized,
            source: snapshot.source,
            contentHash: digest,
            quality: snapshot.quality,
            workLabel: label
        )
    }

    private func workLabel(title: String, lines: [String], app: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed.caseInsensitiveCompare(app) != .orderedSame {
            let separators = [" — ", " – ", " - ", " | "]
            for separator in separators {
                if let first = trimmed.components(separatedBy: separator).first, first.count >= 3 {
                    return String(first.prefix(160))
                }
            }
            return String(trimmed.prefix(160))
        }
        return String((lines.first ?? app).prefix(160))
    }
}
