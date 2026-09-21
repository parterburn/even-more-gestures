import AppKit
import ApplicationServices
import Carbon

public struct KeyShortcut: Equatable {
    public let key: String
    public let modifiers: CGEventFlags
    public static func parse(_ text: String) -> KeyShortcut? {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let key = parts.last, !key.isEmpty else { return nil }
        var flags: CGEventFlags = []
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "ctrl", "control": flags.insert(.maskControl)
            case "alt", "option": flags.insert(.maskAlternate)
            default: return nil
            }
        }
        guard key.count == 1 || ["tab", "left", "right", "up", "down", "return", "escape", "space", "delete"].contains(key) else { return nil }
        // A custom gesture must not type bare characters into a document.
        guard !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty else { return nil }
        return KeyShortcut(key: key, modifiers: flags)
    }
    public static func flagsFromAX(_ mask: Int) -> CGEventFlags {
        var flags: CGEventFlags = mask & 8 == 0 ? [.maskCommand] : []
        if mask & 1 != 0 { flags.insert(.maskShift) }
        if mask & 2 != 0 { flags.insert(.maskAlternate) }
        if mask & 4 != 0 { flags.insert(.maskControl) }
        return flags
    }
}

public enum KeyboardLayout {
    public static func resolve(_ key: String) -> (CGKeyCode, CGEventFlags)? {
        let special: [String: CGKeyCode] = ["tab":48,"left":123,"right":124,"up":126,"down":125,"return":36,"escape":53,"space":49,"delete":51]
        if let code = special[key] { return (code, []) }
        guard let input = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(input, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
        for (carbonFlags, eventFlags) in [(0, CGEventFlags()), (shiftKey, .maskShift), (optionKey, .maskAlternate), (shiftKey | optionKey, [.maskShift, .maskAlternate])] {
            for code in UInt16(0)..<128 {
                var dead: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 8)
                let result = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), UInt32(carbonFlags >> 8), UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 8, &length, &chars)
                if result == noErr, length > 0, String(utf16CodeUnits: chars, count: length).lowercased() == key.lowercased() { return (code, eventFlags) }
            }
        }
        return nil
    }
}

public final class ActionExecutor {
    private let queue = DispatchQueue(label: "app.evenmoregestures.accessibility", qos: .userInteractive)
    private var cache: [String: AXUIElement] = [:]
    public init() {}
    public func invalidate() { queue.async { self.cache.removeAll() } }
    public func execute(plan: ActionPlan, action: GestureAction, pid: pid_t, allowBackground: Bool = false, isValid: @escaping () -> Bool = { true }, completion: @escaping (Bool) -> Void) {
        queue.async {
            let validTarget = NSRunningApplication(processIdentifier: pid)?.isTerminated == false
            guard isValid(), validTarget, AXIsProcessTrusted(), allowBackground || NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                DispatchQueue.main.async { completion(false) }; return
            }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.25)
            let cacheKey = "\(pid):\(action.rawValue):\(plan.menuPaths)"
            var element = self.cache[cacheKey]
            if let existing = element, self.value(existing, kAXRoleAttribute) == nil { self.cache.removeValue(forKey: cacheKey); element = nil }
            if element == nil {
                for path in plan.menuPaths {
                    if let found = self.find(path, app: app) { element = found; self.cache[cacheKey] = found; break }
                }
            }
            // Recheck after AX discovery, which may have taken time.
            guard isValid(), allowBackground || NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                DispatchQueue.main.async { completion(false) }; return
            }
            var succeeded = false
            if let element {
                if (self.value(element, kAXEnabledAttribute) as? Bool) != false {
                    if let code = self.value(element, kAXMenuItemCmdVirtualKeyAttribute) as? Int,
                       let mask = self.value(element, kAXMenuItemCmdModifiersAttribute) as? Int,
                       let character = self.value(element, kAXMenuItemCmdCharAttribute) as? String,
                       !character.isEmpty, (0..<128).contains(code) {
                        succeeded = self.post(CGKeyCode(code), flags: KeyShortcut.flagsFromAX(mask), pid: pid)
                    } else {
                        succeeded = AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
                    }
                }
                if !succeeded { self.cache.removeValue(forKey: cacheKey) }
            } else if let shortcut = plan.shortcut.flatMap(KeyShortcut.parse), let (code, extra) = KeyboardLayout.resolve(shortcut.key) {
                succeeded = self.post(code, flags: shortcut.modifiers.union(extra), pid: pid)
            }
            DispatchQueue.main.async { completion(succeeded) }
        }
    }
    public func dumpMenu(pid: pid_t, completion: @escaping (String) -> Void) {
        queue.async {
            let app = AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(app, 0.25)
            guard let menu = self.value(app, kAXMenuBarAttribute) else { DispatchQueue.main.async { completion("Menu unavailable. Grant Accessibility and launch the app first.") }; return }
            var lines: [String] = []; var budget = 700
            self.dump(menu as! AXUIElement, path: [], depth: 0, budget: &budget, lines: &lines)
            let result = lines.joined(separator: "\n")
            DispatchQueue.main.async { completion(result) }
        }
    }
    private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }
    private func children(_ element: AXUIElement) -> [AXUIElement] { value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    private func find(_ path: [String], app: AXUIElement) -> AXUIElement? {
        guard let menu = value(app, kAXMenuBarAttribute), !path.isEmpty else { return nil }
        var current = menu as! AXUIElement
        for title in path {
            let direct = children(current)
            let candidates = direct + direct.filter { (value($0, kAXRoleAttribute) as? String) == kAXMenuRole }.flatMap(children)
            guard let item = candidates.first(where: { normalized(value($0, kAXTitleAttribute) as? String ?? "") == normalized(title) }) else { return nil }
            current = item
        }
        return current
    }
    private func normalized(_ text: String) -> String { text.replacingOccurrences(of: "…", with: "...").trimmingCharacters(in: .whitespaces) }
    private func post(_ code: CGKeyCode, flags: CGEventFlags, pid: pid_t) -> Bool {
        guard let source = CGEventSource(stateID: .privateState), let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true), let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return false }
        down.flags = flags; up.flags = flags
        down.postToPid(pid); up.postToPid(pid)
        return true
    }
    private func dump(_ element: AXUIElement, path: [String], depth: Int, budget: inout Int, lines: inout [String]) {
        guard depth < 8, budget > 0 else { return }; budget -= 1
        let title = value(element, kAXTitleAttribute) as? String ?? ""
        let next = title.isEmpty ? path : path + [title]
        if !title.isEmpty {
            let key = value(element, kAXMenuItemCmdCharAttribute) as? String ?? ""
            let modifiers = value(element, kAXMenuItemCmdModifiersAttribute) as? Int ?? 0
            lines.append(next.joined(separator: " › ") + (key.isEmpty ? "" : " [\(key), AX modifiers \(modifiers)]"))
        }
        for child in children(element) { dump(child, path: next, depth: depth+1, budget: &budget, lines: &lines) }
    }
}
