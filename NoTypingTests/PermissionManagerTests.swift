import AVFAudio
import AVFoundation
import XCTest
@testable import NoTyping

@MainActor
final class PermissionManagerTests: XCTestCase {
    func testMicrophoneStatusPrefersGrantedRecordPermission() {
        let status = PermissionManager.resolveMicrophoneStatus(
            recordPermission: .granted,
            captureStatus: .notDetermined
        )

        XCTAssertEqual(status, .authorized)
    }

    func testMicrophoneStatusPrefersAuthorizedCaptureStatus() {
        let status = PermissionManager.resolveMicrophoneStatus(
            recordPermission: .undetermined,
            captureStatus: .authorized
        )

        XCTAssertEqual(status, .authorized)
    }

    func testMicrophoneStatusTreatsDeniedSourceAsDeniedWhenNeitherGranted() {
        let status = PermissionManager.resolveMicrophoneStatus(
            recordPermission: .denied,
            captureStatus: .notDetermined
        )

        XCTAssertEqual(status, .denied)
    }

    func testMicrophoneStatusFallsBackToNotDetermined() {
        let status = PermissionManager.resolveMicrophoneStatus(
            recordPermission: .undetermined,
            captureStatus: .notDetermined
        )

        XCTAssertEqual(status, .notDetermined)
    }
}
