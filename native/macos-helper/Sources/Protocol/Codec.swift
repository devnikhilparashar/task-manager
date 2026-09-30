import Foundation

public enum ProtocolLimits {
    /// Maximum number of bytes before the JSONL newline delimiter.
    public static let maximumLineBytes = 4 * 1_024 * 1_024
    public static let maximumIdentifierBytes = 128
    public static let maximumMethodBytes = 128
}

public struct ProtocolCodec: Sendable {
    public init() {}

    public func decodeRequest(line: Data) throws -> RequestEnvelope {
        guard line.count <= ProtocolLimits.maximumLineBytes else {
            throw ProtocolFailure(
                code: .payloadTooLarge,
                message: "Protocol frame exceeds the maximum line size",
                details: .object([
                    "maximumLineBytes": .integer(Int64(ProtocolLimits.maximumLineBytes))
                ])
            )
        }
        guard !line.isEmpty else {
            throw invalidRequest("Protocol frame must not be empty")
        }
        guard String(data: line, encoding: .utf8) != nil else {
            throw invalidRequest("Protocol frame must be valid UTF-8")
        }

        let rawObject: Any
        do {
            rawObject = try JSONSerialization.jsonObject(with: line, options: [])
        } catch {
            throw invalidRequest("Protocol frame must contain valid JSON")
        }

        guard let object = rawObject as? [String: Any] else {
            throw invalidRequest("Protocol frame must be a JSON object")
        }

        let allowedKeys: Set<String> = ["kind", "protocol", "id", "method", "deadlineMs", "params"]
        let unknownCount = Set(object.keys).subtracting(allowedKeys).count
        guard unknownCount == 0 else {
            throw ProtocolFailure(
                code: .invalidRequest,
                message: "Request contains unknown envelope fields",
                details: .object(["unknownFieldCount": .integer(Int64(unknownCount))])
            )
        }

        if let params = object["params"], !(params is [String: Any]) {
            throw ProtocolFailure(
                code: .invalidArgument,
                message: "Request params must be a JSON object"
            )
        }

        let request: RequestEnvelope
        do {
            request = try JSONDecoder().decode(RequestEnvelope.self, from: line)
        } catch {
            throw invalidRequest("Request envelope has missing or invalid fields")
        }

        guard request.kind == "request" else {
            throw invalidRequest("Envelope kind must be request")
        }
        guard !request.id.isEmpty,
              request.id.utf8.count <= ProtocolLimits.maximumIdentifierBytes,
              request.id.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw invalidRequest("Request id is invalid")
        }
        guard !request.method.isEmpty,
              request.method.utf8.count <= ProtocolLimits.maximumMethodBytes,
              request.method.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw invalidRequest("Request method is invalid")
        }
        if let deadlineMs = request.deadlineMs, deadlineMs <= 0 {
            throw ProtocolFailure(
                code: .invalidArgument,
                message: "deadlineMs must be a positive integer"
            )
        }
        return request
    }

    public func encode(response: ResponseEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(response)
        guard data.count <= ProtocolLimits.maximumLineBytes else {
            throw ProtocolFailure(
                code: .payloadTooLarge,
                message: "Encoded protocol frame exceeds the maximum line size"
            )
        }
        return data
    }

    private func invalidRequest(_ message: String) -> ProtocolFailure {
        ProtocolFailure(code: .invalidRequest, message: message)
    }
}

public enum LineFrameEvent: Equatable, Sendable {
    case line(Data)
    case failure(ProtocolFailure)
}

/// Incremental framing prevents an untrusted peer from making the helper allocate
/// an unbounded string before the 4 MiB protocol limit can be checked.
public struct JSONLineFramer: Sendable {
    private var buffer = Data()
    private var discardingOversizedLine = false

    public init() {
        buffer.reserveCapacity(64 * 1_024)
    }

    public mutating func append(_ data: Data) -> [LineFrameEvent] {
        var events: [LineFrameEvent] = []

        for byte in data {
            if byte == 0x0A {
                if discardingOversizedLine {
                    discardingOversizedLine = false
                    buffer.removeAll(keepingCapacity: true)
                } else {
                    events.append(.line(buffer))
                    buffer.removeAll(keepingCapacity: true)
                }
                continue
            }

            if discardingOversizedLine {
                continue
            }

            if buffer.count == ProtocolLimits.maximumLineBytes {
                discardingOversizedLine = true
                buffer.removeAll(keepingCapacity: true)
                events.append(.failure(ProtocolFailure(
                    code: .payloadTooLarge,
                    message: "Protocol frame exceeds the maximum line size",
                    details: .object([
                        "maximumLineBytes": .integer(Int64(ProtocolLimits.maximumLineBytes))
                    ])
                )))
            } else {
                buffer.append(byte)
            }
        }
        return events
    }

    public mutating func finish() -> [LineFrameEvent] {
        guard !discardingOversizedLine, !buffer.isEmpty else {
            buffer.removeAll(keepingCapacity: false)
            discardingOversizedLine = false
            return []
        }
        let finalLine = buffer
        buffer.removeAll(keepingCapacity: false)
        return [.line(finalLine)]
    }
}
