import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show<Content: View>(rootView: Content) { fatalError("TODO") }
    func close() { window?.close() }
}
