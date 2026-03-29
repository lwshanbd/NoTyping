import ApplicationServices
import AVFoundation
import Carbon
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var permissionManager: PermissionManager

    @State private var audioDevices: [AudioDeviceInfo] = []
    @State private var selectedDeviceUID: String = ""
    @State private var launchAtLogin: Bool = LaunchAtLoginManager.isEnabled

    var body: some View {
        Form {
            Section("Permissions") {
                HStack {
                    Text("Accessibility")
                    Spacer()
                    if permissionManager.accessibilityStatus == .granted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access") {
                            permissionManager.requestAccessibilityPermission()
                        }
                        .foregroundStyle(.red)
                    }
                }
                if permissionManager.accessibilityStatus != .granted {
                    Text("NoTyping needs accessibility permission to type text into other apps. Without it, text can only be copied to clipboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Microphone")
                    Spacer()
                    if permissionManager.microphoneStatus == .granted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access") {
                            Task { await permissionManager.requestMicrophonePermission() }
                        }
                        .foregroundStyle(.red)
                    }
                }
            }

            Section("Hotkey") {
                HStack {
                    Text("Shortcut")
                    Spacer()
                    HotkeyRecorderView(hotkey: $settingsStore.settings.hotkey)
                        .frame(width: 140, height: 28)
                }

                Picker("Mode", selection: $settingsStore.settings.hotkeyMode) {
                    ForEach(HotkeyMode.allCases) { mode in
                        Text(mode.displayLabel).tag(mode)
                    }
                }
            }

            Section("Microphone") {
                Picker("Input Device", selection: $selectedDeviceUID) {
                    Text("System Default").tag("")
                    ForEach(audioDevices, id: \.uid) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
            }

            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        try? LaunchAtLoginManager.setEnabled(newValue)
                    }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshAudioDevices()
        }
        .onChange(of: settingsStore.settings) { _, _ in
            settingsStore.save()
        }
    }

    private func refreshAudioDevices() {
        audioDevices = AudioDeviceInfo.availableInputDevices()
    }
}

// MARK: - Audio device enumeration

private struct AudioDeviceInfo {
    let uid: String
    let name: String

    static func availableInputDevices() -> [AudioDeviceInfo] {
        var devices: [AudioDeviceInfo] = []
        var propSize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propSize) == noErr else {
            return devices
        }

        let count = Int(propSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propSize, &deviceIDs) == noErr else {
            return devices
        }

        for id in deviceIDs {
            // Check if device has input channels
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamPropSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &inputAddress, 0, nil, &streamPropSize) == noErr else { continue }

            let bufferListPointer = UnsafeMutableRawPointer.allocate(byteCount: Int(streamPropSize), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { bufferListPointer.deallocate() }
            guard AudioObjectGetPropertyData(id, &inputAddress, 0, nil, &streamPropSize, bufferListPointer) == noErr else { continue }

            let bufferList = bufferListPointer.assumingMemoryBound(to: AudioBufferList.self).pointee
            guard bufferList.mNumberBuffers > 0 else { continue }

            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameValue: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &nameValue) == noErr else { continue }

            // Get device UID
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uidValue: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            guard AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &uidSize, &uidValue) == noErr else { continue }

            devices.append(AudioDeviceInfo(uid: uidValue as String, name: nameValue as String))
        }
        return devices
    }
}

// MARK: - Hotkey Recorder (SwiftUI wrapper over NSView)

private struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var hotkey: HotkeyDescriptor

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.hotkey = hotkey
        view.onUpdate = { newHotkey in
            hotkey = newHotkey
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.hotkey = hotkey
    }
}

private final class HotkeyRecorderNSView: NSTextField {
    var onUpdate: ((HotkeyDescriptor) -> Void)?
    var hotkey: HotkeyDescriptor = .default {
        didSet {
            guard !isRecording else { return }
            updatePresentation()
        }
    }

    private var eventMonitor: Any?
    private var isRecording = false {
        didSet { updatePresentation() }
    }
    private var errorMessage: String? {
        didSet { updatePresentation() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
        isSelectable = false
        isBordered = true
        drawsBackground = true
        focusRingType = .default
        alignment = .center
        font = .systemFont(ofSize: 13, weight: .medium)
        lineBreakMode = .byTruncatingTail
        toolTip = "Click to record a new shortcut. Press Escape to cancel."
        updatePresentation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    deinit { stopMonitoring() }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        beginRecording()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            beginRecording()
            return
        }
        _ = handleRecordingEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        return handleRecordingEvent(event)
    }

    override func resignFirstResponder() -> Bool {
        finishRecording()
        return super.resignFirstResponder()
    }

    private func beginRecording() {
        errorMessage = nil
        isRecording = true
        startMonitoring()
    }

    private func finishRecording() {
        isRecording = false
        errorMessage = nil
        stopMonitoring()
    }

    @discardableResult
    private func handleRecordingEvent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }

        if event.keyCode == UInt16(kVK_Escape) {
            finishRecording()
            return true
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonMods: UInt32 = 0
        if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if modifiers.contains(.option) { carbonMods |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
        if modifiers.contains(.shift) { carbonMods |= UInt32(shiftKey) }

        let descriptor = HotkeyDescriptor(keyCode: UInt32(event.keyCode), carbonModifiers: carbonMods)

        guard descriptor.isValid else {
            errorMessage = "Must include a modifier key"
            NSSound.beep()
            return true
        }

        hotkey = descriptor
        onUpdate?(descriptor)
        finishRecording()
        return true
    }

    private func startMonitoring() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            return self.handleRecordingEvent(event) ? nil : event
        }
    }

    private func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func updatePresentation() {
        if isRecording {
            stringValue = errorMessage ?? "Type shortcut..."
            textColor = errorMessage == nil ? .secondaryLabelColor : .systemRed
            backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.12)
        } else {
            stringValue = hotkey.displayString
            textColor = .labelColor
            backgroundColor = .textBackgroundColor
        }
    }
}

// MARK: - HotkeyMode display label

extension HotkeyMode {
    var displayLabel: String {
        switch self {
        case .toggle: "Toggle"
        case .pushToTalk: "Push-to-Talk"
        }
    }
}
