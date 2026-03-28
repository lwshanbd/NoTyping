import AppKit
import SwiftUI

@MainActor
final class ResultPanelController: ObservableObject {
    @Published var text: String = ""
    @Published var timestamp: Date = Date()
    @Published var isVisible: Bool = false
    @Published var isCopied: Bool = false

    private var panel: NSPanel?

    func show(text: String) { fatalError("TODO") }
    func copyToClipboard() { fatalError("TODO") }
    func dismiss() { fatalError("TODO") }
}
