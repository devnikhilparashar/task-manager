import ApplicationServices
import CoreGraphics
import Foundation

public enum PermissionStatus: String, Codable, Equatable, Sendable {
    case granted
    case denied
}

public struct PermissionSnapshot: Codable, Equatable, Sendable {
    public let accessibility: PermissionStatus
    public let screenRecording: PermissionStatus

    public init(accessibility: PermissionStatus, screenRecording: PermissionStatus) {
        self.accessibility = accessibility
        self.screenRecording = screenRecording
    }
}

public protocol PermissionStateProviding {
    func currentPermissionState() -> PermissionSnapshot
}

public struct SystemPermissionStateProvider: PermissionStateProviding {
    public init() {}

    public func currentPermissionState() -> PermissionSnapshot {
        PermissionSnapshot(
            accessibility: AXIsProcessTrusted() ? .granted : .denied,
            screenRecording: CGPreflightScreenCaptureAccess() ? .granted : .denied
        )
    }
}
