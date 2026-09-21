import AppKit
import SwiftUI
import GestureCore
import Carbon
import Sparkle

@main
struct Main {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var model: AppModel!
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var hud: NSPanel?
    private var hudDismiss: DispatchWorkItem?
    private lazy var updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource:"AppIcon",withExtension:"icns"), let icon = NSImage(contentsOf:iconURL) { NSApp.applicationIconImage = icon }
        model = AppModel()
        _ = updaterController
        model.onMenuVisibility = { [weak self] shown in self?.setStatusVisible(shown) }
        model.onStatusChange = { [weak self] in self?.updateIcon() }
        model.onHUD = { [weak self] text in self?.showHUD(text) }
        model.onCheckForUpdates = { [weak self] in self?.updaterController.checkForUpdates(nil) }
        setStatusVisible(model.showMenuIcon)
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let settings = appMenu.addItem(withTitle:"Settings…",action:#selector(openSettings),keyEquivalent:","); settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle:"Quit Even More Gestures",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        appMenuItem.submenu = appMenu; mainMenu.addItem(appMenuItem); NSApp.mainMenu = mainMenu
        let launchedAtLogin = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword:keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !launchedAtLogin || model.showOnboarding || CommandLine.arguments.contains("--settings") { openSettings() }
    }
    func applicationWillTerminate(_ notification: Notification) { model.input.stop() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return true }
    private func setStatusVisible(_ visible: Bool) {
        if !visible { if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }; statusItem = nil; return }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        item.button?.target = self; item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on:[.leftMouseUp,.rightMouseUp])
        item.button?.toolTip = "Even More Gestures • Option-click to pause"
        statusItem = item; updateIcon()
    }
    private func updateIcon() {
        let image = NSImage(systemSymbolName: model.paused ? "hand.draw" : "hand.draw.fill", accessibilityDescription:"Even More Gestures")
        image?.isTemplate = true; statusItem?.button?.image = image
        statusItem?.button?.alphaValue = model.paused ? 0.5 : 1
    }
    @objc private func statusClicked() {
        if NSEvent.modifierFlags.contains(.option), model.permission { model.togglePause(); return }
        let menu = NSMenu(); menu.delegate = self
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
    }
    func menuWillOpen(_ menu: NSMenu) {
        model.refreshPermission(); menu.removeAllItems()
        if !model.permission {
            let setup = menu.addItem(withTitle:"Finish Accessibility setup…",action:#selector(openSettings),keyEquivalent:"")
            setup.target = self
            setup.image = NSImage(systemSymbolName:"hand.raised.fill",accessibilityDescription:"Finish Accessibility setup")
        } else {
            let title = model.paused ? "Gestures are paused" : "Even More Gestures is on"
            let toggle = menu.addItem(withTitle:title,action:#selector(togglePause),keyEquivalent:"")
            toggle.target = self; toggle.state = model.paused ? .off : .on
        }
        if let app = model.lastApp, let id = app.bundleIdentifier {
            let enabled = model.store.isEnabled(bundleIdentifier:id)
            let item = menu.addItem(withTitle:"\(enabled ? "Disable" : "Enable") for \(app.localizedName ?? id)",action:#selector(toggleCurrentApp),keyEquivalent:"")
            item.target = self; item.representedObject = id
            let icon = app.icon?.copy() as? NSImage; icon?.size = NSSize(width:16,height:16); item.image = icon
        }
        let pause = menu.addItem(withTitle:"Pause for 1 Hour",action:#selector(pauseHour),keyEquivalent:""); pause.target = self
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle:"Settings…",action:#selector(openSettings),keyEquivalent:","); settings.target = self
        let updates = menu.addItem(withTitle:"Check for Updates…",action:#selector(SPUStandardUpdaterController.checkForUpdates(_:)),keyEquivalent:"")
        updates.target = updaterController
        updates.isEnabled = updaterController.updater.canCheckForUpdates
        menu.addItem(.separator())
        menu.addItem(withTitle:"Quit Even More Gestures",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
    }
    func menuDidClose(_ menu: NSMenu) { statusItem?.menu = nil }
    @objc private func togglePause() { model.togglePause() }
    @objc private func pauseHour() { model.pauseForHour() }
    @objc private func toggleCurrentApp(_ sender: NSMenuItem) {
        guard let bundle = sender.representedObject as? String else { return }
        model.store.setEnabled(!model.store.isEnabled(bundleIdentifier:bundle),bundleIdentifier:bundle)
    }
    @objc func openSettings() {
        model.refresh()
        model.settingsVisible = true
        NSApp.setActivationPolicy(.accessory)
        if settingsWindow == nil {
            let controller = NSHostingController(rootView:SettingsView(model:model))
            let window = NSWindow(contentViewController:controller)
            window.title = "Even More Gestures"; window.styleMask = [.titled,.closable,.miniaturizable,.resizable]
            window.setContentSize(NSSize(width:760,height:760)); window.minSize = NSSize(width:720,height:710)
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false; window.delegate = self; window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps:true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        model.settingsVisible = false
        model.practice = false; settingsWindow?.contentViewController = nil; settingsWindow = nil
        NSApp.setActivationPolicy(.accessory)
    }
    func windowDidMiniaturize(_ notification: Notification) { model.settingsVisible = false }
    func windowDidDeminiaturize(_ notification: Notification) { model.settingsVisible = true }
    func applicationDidHide(_ notification: Notification) { model.settingsVisible = false }
    func applicationDidUnhide(_ notification: Notification) { model.settingsVisible = settingsWindow?.isVisible == true }
    private func showHUD(_ text: String) {
        hudDismiss?.cancel(); hud?.close()
        let panel = NSPanel(contentRect:NSRect(x:0,y:0,width:310,height:48),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.ignoresMouseEvents = true; panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: Text(text).font(.system(size:13,weight:.medium)).padding(.horizontal,20).frame(width:310,height:48).background(.regularMaterial,in:Capsule()))
        if let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x:screen.visibleFrame.midX-155,y:screen.visibleFrame.minY+65)) }
        panel.orderFrontRegardless(); hud = panel
        let item = DispatchWorkItem { [weak self] in self?.hud?.close(); self?.hud = nil }
        hudDismiss = item; DispatchQueue.main.asyncAfter(deadline:.now()+3,execute:item)
    }
}
