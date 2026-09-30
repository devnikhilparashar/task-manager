import XCTest
@testable import AmbiantMemory

final class SQLiteTimelineStoreTests: XCTestCase {
    func testDuplicateObservationExtendsOneBlock() async throws {
        let store = try makeStore()
        let now = Date()
        try await store.save(candidate(at: now, hash: "same"))
        try await store.save(candidate(at: now.addingTimeInterval(30), hash: "same"))
        let blocks = try await store.blocks(for: now)

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].end.timeIntervalSince(blocks[0].start), 30, accuracy: 0.01)
    }

    func testSubjectChangeCreatesNewBlock() async throws {
        let store = try makeStore()
        let now = Date()
        try await store.save(candidate(at: now, hash: "one", title: "First"))
        try await store.save(candidate(at: now.addingTimeInterval(10), hash: "two", title: "Second"))
        let blocks = try await store.blocks(for: now)
        XCTAssertEqual(blocks.count, 2)
    }

    func testExportContainsNoImageData() async throws {
        let store = try makeStore()
        let now = Date()
        try await store.save(candidate(at: now, hash: "one"))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        try await store.export(day: now, format: .json, to: output)
        let text = try String(contentsOf: output, encoding: .utf8)
        XCTAssertTrue(text.contains("Example document"))
        XCTAssertFalse(text.lowercased().contains("screenshot"))
        XCTAssertFalse(text.lowercased().contains("pixel"))
    }

    private func makeStore() throws -> SQLiteTimelineStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return try SQLiteTimelineStore(url: directory.appendingPathComponent("test.sqlite3"))
    }

    private func candidate(at date: Date, hash: String, title: String = "Example document") -> ObservationCandidate {
        ObservationCandidate(timestamp: date, bundleID: "com.example.App", appName: "App", windowTitle: title, normalizedText: "Some captured text", source: .accessibility, contentHash: hash, quality: 0.9, workLabel: title)
    }
}
