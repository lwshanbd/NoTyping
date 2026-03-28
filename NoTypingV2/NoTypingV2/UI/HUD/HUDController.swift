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

    func show(state: String, detail: String = "", isError: Bool = false) { fatalError("TODO") }
    func hide(after delay: TimeInterval = 0) { fatalError("TODO") }
    func dismiss() { fatalError("TODO") }
    func updateVolume(_ level: Float) { fatalError("TODO") }
}
