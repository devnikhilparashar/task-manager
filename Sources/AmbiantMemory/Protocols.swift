import Foundation

@MainActor
protocol ActivitySource: AnyObject {
    func observe() -> AsyncStream<CaptureTrigger>
    func currentContext() -> ActiveWindowContext?
    func updatePollingInterval(_ interval: TimeInterval)
}

protocol AccessibilityExtracting: Sendable {
    func extract(from context: ActiveWindowContext) async -> SemanticSnapshot
}

protocol ScreenTextExtracting: Sendable {
    func extract(window context: ActiveWindowContext) async throws -> OCRSnapshot
}

protocol ObservationProcessing: Sendable {
    func process(snapshot: CapturedSnapshot) -> ObservationCandidate
}

protocol TimelineStoring: Sendable {
    func save(_ candidate: ObservationCandidate) async throws
    func blocks(for day: Date) async throws -> [ActivityBlock]
    func exclusionRules() async throws -> [ExclusionRule]
    func addExclusion(kind: ExclusionKind, value: String) async throws
    func removeExclusion(id: Int64) async throws
    func export(day: Date, format: ExportFormat, to url: URL) async throws
    func closeOpenBlock(at date: Date) async throws
}
