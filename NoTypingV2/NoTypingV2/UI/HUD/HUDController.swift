import AppKit
import SwiftUI

@MainActor
final class HUDController: ObservableObject {
    @Published var stateText: String = ""
    @Published var detailText: String = ""
    @Published var volumeLevel: Float = 0
    @Published var isVisible: Bool = false
    @Published var isError: Bool = false

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(state: String, detail: String = "", isError: Bool = false) {
        hideTask?.cancel()
        hideTask = nil

        stateText = state
        detailText = detail
        self.isError = isError
        isVisible = true

        if panel == nil {
            createPanel()
        }
        positionPanel()
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel?.animator().alphaValue = 1
        }
    }

    func hide(after delay: TimeInterval = 0) {
        hideTask?.cancel()
        if delay > 0 {
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.dismiss()
            }
        } else {
            dismiss()
        }
    }

    func dismiss() {
        hideTask?.cancel()
        hideTask = nil

        guard let panel else {
            isVisible = false
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.isVisible = false
        })
    }

    func updateVolume(_ level: Float) {
        volumeLevel = level
    }

    private func createPanel() {
        let hudView = HUDView().environmentObject(self)
        let hostingView = NSHostingView(rootView: hudView)
        hostingView.setFrameSize(NSSize(width: 300, height: 40))

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let effectView = NSVisualEffectView(frame: panel.contentView!.bounds)
        effectView.material = .dark
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 12
        effectView.layer?.masksToBounds = true
        effectView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(effectView)

        hostingView.frame = panel.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hostingView)

        self.panel = panel
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame

        // Auto-size: let the hosting view determine intrinsic width
        if let hostingView = panel.contentView?.subviews.last as? NSView {
            let fittingSize = hostingView.fittingSize
            let width = min(max(fittingSize.width, 200), 400)
            let height: CGFloat = 40
            let x = visibleFrame.midX - width / 2
            let y = visibleFrame.minY + 80
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }
    }
}
