import Foundation

public struct RouterOutcome: Equatable, Sendable {
    public let response: ResponseEnvelope
    public let shouldTerminate: Bool

    public init(response: ResponseEnvelope, shouldTerminate: Bool = false) {
        self.response = response
        self.shouldTerminate = shouldTerminate
    }
}

public final class ProtocolRouter {
    public static let currentVersion = ProtocolVersion(major: 1, minor: 0)

    public static let implementedMethods = [
        "hello",
        "getCapabilities",
        "getPermissionState",
        "shutdown"
    ]

    public static let protocolMethods = [
        "hello",
        "getCapabilities",
        "getPermissionState",
        "requestAccessibilityPermission",
        "requestScreenRecordingPermission",
        "getActiveWindow",
        "getAccessibilitySnapshot",
        "captureAndRecognizeActiveWindow",
        "startAccessibilityEvents",
        "stopAccessibilityEvents",
        "cancel",
        "shutdown"
    ]

    private enum State {
        case awaitingHello
        case ready(ProtocolVersion)
        case stopped
    }

    private var state: State = .awaitingHello
    private let permissionProvider: PermissionStateProviding

    public init(permissionProvider: PermissionStateProviding = SystemPermissionStateProvider()) {
        self.permissionProvider = permissionProvider
    }

    public var responseProtocol: ProtocolVersion {
        if case let .ready(version) = state {
            return version
        }
        return Self.currentVersion
    }

    public func handle(_ request: RequestEnvelope) -> RouterOutcome {
        switch state {
        case .awaitingHello:
            return handleInitialRequest(request)
        case let .ready(negotiatedVersion):
            return handleReadyRequest(request, negotiatedVersion: negotiatedVersion)
        case .stopped:
            return failure(
                request,
                code: .invalidRequest,
                message: "Helper is shutting down",
                shouldTerminate: true
            )
        }
    }

    private func handleInitialRequest(_ request: RequestEnvelope) -> RouterOutcome {
        guard request.method == "hello" else {
            return failure(
                request,
                code: .invalidRequest,
                message: "The first request must be hello",
                details: .object(["requiredMethod": .string("hello")])
            )
        }
        guard let requestedVersion = ProtocolVersion(request.protocol) else {
            state = .stopped
            return unsupportedProtocol(request, shouldTerminate: true)
        }
        guard requestedVersion.major == Self.currentVersion.major else {
            state = .stopped
            return unsupportedProtocol(request, shouldTerminate: true)
        }
        if let validationError = validateHelloParams(request.params) {
            return RouterOutcome(response: .failure(
                id: request.id,
                protocol: Self.currentVersion,
                error: validationError
            ))
        }

        let negotiatedVersion = ProtocolVersion(
            major: Self.currentVersion.major,
            minor: min(requestedVersion.minor, Self.currentVersion.minor)
        )
        state = .ready(negotiatedVersion)

        var result = capabilities(negotiatedVersion: negotiatedVersion).objectValue ?? [:]
        result["negotiatedProtocol"] = .string(negotiatedVersion.description)
        return RouterOutcome(response: .success(
            id: request.id,
            protocol: negotiatedVersion,
            result: .object(result)
        ))
    }

    private func handleReadyRequest(
        _ request: RequestEnvelope,
        negotiatedVersion: ProtocolVersion
    ) -> RouterOutcome {
        guard request.protocol == negotiatedVersion.description else {
            return unsupportedProtocol(request)
        }

        switch request.method {
        case "hello":
            return failure(
                request,
                code: .invalidRequest,
                message: "hello may only be sent once"
            )

        case "getCapabilities":
            guard let error = validateEmptyParams(request.params, method: request.method) else {
                return RouterOutcome(response: .success(
                    id: request.id,
                    protocol: negotiatedVersion,
                    result: capabilities(negotiatedVersion: negotiatedVersion)
                ))
            }
            return RouterOutcome(response: .failure(
                id: request.id,
                protocol: negotiatedVersion,
                error: error
            ))

        case "getPermissionState":
            guard let error = validateEmptyParams(request.params, method: request.method) else {
                let permissions = permissionProvider.currentPermissionState()
                return RouterOutcome(response: .success(
                    id: request.id,
                    protocol: negotiatedVersion,
                    result: .object([
                        "accessibility": .string(permissions.accessibility.rawValue),
                        "screenRecording": .string(permissions.screenRecording.rawValue)
                    ])
                ))
            }
            return RouterOutcome(response: .failure(
                id: request.id,
                protocol: negotiatedVersion,
                error: error
            ))

        case "shutdown":
            guard let error = validateEmptyParams(request.params, method: request.method) else {
                state = .stopped
                return RouterOutcome(
                    response: .success(
                        id: request.id,
                        protocol: negotiatedVersion,
                        result: .object(["shuttingDown": .bool(true)])
                    ),
                    shouldTerminate: true
                )
            }
            return RouterOutcome(response: .failure(
                id: request.id,
                protocol: negotiatedVersion,
                error: error
            ))

        default:
            return failure(
                request,
                code: .unsupportedMethod,
                message: "Method is not implemented by this helper version",
                details: .object([
                    "knownProtocolMethod": .bool(Self.protocolMethods.contains(request.method))
                ])
            )
        }
    }

