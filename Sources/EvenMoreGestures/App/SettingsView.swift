import SwiftUI
import GestureCore
import GestureKit

struct SettingsView: View {
    private enum AppFilter: String, CaseIterable, Identifiable {
        case all = "All", presets = "Presets", custom = "Custom", overrides = "With Overrides"
        var id: String { rawValue }
    }
    @ObservedObject var model: AppModel
    @State private var tab = "Gestures"
    @State private var search = ""
    @State private var appFilter: AppFilter = .all
    @State private var expanded: String?
    @State private var editing: ShortcutSelection?
    @State private var isVisible = false
    @State private var showingAccessibilityHelp = false
    private let tabs = ["Gestures", "Apps", "General"]
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:13) {
                Image(nsImage:NSApp.applicationIconImage).resizable().interpolation(.high).frame(width:52,height:52)
                VStack(alignment:.leading,spacing:4) {
                    Text("Even More Gestures").font(.system(size:20,weight:.semibold))
                    Text("A little more at your fingertips.").font(.system(size:12)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.horizontal,28).padding(.top,25).padding(.bottom,20)
            if !model.permission { permissionBanner.padding(.horizontal,28).padding(.bottom,20) }
            Picker("Settings",selection:$tab) { ForEach(tabs,id:\.self) { Text($0) } }.pickerStyle(.segmented).labelsHidden().frame(width:306).padding(.bottom,20)
            Divider()
            if model.showOnboarding { OnboardingView(model:model) }
            else {
                ScrollView {
                    VStack(spacing:18) {
                        if let error = model.store.error { banner(error, icon:"exclamationmark.triangle", color:.orange) }
                        switch tab {
                        case "Apps": appsView
                        case "General": generalView
                        default: gesturesView
                        }
                    }.padding(26)
                }
                Divider()
                HStack {
                    Button(action: performFooterStatusAction) {
                        HStack(spacing:6) {
                            Image(systemName: footerStatus.symbol).font(.system(size:10,weight:.semibold))
                            Text(footerStatus.title).font(.system(size:10,weight:.medium)).monospacedDigit()
                        }.foregroundStyle(footerStatus.color)
                    }.buttonStyle(.plain).help(footerStatus.help)
                    Spacer()
                    Button(model.practice ? "End practice" : "Try the gestures") { model.practice.toggle() }.buttonStyle(.link).font(.system(size:11))
                }.padding(.horizontal,26).padding(.vertical,12)
                if model.practice { PracticeView(model:model).padding([.horizontal,.bottom],20) }
            }
        }.frame(minWidth:720,minHeight:690).background(Color(nsColor:.windowBackgroundColor))
        .onAppear { isVisible = true; model.refresh() }
        .onDisappear { isVisible = false; model.practice = false }
        .task(id:model.settingsVisible) {
            guard model.settingsVisible else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for:.seconds(1))
                guard !Task.isCancelled else { break }
                model.refreshPermission()
            }
        }
        .sheet(item:$editing) { selection in ShortcutEditor(model:model,selection:selection) }
        .sheet(isPresented:$showingAccessibilityHelp) { accessibilityHelp }
        .alert("Even More Gestures",isPresented:Binding(get:{model.issue != nil},set:{if !$0 {model.issue = nil}})) { Button("OK") { model.issue = nil } } message: { Text(model.issue ?? "") }
    }
    private var permissionBanner: some View {
        HStack(alignment:.top,spacing:14) {
            Image(systemName:"hand.raised.fill").font(.system(size:24,weight:.medium)).foregroundStyle(.blue).frame(width:36)
            VStack(alignment:.leading,spacing:5) {
                Text("Finish setup to turn gestures on").font(.system(size:15,weight:.semibold))
                Text("Even More Gestures needs Accessibility permission before it can switch tabs, close them, or open sidebars in your apps.").font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Button("Show setup steps") { showingAccessibilityHelp = true }.buttonStyle(.link).font(.system(size:12))
            }
            Spacer()
            Button("Open Accessibility") { model.requestPermission() }.buttonStyle(.borderedProminent).controlSize(.regular)
        }.padding(18).background(.blue.opacity(0.09),in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(.blue.opacity(0.18),lineWidth:1))
    }
    private var accessibilityHelp: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack(spacing:12) {
                Image(systemName:"hand.raised.fill").font(.system(size:28)).foregroundStyle(.blue)
                VStack(alignment:.leading,spacing:3) {
                    Text("Turn on Accessibility").font(.title2.weight(.semibold))
                    Text("One-time setup. Your settings stay on this Mac.").foregroundStyle(.secondary)
                }
            }
            VStack(alignment:.leading,spacing:13) {
                setupStep("1", "Open the Accessibility pane", "Use the button below. macOS opens directly to the right list.")
                setupStep("2", "Enable Even More Gestures", "Find it in the list and turn its switch on. If it isn’t listed, click + and choose this app from Applications.")
                setupStep("3", "Come back here", "This screen notices the permission automatically and turns your gestures on.")
            }
            Text("macOS protects this list, so apps cannot add themselves or accept permission on your behalf. You only need to do this once per app copy.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack { Spacer(); Button("Not now") { showingAccessibilityHelp = false }; Button("Open Accessibility") { model.requestPermission(); showingAccessibilityHelp = false }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width:510)
    }
    private func setupStep(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment:.top,spacing:12) {
            Text(number).font(.system(size:12,weight:.bold)).foregroundStyle(.white).frame(width:24,height:24).background(Color.accentColor,in:Circle())
            VStack(alignment:.leading,spacing:3) { Text(title).font(.system(size:13,weight:.semibold)); Text(detail).font(.system(size:12)).foregroundStyle(.secondary) }
        }
    }
    private var pauseStatus: String {
        guard let remaining = model.pauseRemaining else { return "Paused" }
        let seconds = max(0, Int(remaining.rounded(.up)))
        return String(format: "Paused · %d:%02d", seconds / 60, seconds % 60)
    }
    private enum FooterStatusAction { case accessibility, general, reconnect }
    private struct FooterStatus {
        let title: String
        let symbol: String
        let color: Color
        let help: String
        let action: FooterStatusAction
    }
    private var footerStatus: FooterStatus {
        if !model.permission {
            return .init(title:"Accessibility needed", symbol:"hand.raised.fill", color:.blue, help:"Open Accessibility settings", action:.accessibility)
        }
        if model.paused {
            return .init(title:pauseStatus, symbol:"pause.fill", color:.orange, help:"Open General settings to resume gestures", action:.general)
        }
        if let error = model.store.error {
            return .init(title:"Settings need attention", symbol:"exclamationmark.triangle.fill", color:.orange, help:error, action:.general)
        }
        if !model.input.isRunning {
            return .init(title:"Trackpad needs reconnecting", symbol:"trackpad", color:.orange, help:model.input.status, action:.reconnect)
        }
        return .init(title:"Gestures active", symbol:"checkmark.circle.fill", color:.green, help:"Open General settings", action:.general)
    }
    private func performFooterStatusAction() {
        switch footerStatus.action {
        case .accessibility:
            model.requestPermission()
        case .general:
            tab = "General"
        case .reconnect:
            tab = "General"
            model.input.start()
        }
    }
    private var gesturesView: some View {
        VStack(spacing:18) {
            GesturePreview(gesture:model.preview, pinchFingerCount:model.pinchFingerCount, isActive:model.settingsVisible)
            VStack(spacing:0) {
                gestureRow("Rotate with two fingers", subtitle:"Defaults to switching between tabs in enabled apps",icon:"arrow.trianglehead.2.clockwise.rotate.90", binding:$model.rotateEnabled,preview:.rotate)
                Divider().padding(.leading,50)
                gestureRow("Pinch and spread with \(model.pinchFingerCount) fingers",subtitle:"Defaults to closing or opening tabs in enabled apps",icon:"arrow.down.right.and.arrow.up.left",binding:$model.pinchEnabled,preview:.pinch)
                Divider().padding(.leading,50)
                gestureRow("Spread out to undo",subtitle:"Defaults to reopening a recently closed tab",icon:"arrow.uturn.backward",binding:$model.undoEnabled,preview:.spread)
                Divider().padding(.leading,50)
                gestureRow("Swipe left with four fingers",subtitle:"Defaults to showing or hiding the left sidebar in selected apps",icon:"sidebar.left",binding:$model.leftEnabled,preview:.left)
                Divider().padding(.leading,50)
                gestureRow("Swipe right with four fingers",subtitle:"Defaults to showing or hiding the right sidebar in selected apps",icon:"sidebar.right",binding:$model.rightEnabled,preview:.right)
            }.card()
            VStack(spacing:14) {
                HStack {
                    VStack(alignment:.leading,spacing:3) { Text("Rotation per tab"); Text("Smaller turns switch tabs sooner.").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Slider(value:$model.rotationStep,in:20...45,step:1).frame(width:170).accessibilityLabel("Degrees per tab")
                    Text("\(Int(model.rotationStep))°").monospacedDigit().foregroundStyle(.secondary).frame(width:32)
                }
                Divider()
                settingToggle("Haptic feedback",value:$model.haptics)
                HStack {
                    Text("Pinch and spread")
                    Spacer()
                    Picker("Pinch and spread",selection:$model.pinchFingerCount) {
                        Text("2 fingers").tag(2)
                        Text("3 fingers").tag(3)
                    }.labelsHidden().pickerStyle(.segmented).frame(width:190)
                }
                if model.pinchFingerCount == 2 {
                    Text("Two-finger pinch may also zoom in the app you’re using.").font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
                }
                settingToggle("Show the undo hint",value:$model.showHUD)
                settingToggle("Invert sidebar direction",value:$model.invert)
            }.font(.system(size:12)).toggleStyle(.switch).controlSize(.small).padding(16).card()
            Text("Already set up for the apps you use. Fine-tune individual apps in the Apps tab.").font(.system(size:11)).foregroundStyle(.secondary)
        }
    }
    private func gestureRow(_ title: String, subtitle: String, icon: String, binding: Binding<Bool>, preview: PreviewGesture) -> some View {
        HStack(spacing:13) {
            Image(systemName:icon).font(.system(size:17)).foregroundStyle(.blue).frame(width:24)
            VStack(alignment:.leading,spacing:4) { Text(title).font(.system(size:13,weight:.medium)); Text(subtitle).font(.system(size:12)).foregroundStyle(.primary.opacity(0.65)) }
            Spacer()
            Toggle(title,isOn:binding).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }.padding(.horizontal,16).padding(.vertical,13).contentShape(Rectangle()).onHover { if $0 { model.preview = preview } }
    }
    private var appsView: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Text(appSummary).font(.system(size:15,weight:.medium)).foregroundStyle(.secondary)
                Spacer()
                Button { model.addApp() } label:{ Label("Add App",systemImage:"plus") }
            }
            HStack(spacing:10) {
                TextField("Search your apps",text:$search).textFieldStyle(.roundedBorder)
                Picker("Filter apps",selection:$appFilter) { ForEach(AppFilter.allCases) { Text($0.rawValue).tag($0) } }
                    .labelsHidden().pickerStyle(.menu).frame(width:145)
            }
            ForEach(filteredApps) { app in
                VStack(spacing:0) {
                    HStack(spacing:12) {
                        Button { withAnimation(.easeInOut(duration:0.15)) { expanded = expanded == app.id ? nil : app.id } } label: {
                            HStack(spacing:12) {
                                Image(nsImage:app.icon).resizable().frame(width:32,height:32)
                                Text(app.name).font(.system(size:13,weight:.medium))
                                Text(app.isCustom ? "Custom" : "Preset").font(.system(size:9,weight:.medium)).foregroundStyle(.secondary).padding(.horizontal,7).padding(.vertical,3).background(.quaternary,in:Capsule())
                                Spacer()
                                Image(systemName: expanded == app.id ? "chevron.down" : "chevron.right").font(.system(size:10)).foregroundStyle(.secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Toggle("Enable \(app.name)",isOn:Binding(get:{model.store.isEnabled(bundleIdentifier:app.id)},set:{model.store.setEnabled($0,bundleIdentifier:app.id)})).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }.padding(13)
                    if expanded == app.id {
                        Divider()
                        VStack(spacing:12) {
                            ForEach(GestureAction.allCases) { action in
                                let globallyEnabled = model.isGestureEnabled(action)
                                HStack(spacing:12) {
                                    ActionGestureCue(action:action,pinchFingerCount:model.pinchFingerCount,isActive:model.settingsVisible,inverted:model.invert)
                                    VStack(alignment:.leading,spacing:3) {
                                        Text(action.gestureName(inverted:model.invert)).font(.system(size:12,weight:.medium))
                                        if globallyEnabled {
                                            actionDescriptionView(action, app: app)
                                        } else {
                                            Text("Disabled in Gestures").font(.system(size:12)).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    let mode = model.store.overrideMode(action:action,bundleIdentifier:app.id)
                                    Menu {
                                        Button("Default") { model.store.setOverride(.useDefault,action:action,bundleIdentifier:app.id) }
                                        Button("Off") { model.store.setOverride(.off,action:action,bundleIdentifier:app.id) }
                                        Button("Custom shortcut…") { editing = ShortcutSelection(app:app,action:action) }
                                    } label: { Text(modeLabel(mode)).frame(width:80,alignment:.trailing) }.menuStyle(.borderlessButton).fixedSize()
                                }.opacity(globallyEnabled ? 1 : 0.45).disabled(!globallyEnabled)
                            }
                        }.padding(16)
                    }
                }.card()
            }
            if model.apps.isEmpty { ContentUnavailableView("Add your first app",systemImage:"app.badge",description:Text("Choose an app and assign a shortcut to any gesture.")) }
            else if filteredApps.isEmpty {
                ContentUnavailableView("No apps found",systemImage:"magnifyingglass",description:Text("Try a different search or filter."))
                    .frame(maxWidth:.infinity,minHeight:240)
            }
            Text("Terminal close gestures and rotation in image apps are off by default. Default actions follow app menus when available.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var filteredApps: [InstalledApp] {
        model.apps.filter { app in
            let matchesSearch = search.isEmpty || app.name.localizedCaseInsensitiveContains(search)
            guard matchesSearch else { return false }
            switch appFilter {
            case .all: return true
            case .presets: return !app.isCustom
            case .custom: return app.isCustom
            case .overrides: return hasOverride(app)
            }
        }
    }
    private var appSummary: String {
        let presetCount = filteredApps.filter { !$0.isCustom }.count
        let customCount = filteredApps.filter(\.isCustom).count
        let parts = [
            presetCount > 0 ? "\(presetCount) preset \(presetCount == 1 ? "app" : "apps")" : nil,
            customCount > 0 ? "\(customCount) custom \(customCount == 1 ? "app" : "apps")" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? "No apps match this filter" : parts.joined(separator:" · ")
    }
    private func hasOverride(_ app: InstalledApp) -> Bool {
        guard let override = model.store.overrides[app.id] else { return false }
        return !override.enabled || override.actions.values.contains { action in
            if case .useDefault = action { return false }
            return true
        }
    }
    @ViewBuilder
    private func actionDescriptionView(_ action: GestureAction, app: InstalledApp) -> some View {
        switch model.store.overrideMode(action: action, bundleIdentifier: app.id) {
        case .useDefault:
            if let plan = model.store.plan(action: action, bundleIdentifier: app.id) {
                if let shortcut = plan.shortcut {
                    defaultActionDescription(formattedShortcut(shortcut), action: action)
                } else if let menuPath = plan.menuPaths.first?.joined(separator: " › ") {
                    defaultActionDescription(menuPath, action: action)
                } else {
                    Text("No action").font(.system(size:12)).foregroundStyle(.secondary)
                }
            } else {
                Text("Off by default").font(.system(size:12)).foregroundStyle(.secondary)
            }
        case .off:
            Text("Off").font(.system(size:12)).foregroundStyle(.secondary)
        case .custom(let shortcut):
            Text(formattedShortcut(shortcut)).font(.system(size:12)).foregroundStyle(.primary.opacity(0.72))
        }
    }
    private func defaultActionDescription(_ shortcutOrMenu: String, action: GestureAction) -> some View {
        HStack(spacing:4) {
            Text(shortcutOrMenu).foregroundStyle(.primary.opacity(0.72))
            Text("(\(action.title.lowercased()))").foregroundStyle(.secondary)
        }
        .font(.system(size:12))
        .lineLimit(1)
    }
    private func formattedShortcut(_ shortcut: String) -> String {
        shortcut.replacingOccurrences(of:"cmd+",with:"⌘").replacingOccurrences(of:"ctrl+",with:"⌃").replacingOccurrences(of:"alt+",with:"⌥").replacingOccurrences(of:"shift+",with:"⇧").uppercased()
    }
    private func modeLabel(_ mode: ActionOverride) -> String { switch mode {case .useDefault:return "Default";case .off:return "Off";case .custom:return "Custom"} }
    private var generalView: some View {
        VStack(alignment:.leading,spacing:18) {
            sectionLabel("EVERYDAY")
            VStack(spacing:16) {
                settingToggle("Launch at login",value:Binding(get:{model.launchAtLogin},set:{model.setLogin($0)}))
                Divider()
                settingToggle("Show menu bar icon",value:$model.showMenuIcon)
                Text("If you hide the icon, open Even More Gestures from Finder or Spotlight to return here.").font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
                Divider()
                HStack { Text("Gestures"); Spacer(); Button(model.paused ? "Resume" : "Pause") { model.togglePause() }; Button("Pause for 1 Hour") { model.pauseForHour() } }
            }.font(.system(size:12)).toggleStyle(.switch).controlSize(.small).padding(16).card()
            sectionLabel("PERMISSIONS & INPUT")
            VStack(alignment:.leading,spacing:14) {
                HStack { Label("Accessibility",systemImage: model.permission ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(model.permission ? .green : .orange); Spacer(); Button(model.permission ? "System Settings…" : "Allow…") { model.requestPermission() } }
                Divider()
                HStack { Text(model.input.status).foregroundStyle(.secondary); Spacer(); Button("Reconnect") { model.input.start() } }
                Text("If a connected trackpad is silent on your macOS version, check Input Monitoring, then reconnect.").font(.caption).foregroundStyle(.secondary)
                Button("Input Monitoring settings…") { model.openInputMonitoring() }.buttonStyle(.link)
            }.font(.system(size:12)).padding(16).card()
            sectionLabel("COMPATIBILITY")
            if model.conflicts.isEmpty { banner("No other gesture utilities detected.",icon:"checkmark.shield",color:.green) }
            ForEach(model.conflicts,id:\.self) { banner($0,icon:"exclamationmark.triangle",color:.orange) }
            Text("Four-finger swipes also belong to macOS. Sidebar changes are reverted when a Spaces change is detected within 0.6 seconds; this needs validation on your Mac.").font(.caption).foregroundStyle(.secondary)
            sectionLabel("UPDATES & ABOUT")
            VStack(alignment:.leading,spacing:9) {
                Text("Even More Gestures \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "")").fontWeight(.medium)
                Text("App updates download securely in the background. Gesture defaults refresh daily so supported apps can stay current. Your custom shortcuts always take priority.").foregroundStyle(.secondary)
                HStack(spacing:10) {
                    Button("Show setup again") { model.showOnboarding = true }
                    Button("Check for Updates…") { model.checkForUpdates() }
                }
            }.font(.system(size:12)).padding(16).frame(maxWidth:.infinity,alignment:.leading).card()
        }
    }
    private func settingToggle(_ title: String, value: Binding<Bool>) -> some View {
        HStack { Text(title); Spacer(); Toggle(title,isOn:value).labelsHidden().toggleStyle(.switch).controlSize(.small) }
    }
    private func sectionLabel(_ text: String) -> some View { Text(text).font(.system(size:10,weight:.semibold)).tracking(1).foregroundStyle(.secondary) }
    private func banner(_ text: String,icon: String,color: Color) -> some View { HStack(spacing:10) { Image(systemName:icon).foregroundStyle(color); Text(text).font(.system(size:12)); Spacer(minLength:0) }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(color.opacity(0.07),in:RoundedRectangle(cornerRadius:10)) }
}
private extension View {
    func card() -> some View { background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(.secondary.opacity(0.12),lineWidth:0.5)) }
}
struct ShortcutSelection: Identifiable { let id = UUID(); let app: InstalledApp; let action: GestureAction }
struct ShortcutEditor: View {
    @ObservedObject var model: AppModel
    let selection: ShortcutSelection
    @Environment(\.dismiss) private var dismiss
    @State private var shortcut = ""
    @State private var recording = false
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("\(selection.action.title) in \(selection.app.name)").font(.headline)
            Text("Record a shortcut, or type one such as cmd+shift+t. Include Command, Control, or Option.").font(.callout).foregroundStyle(.secondary)
            TextField("cmd+shift+t",text:$shortcut).textFieldStyle(.roundedBorder)
            ShortcutRecorder(shortcut:$shortcut,recording:$recording).frame(height:44)
            HStack { Button(recording ? "Press your shortcut…" : "Record shortcut") { recording.toggle() }; Spacer(); Button("Cancel") { dismiss() }; Button("Save") { model.store.setOverride(.custom(shortcut),action:selection.action,bundleIdentifier:selection.app.id); dismiss() }.buttonStyle(.borderedProminent).disabled(KeyShortcut.parse(shortcut) == nil) }
        }.padding(24).frame(width:470).onAppear { if case .custom(let keys) = model.store.overrideMode(action:selection.action,bundleIdentifier:selection.app.id) { shortcut = keys } }
    }
}
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: String
    @Binding var recording: Bool
    func makeNSView(context: Context) -> CaptureView { CaptureView() }
    func updateNSView(_ view: CaptureView,context: Context) {
        view.onCapture = { shortcut = $0; recording = false }
        view.active = recording
        if recording { DispatchQueue.main.async { view.window?.makeFirstResponder(view) } }
    }
    class CaptureView: NSView {
        var active = false
        var onCapture: ((String)->Void)?
        override var acceptsFirstResponder: Bool { true }
        override func performKeyEquivalent(with event: NSEvent) -> Bool { guard active else { return false }; capture(event); return true }
        override func keyDown(with event: NSEvent) { if active { capture(event) } else { super.keyDown(with:event) } }
        private func capture(_ event: NSEvent) {
            var parts: [String] = []; let flags = event.modifierFlags
            if flags.contains(.command) { parts.append("cmd") }; if flags.contains(.control) { parts.append("ctrl") }; if flags.contains(.option) { parts.append("alt") }; if flags.contains(.shift) { parts.append("shift") }
            let special: [UInt16:String] = [48:"tab",123:"left",124:"right",125:"down",126:"up",36:"return",53:"escape",49:"space",51:"delete"]
            guard let key = special[event.keyCode] ?? event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else { return }
            parts.append(key); let result = parts.joined(separator:"+")
            if KeyShortcut.parse(result) != nil { onCapture?(result) }
        }
    }
}
