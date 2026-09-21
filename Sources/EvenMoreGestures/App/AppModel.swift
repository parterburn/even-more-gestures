import SwiftUI
import AppKit
import Combine
import ServiceManagement
import GestureKit
import GestureCore
import AppLogic
import TouchBridge

struct InstalledApp: Identifiable {
    let id: String
    let name: String
    let url: URL
    let isCustom: Bool
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}
@MainActor final class AppModel: ObservableObject {
    let store = PresetStore()
    let input = TouchInputController()
    let executor = ActionExecutor()
    @Published var settingsVisible = false
    @Published var permission = AXIsProcessTrusted()
    @Published var conflicts: [String] = []
    @Published var apps: [InstalledApp] = []
    @Published var paused = false
    @Published var pauseRemaining: TimeInterval?
    @Published var lastApp: NSRunningApplication?
    @Published var lastEvent = "Ready when you are"
    @Published var showOnboarding: Bool
    @Published var practice = false
    @Published var practiceTabs = ["Start page", "Inspiration", "A little more"]
    @Published var practiceIndex = 0
    @Published var practiceClosed: String?
    @Published var issue: String?
    @Published var preview: PreviewGesture = .rotate
    @Published var rotateEnabled: Bool { didSet { save(rotateEnabled, "rotate"); input.resetGestureSessions() } }
    @Published var pinchEnabled: Bool { didSet { save(pinchEnabled, "pinch"); input.resetGestureSessions() } }
    @Published var leftEnabled: Bool { didSet { save(leftEnabled, "left"); input.resetGestureSessions() } }
    @Published var rightEnabled: Bool { didSet { save(rightEnabled, "right"); input.resetGestureSessions() } }
    @Published var undoEnabled: Bool { didSet { save(undoEnabled, "undo"); undo.clear() } }
    @Published var pinchFingerCount: Int { didSet { UserDefaults.standard.set(pinchFingerCount, forKey: "pinchFingers"); input.setPinchFingers(pinchFingerCount) } }
    @Published var haptics: Bool { didSet { save(haptics, "haptics") } }
    @Published var invert: Bool { didSet { save(invert, "invert"); input.resetGestureSessions() } }
    @Published var showHUD: Bool { didSet { save(showHUD, "hud") } }
    @Published var showMenuIcon: Bool { didSet { save(showMenuIcon, "menuIcon"); onMenuVisibility?(showMenuIcon) } }
    @Published var rotationStep: Double { didSet { UserDefaults.standard.set(rotationStep, forKey: "rotationStep"); input.setRotationStep(rotationStep) } }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    var onMenuVisibility: ((Bool) -> Void)?
    var onStatusChange: (() -> Void)?
    var onHUD: ((String) -> Void)?
    var onCheckForUpdates: (() -> Void)?
    private var undo = UndoWindow()
    private var pause = PauseState()
    private var pauseTimer: DispatchWorkItem?
    private var observations: [NSObjectProtocol] = []
    private var subscriptions = Set<AnyCancellable>()
    private var sidebar: (action: GestureAction, plan: ActionPlan, pid: pid_t, time: Date)?
    private var practiceUndo = UndoWindow()
    private var routeGeneration = 0
    private var lastSpaceChange = Date.distantPast
    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["rotate":true,"pinch":true,"left":true,"right":true,"undo":true,"haptics":true,"hud":true,"menuIcon":true,"rotationStep":30.0,"pinchFingers":3])
        rotateEnabled = defaults.bool(forKey: "rotate"); pinchEnabled = defaults.bool(forKey: "pinch")
        leftEnabled = defaults.bool(forKey: "left"); rightEnabled = defaults.bool(forKey: "right")
        undoEnabled = defaults.bool(forKey: "undo"); haptics = defaults.bool(forKey: "haptics")
        pinchFingerCount = defaults.integer(forKey: "pinchFingers") == 2 ? 2 : 3
        invert = defaults.bool(forKey: "invert"); showHUD = defaults.bool(forKey: "hud")
        showMenuIcon = defaults.bool(forKey: "menuIcon"); rotationStep = defaults.double(forKey: "rotationStep")
        showOnboarding = !defaults.bool(forKey: "onboarded")
        lastApp = NSWorkspace.shared.frontmostApplication
        input.onGesture = { [weak self] event in self?.handle(event) }
        input.setRotationStep(rotationStep)
        input.setPinchFingers(pinchFingerCount)
        store.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            self.objectWillChange.send(); self.routeGeneration += 1; self.input.resetGestureSessions(); self.executor.invalidate()
        }.store(in: &subscriptions)
        input.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        let center = NSWorkspace.shared.notificationCenter
        observations.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self.routeGeneration += 1; self.input.resetGestureSessions()
                if app.processIdentifier != ProcessInfo.processInfo.processIdentifier { self.lastApp = app }
            }
        })
        observations.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.revertSidebarIfNeeded() }
        })
        observations.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.executor.invalidate() } })
        refresh()
        // System Settings can grant Accessibility while this app is inactive. Keep
        // checking until it is available instead of relying on the settings window
        // to remain alive or become active again.
        Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.permission else { return }
                self.refreshPermission()
            }
        }.store(in: &subscriptions)
        Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.refreshPauseCountdown()
        }.store(in: &subscriptions)
        Task { await store.refreshDefaultsIfNeeded() }
        Timer.publish(every: 3600, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            Task { @MainActor in await self?.store.refreshDefaultsIfNeeded() }
        }.store(in: &subscriptions)
    }
    private func save(_ value: Bool, _ key: String) { UserDefaults.standard.set(value, forKey: key) }
    func refreshPermission() {
        let current = AXIsProcessTrusted()
        guard current != permission else {
            if current && !input.isRunning { input.start() }
            return
        }
        permission = current
        current ? input.start() : input.stop()
        onStatusChange?()
    }
    func refresh() {
        refreshPermission()
        if permission && !input.isRunning { input.start() }
        reloadApps(); detectConflicts()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func checkForUpdates() { onCheckForUpdates?() }
    func openInputMonitoring() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!) }
    func setLogin(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { issue = "Allow Even More Gestures in System Settings → General → Login Items." }
        } catch { issue = "Could not change launch at login: \(error.localizedDescription)" }
    }
    func reloadApps() {
        var found: [InstalledApp] = []
        let names = Dictionary(uniqueKeysWithValues: store.presets.map { ($0.id, $0.name) })
        for bundle in Set(names.keys).union(store.overrides.keys) {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { continue }
            found.append(InstalledApp(id: bundle, name: names[bundle] ?? store.overrides[bundle]?.name ?? url.deletingPathExtension().lastPathComponent, url: url, isCustom: names[bundle] == nil))
        }
        apps = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    func addApp() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.prompt = "Add App"
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        store.addApp(bundleIdentifier: id, name: url.deletingPathExtension().lastPathComponent); reloadApps()
    }
    func detectConflicts() {
        let running = NSWorkspace.shared.runningApplications
        conflicts = running.compactMap { app in
            guard let name = app.localizedName, ["BetterTouchTool", "TouchBridge", "Multitouch"].contains(name) else { return nil }
            return "\(name) is running. Overlapping gestures may fire twice."
        }
        for domain in ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"] {
            if (CFPreferencesCopyAppValue("TrackpadThreeFingerDrag" as CFString, domain as CFString) as? Bool) == true {
                conflicts.append("Three-finger drag is enabled. Pinching may also start a drag."); break
            }
        }
    }
    func togglePause() { pause.toggle(); updatePause() }
    func pauseForHour() {
        pause.pauseForHour(); updatePause()
        let item = DispatchWorkItem { [weak self] in self?.pause.resume(); self?.updatePause() }
        pauseTimer = item; DispatchQueue.main.asyncAfter(deadline: .now()+3600, execute: item)
    }
    private func updatePause() {
        pauseTimer?.cancel(); pauseTimer = nil; paused = pause.isPaused()
        pauseRemaining = pause.remainingTime()
        routeGeneration += 1; undo.clear(); sidebar = nil; input.resetGestureSessions(); onStatusChange?()
    }
    private func refreshPauseCountdown() {
        guard paused else { return }
        if pause.isPaused() { pauseRemaining = pause.remainingTime() }
        else { pause.resume(); updatePause() }
    }
    func finishOnboarding() { showOnboarding = false; practice = false; UserDefaults.standard.set(true, forKey: "onboarded") }
    func handle(_ event: GestureEvent) {
        if practice && NSApp.isActive { practiceEvent(event); return }
        guard !pause.isPaused(), permission, !NSApp.isActive,
              let app = NSWorkspace.shared.frontmostApplication, let bundle = app.bundleIdentifier,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier, store.isEnabled(bundleIdentifier: bundle) else { return }
        let pid = app.processIdentifier
        let action: GestureAction
        switch event {
        case .rotateClockwise: guard rotateEnabled else { return }; action = .nextTab
        case .rotateCounterclockwise: guard rotateEnabled else { return }; action = .previousTab
        case .pinchIn: guard pinchEnabled else { return }; action = .closeTab
        case .pinchOut:
            guard pinchEnabled else { return }
            action = undoEnabled && undo.shouldReopen(pid: pid) ? .reopenClosedTab : .newTab
        case .swipeLeft:
            guard leftEnabled else { return }; action = invert ? .toggleRightSidebar : .toggleLeftSidebar
        case .swipeRight:
            guard rightEnabled else { return }; action = invert ? .toggleLeftSidebar : .toggleRightSidebar
        }
        guard let plan = store.plan(action: action, bundleIdentifier: bundle) else { return }
        let generation = routeGeneration
        let inputGeneration = EMGGeneration()
        let firedAt = Date()
        executor.execute(plan: plan, action: action, pid: pid, isValid: { EMGGeneration() == inputGeneration }) { [weak self] success in
            guard let self, success else { return }
            if action == .toggleLeftSidebar || action == .toggleRightSidebar {
                if self.lastSpaceChange >= firedAt && self.lastSpaceChange.timeIntervalSince(firedAt) <= 0.6 {
                    self.executor.execute(plan: plan, action: action, pid: pid, allowBackground: true) { _ in }
                } else { self.sidebar = (action, plan, pid, firedAt) }
            }
            guard self.routeGeneration == generation else { return }
            self.lastEvent = "\(action.title) · \(app.localizedName ?? bundle)"
            if self.haptics { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            if action == .closeTab {
                let reopen = self.undoEnabled && self.store.plan(action: .reopenClosedTab, bundleIdentifier: bundle) != nil
                self.undo.didClose(pid: pid, supportsReopen: reopen)
                if reopen && self.showHUD { self.onHUD?("Tab closed · spread to undo") }
            } else if action == .newTab || action == .reopenClosedTab { self.undo.clear() }

        }
    }
    func isGestureEnabled(_ action: GestureAction) -> Bool {
        switch action {
        case .nextTab, .previousTab:
            return rotateEnabled
        case .closeTab, .newTab:
            return pinchEnabled
        case .reopenClosedTab:
            return pinchEnabled && undoEnabled
        case .toggleLeftSidebar:
            return invert ? rightEnabled : leftEnabled
        case .toggleRightSidebar:
            return invert ? leftEnabled : rightEnabled
        }
    }
    private func revertSidebarIfNeeded() {
        lastSpaceChange = Date()
        guard let pending = sidebar else { return }; sidebar = nil
        guard Date().timeIntervalSince(pending.time) <= 0.6 else { return }
        executor.execute(plan: pending.plan, action: pending.action, pid: pending.pid, allowBackground: true) { _ in }
    }
    func practiceEvent(_ event: GestureEvent) {
        switch event {
        case .rotateClockwise: practiceIndex = (practiceIndex+1) % max(1,practiceTabs.count)
        case .rotateCounterclockwise: practiceIndex = (practiceIndex+max(1,practiceTabs.count)-1) % max(1,practiceTabs.count)
        case .pinchIn:
            guard !practiceTabs.isEmpty else { return }
            practiceClosed = practiceTabs.remove(at: min(practiceIndex,practiceTabs.count-1)); practiceIndex = max(0,min(practiceIndex,practiceTabs.count-1))
            practiceUndo.didClose(pid: 0, supportsReopen: true)
        case .pinchOut:
            if practiceUndo.shouldReopen(pid: 0), let closed = practiceClosed { practiceTabs.append(closed) }
            else { practiceTabs.append("New tab") }
            practiceIndex = practiceTabs.count-1; practiceClosed = nil; practiceUndo.clear()
        default: break
        }
        lastEvent = "Recognized: \(event.rawValue)"
    }
}