    private func capabilities(negotiatedVersion: ProtocolVersion) -> JSONValue {
        .object([
            "helper": .object([
                "name": .string("ambiant-memory-macos-helper"),
                "version": .string("0.1.0")
            ]),
            "protocol": .object([
                "negotiated": .string(negotiatedVersion.description),
                "supported": .array([.string(Self.currentVersion.description)])
            ]),
            "methods": .array(Self.implementedMethods.map(JSONValue.string)),
            "permissionKinds": .array([
                .string("accessibility"),
                .string("screenRecording")
            ]),
            "features": .array([]),
            "limits": .object([
                "maximumLineBytes": .integer(Int64(ProtocolLimits.maximumLineBytes))
            ])
        ])
    }

    private func validateHelloParams(_ params: JSONValue?) -> ProtocolFailure? {
        guard let params else { return nil }
        guard case let .object(object) = params else {
            return ProtocolFailure(code: .invalidArgument, message: "hello params must be an object")
        }
        let allowedKeys: Set<String> = ["clientName", "clientVersion", "requestedFeatures"]
        guard Set(object.keys).isSubset(of: allowedKeys) else {
            return ProtocolFailure(code: .invalidArgument, message: "hello params contain unknown fields")
        }
        if let clientName = object["clientName"], !isBoundedString(clientName, maximumBytes: 128) {
            return ProtocolFailure(code: .invalidArgument, message: "clientName must be a non-empty string of at most 128 bytes")
        }
        if let clientVersion = object["clientVersion"], !isBoundedString(clientVersion, maximumBytes: 64) {
            return ProtocolFailure(code: .invalidArgument, message: "clientVersion must be a non-empty string of at most 64 bytes")
        }
        if let features = object["requestedFeatures"] {
            guard case let .array(values) = features, values.count <= 64,
                  values.allSatisfy({ isBoundedString($0, maximumBytes: 64) }) else {
                return ProtocolFailure(code: .invalidArgument, message: "requestedFeatures must contain at most 64 bounded strings")
            }
        }
        return nil
    }

    private func validateEmptyParams(_ params: JSONValue?, method: String) -> ProtocolFailure? {
        guard let params else { return nil }
        guard case let .object(object) = params, object.isEmpty else {
            return ProtocolFailure(
                code: .invalidArgument,
                message: "\(method) does not accept parameters"
            )
        }
        return nil
    }

    private func isBoundedString(_ value: JSONValue, maximumBytes: Int) -> Bool {
        guard case let .string(string) = value else { return false }
        return !string.isEmpty && string.utf8.count <= maximumBytes
    }

    private func unsupportedProtocol(
        _ request: RequestEnvelope,
        shouldTerminate: Bool = false
    ) -> RouterOutcome {
        failure(
            request,
            code: .unsupportedProtocol,
            message: "Requested protocol version is not supported",
            details: .object([
                "requested": .string(request.protocol),
                "supported": .array([.string(Self.currentVersion.description)])
            ]),
            shouldTerminate: shouldTerminate
        )
    }

    private func failure(
        _ request: RequestEnvelope,
        code: ProtocolErrorCode,
        message: String,
        details: JSONValue? = nil,
        shouldTerminate: Bool = false
    ) -> RouterOutcome {
        RouterOutcome(
            response: .failure(
                id: request.id,
                protocol: responseProtocol,
                error: ProtocolFailure(
                    code: code,
                    message: message,
                    retryable: false,
                    details: details
                )
            ),
            shouldTerminate: shouldTerminate
        )
    }
}
