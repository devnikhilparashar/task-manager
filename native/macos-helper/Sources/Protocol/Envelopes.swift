import Foundation

public struct ProtocolVersion: Equatable, Hashable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int

    public init(major: Int, minor: Int) {
        precondition(major >= 0 && minor >= 0)
        self.major = major
        self.minor = minor
    }

    public init?(_ rawValue: String) {
        let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts.allSatisfy({ part in
                  !part.isEmpty && part.unicodeScalars.allSatisfy { (48...57).contains($0.value) }
              }),
              let major = Int(parts[0]),
              let minor = Int(parts[1]) else {
            return nil
        }
        self.init(major: major, minor: minor)
    }

    public var description: String { "\(major).\(minor)" }
}

public struct RequestEnvelope: Codable, Equatable, Sendable {
    public let kind: String
    public let `protocol`: String
    public let id: String
    public let method: String
    public let deadlineMs: Int?
    public let params: JSONValue?

    public init(
        kind: String = "request",
        protocol: String,
        id: String,
        method: String,
        deadlineMs: Int? = nil,
        params: JSONValue? = nil
    ) {
        self.kind = kind
        self.protocol = `protocol`
        self.id = id
        self.method = method
        self.deadlineMs = deadlineMs
        self.params = params
    }
}

public enum ProtocolErrorCode: String, Codable, CaseIterable, Sendable {
    case invalidRequest = "INVALID_REQUEST"
    case unsupportedProtocol = "UNSUPPORTED_PROTOCOL"
    case unsupportedMethod = "UNSUPPORTED_METHOD"
    case invalidArgument = "INVALID_ARGUMENT"
    case payloadTooLarge = "PAYLOAD_TOO_LARGE"
    case permissionAXDenied = "PERMISSION_AX_DENIED"
    case permissionScreenDenied = "PERMISSION_SCREEN_DENIED"
    case permissionRevoked = "PERMISSION_REVOKED"
    case noActiveApplication = "NO_ACTIVE_APPLICATION"
    case noFocusedWindow = "NO_FOCUSED_WINDOW"
    case windowChanged = "WINDOW_CHANGED"
    case windowGone = "WINDOW_GONE"
    case excludedTarget = "EXCLUDED_TARGET"
    case axUnavailable = "AX_UNAVAILABLE"
    case axInvalidElement = "AX_INVALID_ELEMENT"
    case axTimeout = "AX_TIMEOUT"
    case axTruncated = "AX_TRUNCATED"
    case captureFailed = "CAPTURE_FAILED"
    case ocrFailed = "OCR_FAILED"
    case ocrRateLimited = "OCR_RATE_LIMITED"
    case cancelled = "CANCELLED"
    case deadlineExceeded = "DEADLINE_EXCEEDED"
    case busy = "BUSY"
    case `internal` = "INTERNAL"
}

public struct ProtocolFailure: Error, Codable, Equatable, Sendable {
    public let code: ProtocolErrorCode
    public let message: String
    public let retryable: Bool
    public let details: JSONValue?

    public init(
        code: ProtocolErrorCode,
        message: String,
        retryable: Bool = false,
        details: JSONValue? = nil
    ) {
        self.code = code
        self.message = message
        self.retryable = retryable
        self.details = details
    }
}

public struct ResponseEnvelope: Codable, Equatable, Sendable {
    public let kind: String
    public let `protocol`: String
    public let id: String
    public let ok: Bool
    public let result: JSONValue?
    public let error: ProtocolFailure?

    public static func success(
        id: String,
        protocol: ProtocolVersion,
        result: JSONValue
    ) -> ResponseEnvelope {
        ResponseEnvelope(
            kind: "response",
            protocol: `protocol`.description,
            id: id,
            ok: true,
            result: result,
            error: nil
        )
    }

    public static func failure(
        id: String,
        protocol: ProtocolVersion,
        error: ProtocolFailure
    ) -> ResponseEnvelope {
        ResponseEnvelope(
            kind: "response",
            protocol: `protocol`.description,
            id: id,
            ok: false,
            result: nil,
            error: error
        )
    }
}
