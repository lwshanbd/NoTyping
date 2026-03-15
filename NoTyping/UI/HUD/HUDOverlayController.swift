import AppKit
import SwiftUI

@MainActor
final class HUDOverlayController: ObservableObject {
    @Published var stateText = "Idle"
    @Published var detailText = "Press the hotkey to start dictation."
    @Published var visible = false
    @Published var isDismissible = false

    private var panel: NSPanel?
    private var pendingHideTask: Task<Void, Never>?

    func show(state: String, detail: String, dismissible: Bool = false) {
        pendingHideTask?.cancel()
        pendingHideTask = nil
        stateText = state
        detailText = detail
        isDismissible = dismissible
        ensurePanel()
        panel?.ignoresMouseEvents = !dismissible
        positionPanel()
        visible = true
        panel?.orderFrontRegardless()
    }

    func dismiss() {
        hide()
    }

    func hide(after delay: Duration? = nil) {
        pendingHideTask?.cancel()
        pendingHideTask = nil
        guard let delay else {
            visible = false
            isDismissible = false
            panel?.orderOut(nil)
            return
        }
        pendingHideTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            self.visible = false
            self.isDismissible = false
            self.panel?.orderOut(nil)
            self.pendingHideTask = nil
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let host = NSHostingView(rootView: HUDView().environmentObject(self))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 140),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = !isDismissible
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = host
        self.panel = panel
    }

    private func positionPanel() {
        guard let panel else { return }
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        let frame = panel.frame
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = NSPoint(x: mouseLocation.x - (frame.width / 2), y: mouseLocation.y - frame.height - 32)
        origin.x = max(visibleFrame.minX + 20, min(origin.x, visibleFrame.maxX - frame.width - 20))
        origin.y = max(visibleFrame.minY + 20, min(origin.y, visibleFrame.maxY - frame.height - 20))
        panel.setFrameOrigin(origin)
    }
}
