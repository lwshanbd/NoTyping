import AppKit
import SwiftUI

@MainActor
final class ResultPanelController: ObservableObject {
    @Published var text: String = ""
    @Published var timestamp: Date = Date()
    @Published var isVisible: Bool = false
    @Published var isCopied: Bool = false

    private var panel: NSPanel?
    private var copyResetTask: Task<Void, Never>?

    func show(text: String) {
        self.text = text
        self.timestamp = Date()
        self.isCopied = false
        self.isVisible = true

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

    func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        isCopied = true
        copyResetTask?.cancel()
        copyResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.isCopied = false
        }
    }

    func dismiss() {
        copyResetTask?.cancel()
        copyResetTask = nil

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

    private func createPanel() {
        let resultView = ResultPanelView().environmentObject(self)
        let hostingView = NSHostingView(rootView: resultView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 200),
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
        effectView.material = .popover
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 10
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

        // Calculate content height based on text
        let textHeight = min(CGFloat(text.count / 20 + 1) * 20, 300)
        let totalHeight = min(textHeight + 100, 400) // header + footer + padding
        let width: CGFloat = 280
        let x = visibleFrame.midX - width / 2
        let y = visibleFrame.midY + 40 // slightly above center
        panel.setFrame(NSRect(x: x, y: y, width: width, height: totalHeight), display: true)
    }
}
