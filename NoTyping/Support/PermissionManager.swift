import AppKit
import ApplicationServices
import AVFoundation
import AVFAudio
import Foundation

// Workaround for Swift 6 strict concurrency: access the C global outside strict checking
private func makeAccessibilityPromptOptions() -> CFDictionary {
    // kAXTrustedCheckOptionPrompt is a global C var; we access it in a non-isolated function
    let key = unsafeBitCast(
        dlsym(dlopen(nil, RTLD_LAZY), "kAXTrustedCheckOptionPrompt"),
        to: UnsafePointer<Unmanaged<CFString>>.self
    ).pointee.takeUnretainedValue()
    return [key: true] as CFDictionary
}

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
        // Trigger the system prompt to add this app to Accessibility
        let options = makeAccessibilityPromptOptions()
        _ = AXIsProcessTrustedWithOptions(options)
        // Also open System Settings as a backup (the system prompt sometimes doesn't appear for non-sandboxed apps)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refresh()
    }

    /// Trigger the system accessibility prompt without opening System Settings.
    func promptAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = makeAccessibilityPromptOptions()
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
