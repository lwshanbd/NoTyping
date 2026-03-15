import AVFAudio
import AVFoundation
import AppKit
import ApplicationServices
import Foundation

@MainActor
final class PermissionManager: ObservableObject {
    private enum DefaultsKey {
        static let hasPromptedForAccessibility = "permissions.hasPromptedForAccessibility"
    }

    enum PermissionStatus: String {
        case authorized
        case denied
        case notDetermined
    }

    @Published private(set) var microphoneStatus: PermissionStatus = .notDetermined
    @Published private(set) var accessibilityStatus: PermissionStatus = .notDetermined
    @Published private(set) var microphoneStatusDetail = "AVAudioApplication: undetermined · AVCaptureDevice: not determined"
    @Published private(set) var accessibilityStatusDetail = "AXIsProcessTrusted: not trusted"

    init() {
        refresh()
    }

    func refresh() {
        let applicationPermission = AVAudioApplication.shared.recordPermission
        let capturePermission = AVCaptureDevice.authorizationStatus(for: .audio)
        microphoneStatus = Self.resolveMicrophoneStatus(
            recordPermission: applicationPermission,
            captureStatus: capturePermission
        )
        microphoneStatusDetail = "AVAudioApplication: \(Self.describe(recordPermission: applicationPermission)) · AVCaptureDevice: \(Self.describe(captureStatus: capturePermission))"

        let isTrusted = AXIsProcessTrusted()
        accessibilityStatus = resolveAccessibilityStatus(isTrusted: isTrusted)
        accessibilityStatusDetail = "AXIsProcessTrusted: \(isTrusted ? "trusted" : "not trusted")"
    }

    func requestMicrophonePermission() async -> Bool {
        refresh()
        switch microphoneStatus {
        case .authorized:
            return true
        case .denied:
            openSystemSettings(for: .microphone)
            return false
        case .notDetermined:
            activateForPermissionPrompt()
        }

        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        refresh()
        if !granted, microphoneStatus == .denied {
            openSystemSettings(for: .microphone)
        }
        return granted || microphoneStatus == .authorized
    }

    func requestAccessibilityPermission(prompt: Bool = true) -> Bool {
        if AXIsProcessTrusted() {
            refresh()
            return true
        }

        if prompt {
            activateForPermissionPrompt()
            UserDefaults.standard.set(true, forKey: DefaultsKey.hasPromptedForAccessibility)
        }

        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        refresh()
        if prompt, !trusted {
            openSystemSettings(for: .accessibility)
        }
        return trusted
    }

    func openSystemSettings(for permission: PermissionKind) {
        let urlString: String
        switch permission {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    enum PermissionKind: String, CaseIterable {
        case microphone
        case accessibility
    }

    private func resolveAccessibilityStatus(isTrusted: Bool) -> PermissionStatus {
        if isTrusted {
            return .authorized
        }
        return UserDefaults.standard.bool(forKey: DefaultsKey.hasPromptedForAccessibility) ? .denied : .notDetermined
    }

    private func activateForPermissionPrompt() {
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    static func resolveMicrophoneStatus(
        recordPermission: AVAudioApplication.recordPermission,
        captureStatus: AVAuthorizationStatus
    ) -> PermissionStatus {
        if recordPermission == .granted || captureStatus == .authorized {
            return .authorized
        }

        if recordPermission == .denied || captureStatus == .denied || captureStatus == .restricted {
            return .denied
        }

        return .notDetermined
    }

    static func describe(recordPermission: AVAudioApplication.recordPermission) -> String {
        switch recordPermission {
        case .granted:
            "granted"
        case .denied:
            "denied"
        case .undetermined:
            "undetermined"
        @unknown default:
            "unknown"
        }
    }

    static func describe(captureStatus: AVAuthorizationStatus) -> String {
        switch captureStatus {
        case .authorized:
            "authorized"
        case .denied:
            "denied"
        case .restricted:
            "restricted"
        case .notDetermined:
            "not determined"
        @unknown default:
            "unknown"
        }
    }
}
