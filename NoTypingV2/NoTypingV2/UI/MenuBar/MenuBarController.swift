import AppKit
import Foundation

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    var onSettingsClicked: (() -> Void)?
    var onQuitClicked: (() -> Void)?

    func setup() { fatalError("TODO") }
    func updateStatus(_ state: PipelineState) { fatalError("TODO") }
}
