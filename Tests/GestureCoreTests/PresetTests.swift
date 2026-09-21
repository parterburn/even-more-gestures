import XCTest
import CoreGraphics
@testable import GestureCore

final class PresetTests: XCTestCase {
    @MainActor func testSafeDefaultsAndExplicitOverrides() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("overrides.json")
        let store = PresetStore(file:file)
        XCTAssertEqual(store.presets.count,26)
        XCTAssertNil(store.error)
        for id in ["com.apple.Terminal","com.googlecode.iterm2","com.mitchellh.ghostty","dev.warp.Warp-Stable"] { XCTAssertNil(store.plan(action:.closeTab,bundleIdentifier:id)) }
        for id in ["com.apple.Preview","com.apple.Photos","com.apple.Maps"] { XCTAssertNil(store.plan(action:.nextTab,bundleIdentifier:id)) }
        XCTAssertNil(store.plan(action:.closeTab,bundleIdentifier:"unknown.app"))
        XCTAssertNil(store.plan(action:.reopenClosedTab,bundleIdentifier:"com.apple.finder"))
        XCTAssertNotNil(store.plan(action:.nextTab,bundleIdentifier:"unknown.app"))
        store.setOverride(.custom("cmd+w"),action:.closeTab,bundleIdentifier:"com.apple.Terminal")
        XCTAssertEqual(store.plan(action:.closeTab,bundleIdentifier:"com.apple.Terminal")?.shortcut,"cmd+w")
        store.setEnabled(false,bundleIdentifier:"com.apple.Terminal")
        XCTAssertNil(store.plan(action:.closeTab,bundleIdentifier:"com.apple.Terminal"))
        let reload = PresetStore(file:file)
        XCTAssertFalse(reload.isEnabled(bundleIdentifier:"com.apple.Terminal"))
        XCTAssertEqual(reload.overrideMode(action:.closeTab,bundleIdentifier:"com.apple.Terminal"),.custom("cmd+w"))
    }
    @MainActor func testOffAndInvalidShortcutDoNotFallBack() {
        let store = PresetStore(file:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        store.setOverride(.off,action:.nextTab,bundleIdentifier:"com.apple.Safari")
        XCTAssertNil(store.plan(action:.nextTab,bundleIdentifier:"com.apple.Safari"))
        store.setOverride(.custom("plain text"),action:.newTab,bundleIdentifier:"com.apple.Safari")
        XCTAssertNil(store.plan(action:.newTab,bundleIdentifier:"com.apple.Safari"))
    }
    @MainActor func testRemovingAnAppKeepsItsCustomSettingsForReadding() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("overrides.json")
        let store = PresetStore(file: file)
        store.setOverride(.custom("cmd+shift+k"), action: .closeTab, bundleIdentifier: "com.example.App")
        store.setEnabled(false, bundleIdentifier: "com.example.App")
        store.removeApp(bundleIdentifier: "com.example.App")
        XCTAssertTrue(store.isRemoved(bundleIdentifier: "com.example.App"))
        XCTAssertFalse(store.isEnabled(bundleIdentifier: "com.example.App"))
        XCTAssertEqual(store.overrideMode(action: .closeTab, bundleIdentifier: "com.example.App"), .custom("cmd+shift+k"))

        let reload = PresetStore(file: file)
        XCTAssertTrue(reload.isRemoved(bundleIdentifier: "com.example.App"))
        XCTAssertEqual(reload.overrideMode(action: .closeTab, bundleIdentifier: "com.example.App"), .custom("cmd+shift+k"))
        reload.addApp(bundleIdentifier: "com.example.App", name: "Example App")
        XCTAssertFalse(reload.isRemoved(bundleIdentifier: "com.example.App"))
        XCTAssertTrue(reload.isEnabled(bundleIdentifier: "com.example.App"))
        XCTAssertEqual(reload.overrideMode(action: .closeTab, bundleIdentifier: "com.example.App"), .custom("cmd+shift+k"))
    }
    @MainActor func testRequestedSidebarDefaults() {
        let store = PresetStore(file:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertEqual(store.plan(action:.toggleLeftSidebar,bundleIdentifier:"com.apple.Maps")?.shortcut,"cmd+ctrl+s")
        XCTAssertEqual(store.plan(action:.toggleLeftSidebar,bundleIdentifier:"com.google.Chrome")?.shortcut,"cmd+shift+l")
        for id in ["com.openai.chat","com.openai.codex"] {
            XCTAssertEqual(store.plan(action:.toggleLeftSidebar,bundleIdentifier:id)?.shortcut,"cmd+b")
            XCTAssertEqual(store.plan(action:.toggleRightSidebar,bundleIdentifier:id)?.shortcut,"cmd+alt+b")
        }
    }
    func testShortcutParserRejectsBareTypingAndInvalidModifiers() {
        XCTAssertNil(KeyShortcut.parse("t")); XCTAssertNil(KeyShortcut.parse("shift+t")); XCTAssertNil(KeyShortcut.parse("bad+t")); XCTAssertNil(KeyShortcut.parse("cmd+"))
        XCTAssertNotNil(KeyShortcut.parse("cmd+shift+]")); XCTAssertNotNil(KeyShortcut.parse("ctrl+tab"))
    }
    func testAXCommandIsImplicitUnlessNoCommandBitSet() {
        XCTAssertEqual(KeyShortcut.flagsFromAX(0),.maskCommand)
        XCTAssertEqual(KeyShortcut.flagsFromAX(1),[.maskCommand,.maskShift])
        XCTAssertEqual(KeyShortcut.flagsFromAX(12),.maskControl)
        XCTAssertEqual(KeyShortcut.flagsFromAX(8),[])
    }
    @MainActor func testEveryBundledFallbackParses() {
        let store = PresetStore(file:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        for preset in store.presets { for action in preset.actions.values { if let keys = action.shortcut { XCTAssertNotNil(KeyShortcut.parse(keys),"\(preset.name): \(keys)") } } }
    }
}
