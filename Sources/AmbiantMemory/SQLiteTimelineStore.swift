import Foundation
import CSQLite

enum StoreError: LocalizedError {
    case open(String)
    case execute(String)

    var errorDescription: String? {
        switch self {
        case .open(let message): return "Could not open activity database: \(message)"
        case .execute(let message): return "Database operation failed: \(message)"
        }
    }
}

actor SQLiteTimelineStore: TimelineStoring {
    private var db: OpaquePointer?
    private let blockGap: TimeInterval

    init(url: URL, blockGap: TimeInterval = 120) throws {
        self.blockGap = blockGap
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            throw StoreError.open(db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error")
        }
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA foreign_keys=ON")
        try migrate()
    }

    deinit { sqlite3_close(db) }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS schema_version(version INTEGER NOT NULL);
        INSERT INTO schema_version(version) SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM schema_version);
        CREATE TABLE IF NOT EXISTS observations(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp REAL NOT NULL,
          duration REAL NOT NULL DEFAULT 0,
          bundle_id TEXT NOT NULL,
          app_name TEXT NOT NULL,
          window_title TEXT NOT NULL,
          normalized_text TEXT NOT NULL,
          source TEXT NOT NULL,
          content_hash TEXT NOT NULL,
          quality REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS observations_timestamp_idx ON observations(timestamp);
        CREATE TABLE IF NOT EXISTS activity_blocks(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          start_time REAL NOT NULL,
          end_time REAL NOT NULL,
          bundle_id TEXT NOT NULL,
          app_name TEXT NOT NULL,
          representative_title TEXT NOT NULL,
          work_label TEXT NOT NULL,
          text TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS blocks_start_idx ON activity_blocks(start_time);
        CREATE TABLE IF NOT EXISTS block_observations(
          block_id INTEGER NOT NULL REFERENCES activity_blocks(id) ON DELETE CASCADE,
          observation_id INTEGER NOT NULL REFERENCES observations(id) ON DELETE CASCADE,
          PRIMARY KEY(block_id, observation_id)
        );
        CREATE TABLE IF NOT EXISTS exclusion_rules(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          kind TEXT NOT NULL,
          value TEXT NOT NULL,
          UNIQUE(kind, value)
        );
        CREATE TABLE IF NOT EXISTS capture_state(
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
        """)
    }

    func save(_ candidate: ObservationCandidate) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            if let last = try lastObservation(),
               last.bundleID == candidate.bundleID,
               last.windowTitle == candidate.windowTitle,
               last.contentHash == candidate.contentHash {
                try run("UPDATE observations SET duration = MAX(0, ? - timestamp) WHERE id = ?", [.double(candidate.timestamp.timeIntervalSince1970), .int(last.id)])
                try extendMatchingBlock(candidate: candidate, observationID: last.id)
            } else {
                let observationID = try insertObservation(candidate)
                try appendToBlock(candidate: candidate, observationID: observationID)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func blocks(for day: Date) throws -> [ActivityBlock] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        var rows: [ActivityBlock] = []
        try query("""
          SELECT id,start_time,end_time,bundle_id,app_name,representative_title,work_label,text
          FROM activity_blocks WHERE start_time < ? AND end_time >= ? ORDER BY start_time DESC
        """, [.double(end.timeIntervalSince1970), .double(start.timeIntervalSince1970)]) { statement in
            rows.append(ActivityBlock(
                id: sqlite3_column_int64(statement, 0),
                start: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                end: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                bundleID: Self.text(statement, 3),
                appName: Self.text(statement, 4),
                representativeTitle: Self.text(statement, 5),
                workLabel: Self.text(statement, 6),
                text: Self.text(statement, 7)
            ))
        }
        return rows
    }

    func exclusionRules() throws -> [ExclusionRule] {
        var rules: [ExclusionRule] = []
        try query("SELECT id,kind,value FROM exclusion_rules ORDER BY kind,value", []) { statement in
            guard let kind = ExclusionKind(rawValue: Self.text(statement, 1)) else { return }
            rules.append(ExclusionRule(id: sqlite3_column_int64(statement, 0), kind: kind, value: Self.text(statement, 2)))
        }
        return rules
    }

    func addExclusion(kind: ExclusionKind, value: String) throws {
        try run("INSERT OR IGNORE INTO exclusion_rules(kind,value) VALUES(?,?)", [.text(kind.rawValue), .text(value)])
    }

    func removeExclusion(id: Int64) throws {
        try run("DELETE FROM exclusion_rules WHERE id=?", [.int(id)])
    }

    func closeOpenBlock(at date: Date) throws {
        try run("UPDATE activity_blocks SET end_time = MIN(end_time, ?) WHERE id=(SELECT id FROM activity_blocks ORDER BY end_time DESC LIMIT 1)", [.double(date.timeIntervalSince1970)])
    }

    func export(day: Date, format: ExportFormat, to url: URL) throws {
        let result = try blocks(for: day)
        let data: Data
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            data = try encoder.encode(result)
        case .csv:
            let formatter = ISO8601DateFormatter()
            let header = "start,end,bundle_id,app_name,title,work_label,text\n"
            let body = result.map { block in
                [formatter.string(from: block.start), formatter.string(from: block.end), block.bundleID, block.appName, block.representativeTitle, block.workLabel, block.text]
                    .map(Self.csvEscape).joined(separator: ",")
            }.joined(separator: "\n")
            data = Data((header + body).utf8)
        }
        try data.write(to: url, options: .atomic)
    }

    private func insertObservation(_ item: ObservationCandidate) throws -> Int64 {
        try run("""
          INSERT INTO observations(timestamp,duration,bundle_id,app_name,window_title,normalized_text,source,content_hash,quality)
          VALUES(?,0,?,?,?,?,?,?,?)
        """, [.double(item.timestamp.timeIntervalSince1970), .text(item.bundleID), .text(item.appName), .text(item.windowTitle), .text(item.normalizedText), .text(item.source.rawValue), .text(item.contentHash), .double(item.quality)])
        return sqlite3_last_insert_rowid(db)
    }

    private func appendToBlock(candidate: ObservationCandidate, observationID: Int64) throws {
        var block: (id: Int64, end: Date, bundleID: String, title: String)?
        try query("SELECT id,end_time,bundle_id,representative_title FROM activity_blocks ORDER BY end_time DESC LIMIT 1", []) { statement in
            block = (sqlite3_column_int64(statement, 0), Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)), Self.text(statement, 2), Self.text(statement, 3))
        }
        let sameSubject = block?.bundleID == candidate.bundleID && Self.subject(block?.title ?? "") == Self.subject(candidate.windowTitle)
        if let block, sameSubject, candidate.timestamp.timeIntervalSince(block.end) <= blockGap {
            try run("UPDATE activity_blocks SET end_time=?, representative_title=?, work_label=?, text=? WHERE id=?", [.double(candidate.timestamp.timeIntervalSince1970), .text(candidate.windowTitle), .text(candidate.workLabel), .text(candidate.normalizedText), .int(block.id)])
            try run("INSERT INTO block_observations(block_id,observation_id) VALUES(?,?)", [.int(block.id), .int(observationID)])
        } else {
            try run("INSERT INTO activity_blocks(start_time,end_time,bundle_id,app_name,representative_title,work_label,text) VALUES(?,?,?,?,?,?,?)", [.double(candidate.timestamp.timeIntervalSince1970), .double(candidate.timestamp.timeIntervalSince1970), .text(candidate.bundleID), .text(candidate.appName), .text(candidate.windowTitle), .text(candidate.workLabel), .text(candidate.normalizedText)])
            let blockID = sqlite3_last_insert_rowid(db)
            try run("INSERT INTO block_observations(block_id,observation_id) VALUES(?,?)", [.int(blockID), .int(observationID)])
        }
    }

    private func extendMatchingBlock(candidate: ObservationCandidate, observationID: Int64) throws {
        try run("UPDATE activity_blocks SET end_time=? WHERE id=(SELECT block_id FROM block_observations WHERE observation_id=? LIMIT 1)", [.double(candidate.timestamp.timeIntervalSince1970), .int(observationID)])
    }

    private func lastObservation() throws -> Observation? {
        var result: Observation?
        try query("SELECT id,timestamp,duration,bundle_id,app_name,window_title,normalized_text,source,content_hash,quality FROM observations ORDER BY timestamp DESC LIMIT 1", []) { statement in
            result = Observation(id: sqlite3_column_int64(statement, 0), timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)), duration: sqlite3_column_double(statement, 2), bundleID: Self.text(statement, 3), appName: Self.text(statement, 4), windowTitle: Self.text(statement, 5), normalizedText: Self.text(statement, 6), source: CaptureSource(rawValue: Self.text(statement, 7)) ?? .metadata, contentHash: Self.text(statement, 8), quality: sqlite3_column_double(statement, 9))
        }
        return result
    }

    private enum Binding { case text(String), double(Double), int(Int64) }

    private func execute(_ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { throw currentError() }
    }

    private func run(_ sql: String, _ values: [Binding]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw currentError() }
        defer { sqlite3_finalize(statement) }
        bind(values, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw currentError() }
    }

    private func query(_ sql: String, _ values: [Binding], row: (OpaquePointer) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw currentError() }
        defer { sqlite3_finalize(statement) }
        bind(values, to: statement)
        while sqlite3_step(statement) == SQLITE_ROW { row(statement) }
    }

    private func bind(_ values: [Binding], to statement: OpaquePointer?) {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .text(let text): sqlite3_bind_text(statement, index, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .double(let number): sqlite3_bind_double(statement, index, number)
            case .int(let number): sqlite3_bind_int64(statement, index, number)
            }
        }
    }

    private func currentError() -> StoreError { .execute(db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error") }
    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String { sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "" }
    private static func subject(_ title: String) -> String { title.lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func csvEscape(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
}
