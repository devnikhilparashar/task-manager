import XCTest
@testable import AmbiantMemory

final class ObservationProcessorTests: XCTestCase {
    func testNormalizationDeduplicatesAndDropsGenericChrome() {
        let context = ActiveWindowContext(pid: 1, bundleID: "com.example.Editor", appName: "Editor", windowTitle: "Plan.md — Editor", accessibilityWindow: nil)
        let snapshot = CapturedSnapshot(timestamp: Date(), context: context, text: ["  Project   plan ", "Project plan", "Close", "Next task"], elements: [], source: .accessibility, quality: 0.8)
        let result = ObservationProcessor().process(snapshot: snapshot)

        XCTAssertEqual(result.normalizedText, "Project plan\nNext task")
        XCTAssertEqual(result.workLabel, "Plan.md")
        XCTAssertEqual(result.source, .accessibility)
        XCTAssertEqual(result.contentHash.count, 64)
    }

    func testHashChangesWithWindowIdentity() {
        let processor = ObservationProcessor()
        func candidate(title: String) -> ObservationCandidate {
            processor.process(snapshot: CapturedSnapshot(timestamp: Date(), context: ActiveWindowContext(pid: 1, bundleID: "app", appName: "App", windowTitle: title, accessibilityWindow: nil), text: ["Same"], elements: [], source: .accessibility, quality: 1))
        }
        XCTAssertNotEqual(candidate(title: "One").contentHash, candidate(title: "Two").contentHash)
    }
}
