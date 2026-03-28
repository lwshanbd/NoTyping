import AppKit
import ApplicationServices
import AVFoundation
import AVFAudio
import Foundation

@MainActor
final class PermissionManager: ObservableObject {
    enum Status: String { case granted, denied, undetermined }

    @Published var microphoneStatus: Status = .undetermined
    @Published var accessibilityStatus: Status = .undetermined

    func refresh() {
        // Microphone: check both AVCaptureDevice and AVAudioApplication
        let captureStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let recordPermission = AVAudioApplication.shared.recordPermission

        if captureStatus == .authorized || recordPermission == .granted {
            microphoneStatus = .granted
        } else if captureStatus == .denied || captureStatus == .restricted || recordPermission == .denied {
            microphoneStatus = .denied
        } else {
            microphoneStatus = .undetermined
        }

        // Accessibility
        let trusted = AXIsProcessTrusted()
        accessibilityStatus = trusted ? .granted : .denied
    }

    func requestMicrophonePermission() async {
        refresh()
        guard microphoneStatus == .undetermined else { return }

        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { result in
                continuation.resume(returning: result)
            }
        }
        _ = granted
        refresh()
    }

    func requestAccessibilityPermission() {
        if AXIsProcessTrusted() {
            refresh()
            return
        }
        // Open System Settings to the Accessibility privacy pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refresh()
    }
}
