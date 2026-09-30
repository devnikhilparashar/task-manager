import XCTest
@testable import AmbiantMemory

final class CapturePolicyTests: XCTestCase {
    func testUsefulTextThreshold() {
        var policy = CapturePolicy()
        policy.minimumUsefulCharacters = 10
        XCTAssertFalse(policy.hasUsefulText(["OK"], quality: 1))
        XCTAssertFalse(policy.hasUsefulText(["A sufficiently long phrase"], quality: 0.1))
        XCTAssertTrue(policy.hasUsefulText(["A sufficiently long phrase"], quality: 0.8))
    }

    func testExclusionsAreCaseInsensitive() {
        let context = ActiveWindowContext(pid: 1, bundleID: "com.example.Secret", appName: "Secret", windowTitle: "PRIVATE Account", accessibilityWindow: nil)
        let policy = CapturePolicy()
        XCTAssertTrue(policy.isExcluded(context, rules: [ExclusionRule(id: 1, kind: .bundleID, value: "COM.EXAMPLE.SECRET")], ownBundleID: "journal"))
        XCTAssertTrue(policy.isExcluded(context, rules: [ExclusionRule(id: 2, kind: .windowTitle, value: "private")], ownBundleID: "journal"))
    }
}
