import XCTest
@testable import MacOSHelperProtocol

private struct StubPermissionProvider: PermissionStateProviding {
    let snapshot: PermissionSnapshot

    func currentPermissionState() -> PermissionSnapshot { snapshot }
}

final class RouterTests: XCTestCase {
    func testRequiresHelloAsFirstRequest() {
        let router = makeRouter()

        let outcome = router.handle(request(id: "1", method: "getCapabilities"))

        XCTAssertFalse(outcome.response.ok)
        XCTAssertEqual(outcome.response.error?.code, .invalidRequest)
        XCTAssertFalse(outcome.shouldTerminate)
    }

    func testNegotiatesHigherClientMinorDownToCurrentMinor() {
        let router = makeRouter()

        let outcome = router.handle(request(id: "1", protocol: "1.7", method: "hello"))

        XCTAssertTrue(outcome.response.ok)
        XCTAssertEqual(outcome.response.protocol, "1.0")
        XCTAssertEqual(outcome.response.result?.objectValue?["negotiatedProtocol"], .string("1.0"))
        XCTAssertFalse(outcome.shouldTerminate)
    }

    func testMajorMismatchReturnsErrorAndTerminates() {
        let router = makeRouter()

        let outcome = router.handle(request(id: "1", protocol: "2.0", method: "hello"))

        XCTAssertEqual(outcome.response.error?.code, .unsupportedProtocol)
        XCTAssertTrue(outcome.shouldTerminate)
    }

    func testCapabilitiesAreAvailableAfterHello() {
        let router = makeRouter()
        _ = router.handle(request(id: "1", method: "hello"))

        let outcome = router.handle(request(id: "2", method: "getCapabilities", params: .object([:])))

        XCTAssertTrue(outcome.response.ok)
        let methods = outcome.response.result?.objectValue?["methods"]
        XCTAssertEqual(methods, .array(ProtocolRouter.implementedMethods.map(JSONValue.string)))
    }

    func testPermissionStateUsesInjectedProvider() {
        let router = makeRouter(accessibility: .granted, screenRecording: .denied)
        _ = router.handle(request(id: "1", method: "hello"))

        let outcome = router.handle(request(id: "2", method: "getPermissionState"))

        XCTAssertEqual(outcome.response.result, .object([
            "accessibility": .string("granted"),
            "screenRecording": .string("denied")
        ]))
    }

    func testPermissionStateRejectsParameters() {
        let router = makeRouter()
        _ = router.handle(request(id: "1", method: "hello"))

        let outcome = router.handle(request(
            id: "2",
            method: "getPermissionState",
            params: .object(["kind": .string("accessibility")])
        ))

        XCTAssertEqual(outcome.response.error?.code, .invalidArgument)
    }

    func testUnimplementedAllowlistedMethodIsRejectedWithoutDispatch() {
        let router = makeRouter()
        _ = router.handle(request(id: "1", method: "hello"))

        let outcome = router.handle(request(id: "2", method: "getAccessibilitySnapshot"))

        XCTAssertEqual(outcome.response.error?.code, .unsupportedMethod)
        XCTAssertEqual(
            outcome.response.error?.details?.objectValue?["knownProtocolMethod"],
            .bool(true)
        )
    }

    func testArbitraryMethodIsRejectedWithoutDispatch() {
        let router = makeRouter()
        _ = router.handle(request(id: "1", method: "hello"))

        let outcome = router.handle(request(id: "2", method: "runShellCommand"))

        XCTAssertEqual(outcome.response.error?.code, .unsupportedMethod)
        XCTAssertEqual(
            outcome.response.error?.details?.objectValue?["knownProtocolMethod"],
            .bool(false)
        )
    }

    func testRequestsMustUseNegotiatedVersion() {
        let router = makeRouter()
        _ = router.handle(request(id: "1", protocol: "1.9", method: "hello"))

        let outcome = router.handle(request(id: "2", protocol: "1.9", method: "getCapabilities"))

        XCTAssertEqual(outcome.response.error?.code, .unsupportedProtocol)
        XCTAssertFalse(outcome.shouldTerminate)
    }

    func testShutdownAcknowledgesAndTerminates() {
        let router = makeRouter()
        _ = router.handle(request(id: "1", method: "hello"))

        let outcome = router.handle(request(id: "2", method: "shutdown", params: .object([:])))

        XCTAssertTrue(outcome.response.ok)
        XCTAssertEqual(outcome.response.result, .object(["shuttingDown": .bool(true)]))
        XCTAssertTrue(outcome.shouldTerminate)
    }

    func testHelloRejectsUnknownParameters() {
        let router = makeRouter()

        let outcome = router.handle(request(
            id: "1",
            method: "hello",
            params: .object(["unexpected": .bool(true)])
        ))

        XCTAssertEqual(outcome.response.error?.code, .invalidArgument)
    }

    private func makeRouter(
        accessibility: PermissionStatus = .denied,
        screenRecording: PermissionStatus = .denied
    ) -> ProtocolRouter {
        ProtocolRouter(permissionProvider: StubPermissionProvider(snapshot: PermissionSnapshot(
            accessibility: accessibility,
            screenRecording: screenRecording
        )))
    }

    private func request(
        id: String,
        protocol version: String = "1.0",
        method: String,
        params: JSONValue? = nil
    ) -> RequestEnvelope {
        RequestEnvelope(
            protocol: version,
            id: id,
            method: method,
            deadlineMs: 1_000,
            params: params
        )
    }
}
