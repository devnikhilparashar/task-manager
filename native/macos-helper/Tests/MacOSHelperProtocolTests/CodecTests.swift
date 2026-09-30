import Foundation
import XCTest
@testable import MacOSHelperProtocol

final class CodecTests: XCTestCase {
    private let codec = ProtocolCodec()

    func testDecodesValidRequest() throws {
        let line = Data(#"{"kind":"request","protocol":"1.0","id":"r1","method":"hello","deadlineMs":1000,"params":{}}"#.utf8)
        let request = try codec.decodeRequest(line: line)

        XCTAssertEqual(request.id, "r1")
        XCTAssertEqual(request.method, "hello")
        XCTAssertEqual(request.params, .object([:]))
    }

    func testRejectsUnknownEnvelopeFields() {
        let line = Data(#"{"kind":"request","protocol":"1.0","id":"r1","method":"hello","extra":true}"#.utf8)

        assertFailure(try codec.decodeRequest(line: line), code: .invalidRequest)
    }

    func testRejectsNonObjectParams() {
        let line = Data(#"{"kind":"request","protocol":"1.0","id":"r1","method":"hello","params":[]}"#.utf8)

        assertFailure(try codec.decodeRequest(line: line), code: .invalidArgument)
    }

    func testRejectsMalformedUTF8() {
        let line = Data([0x7B, 0xFF, 0x7D])

        assertFailure(try codec.decodeRequest(line: line), code: .invalidRequest)
    }

    func testRejectsNonPositiveDeadline() {
        let line = Data(#"{"kind":"request","protocol":"1.0","id":"r1","method":"hello","deadlineMs":0}"#.utf8)

        assertFailure(try codec.decodeRequest(line: line), code: .invalidArgument)
    }

    func testResponseEncodingUsesStructuredErrorEnvelope() throws {
        let response = ResponseEnvelope.failure(
            id: "r1",
            protocol: ProtocolVersion(major: 1, minor: 0),
            error: ProtocolFailure(
                code: .axTimeout,
                message: "Accessibility traversal deadline exceeded",
                retryable: true,
                details: .object(["stage": .string("traversal")])
            )
        )

        let encoded = try codec.encode(response: response)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["kind"] as? String, "response")
        XCTAssertEqual(object["ok"] as? Bool, false)
        let error = try XCTUnwrap(object["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? String, "AX_TIMEOUT")
        XCTAssertEqual(error["retryable"] as? Bool, true)
    }

    private func assertFailure<T>(
        _ expression: @autoclosure () throws -> T,
        code: ProtocolErrorCode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual((error as? ProtocolFailure)?.code, code, file: file, line: line)
        }
    }
}
