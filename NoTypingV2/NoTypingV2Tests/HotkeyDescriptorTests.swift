import Carbon
import XCTest
@testable import NoTypingV2

final class HotkeyDescriptorTests: XCTestCase {

    func testDefaultHotkeyIsValid() {
        let hotkey = HotkeyDescriptor.default
        XCTAssertTrue(hotkey.isValid, "Default hotkey must have at least one modifier")
        XCTAssertEqual(hotkey.keyCode, UInt32(kVK_ANSI_D))
        XCTAssertNotEqual(hotkey.carbonModifiers, 0)
    }

    func testHotkeyWithoutModifierIsInvalid() {
        let hotkey = HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_A), carbonModifiers: 0)
        XCTAssertFalse(hotkey.isValid, "A hotkey with no modifier should be invalid")
    }

    func testDisplayStringFormatsCorrectly() {
        // Default is Option+D => "⌥D"
        let defaultHotkey = HotkeyDescriptor.default
        XCTAssertEqual(defaultHotkey.displayString, "⌥D")

        // Cmd+Shift+F => "⇧⌘F"
        let combo = HotkeyDescriptor(
            keyCode: UInt32(kVK_ANSI_F),
            carbonModifiers: UInt32(shiftKey) | UInt32(cmdKey)
        )
        XCTAssertEqual(combo.displayString, "⇧⌘F")

        // Ctrl+Option+Shift+Cmd+Space => "⌃⌥⇧⌘Space"
        let allMods = HotkeyDescriptor(
            keyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey) | UInt32(cmdKey)
        )
        XCTAssertEqual(allMods.displayString, "⌃⌥⇧⌘Space")
    }
}
