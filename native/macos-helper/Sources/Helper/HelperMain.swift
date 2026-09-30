import Foundation
import MacOSHelperProtocol

private final class StandardOutputWriter {
    private let handle: FileHandle
    private let lock = NSLock()
    private let codec = ProtocolCodec()

    init(handle: FileHandle = .standardOutput) {
        self.handle = handle
    }

    func write(_ response: ResponseEnvelope) throws {
        var frame = try codec.encode(response: response)
        frame.append(0x0A)

        lock.lock()
        defer { lock.unlock() }
        try handle.write(contentsOf: frame)
    }
}

private struct HelperRuntime {
    private let input = FileHandle.standardInput
    private let output = StandardOutputWriter()
    private let codec = ProtocolCodec()
    private let router = ProtocolRouter()

    mutating func run() throws {
        var framer = JSONLineFramer()
        var shouldTerminate = false

        while !shouldTerminate {
            // Bound every read as well as the accumulated line so a peer cannot
            // force a transient allocation proportional to its entire write.
            let chunk = try input.read(upToCount: 64 * 1_024) ?? Data()
            if chunk.isEmpty {
                for event in framer.finish() {
                    shouldTerminate = try process(event)
                }
                break
            }

            for event in framer.append(chunk) {
                shouldTerminate = try process(event)
                if shouldTerminate { break }
            }
        }
    }

    private func process(_ event: LineFrameEvent) throws -> Bool {
        switch event {
        case let .failure(error):
            try output.write(.failure(
                id: "unknown",
                protocol: router.responseProtocol,
                error: error
            ))
            return false

        case let .line(line):
            do {
                let request = try codec.decodeRequest(line: line)
                let outcome = router.handle(request)
                try output.write(outcome.response)
                return outcome.shouldTerminate
            } catch let error as ProtocolFailure {
                try output.write(.failure(
                    id: recoverRequestID(from: line) ?? "unknown",
                    protocol: router.responseProtocol,
                    error: error
                ))
                return false
            }
        }
    }

    /// Recover only a bounded request identifier for correlation. No other
    /// malformed input is reflected into responses or diagnostics.
    private func recoverRequestID(from line: Data) -> String? {
        guard line.count <= ProtocolLimits.maximumLineBytes,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let id = object["id"] as? String,
              !id.isEmpty,
              id.utf8.count <= ProtocolLimits.maximumIdentifierBytes,
              id.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return id
    }
}

do {
    var runtime = HelperRuntime()
    try runtime.run()
} catch {
    // stdout is protocol-only. Keep stderr deliberately generic so input data is
    // never copied into diagnostics.
    FileHandle.standardError.write(Data("macOS helper terminated after an I/O failure\n".utf8))
    exit(1)
}
