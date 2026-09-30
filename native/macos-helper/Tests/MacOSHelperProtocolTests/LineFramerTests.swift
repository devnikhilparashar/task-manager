import Foundation
import XCTest
@testable import MacOSHelperProtocol

final class LineFramerTests: XCTestCase {
    func testFramesAcrossChunks() {
        var framer = JSONLineFramer()

        XCTAssertEqual(framer.append(Data("{\"id\":".utf8)), [])
        XCTAssertEqual(
            framer.append(Data("1}\n{\"id\":2}\n".utf8)),
            [
                .line(Data("{\"id\":1}".utf8)),
                .line(Data("{\"id\":2}".utf8))
            ]
        )
    }

    func testAllowsLineAtExactLimit() {
        var framer = JSONLineFramer()
        var data = Data(repeating: 0x20, count: ProtocolLimits.maximumLineBytes)
        data.append(0x0A)

        let events = framer.append(data)

        XCTAssertEqual(events.count, 1)
        guard case let .line(line) = events[0] else {
            return XCTFail("Expected a framed line")
        }
        XCTAssertEqual(line.count, ProtocolLimits.maximumLineBytes)
    }

    func testOversizedLineEmitsOneFailureAndRecoversAtNewline() {
        var framer = JSONLineFramer()
        var oversized = Data(repeating: 0x61, count: ProtocolLimits.maximumLineBytes + 50)
        oversized.append(0x0A)
        oversized.append(Data("{}\n".utf8))

        let events = framer.append(oversized)

        XCTAssertEqual(events.count, 2)
        guard case let .failure(error) = events[0] else {
            return XCTFail("Expected a size failure")
        }
        XCTAssertEqual(error.code, .payloadTooLarge)
        XCTAssertEqual(events[1], .line(Data("{}".utf8)))
    }

    func testFinishReturnsFinalUnterminatedLine() {
        var framer = JSONLineFramer()
        _ = framer.append(Data("{}".utf8))

        XCTAssertEqual(framer.finish(), [.line(Data("{}".utf8))])
        XCTAssertEqual(framer.finish(), [])
    }
}
