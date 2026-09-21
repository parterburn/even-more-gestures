import SwiftUI
import GestureKit

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @State private var step = 0
    @State private var login = true
    var body: some View {
        VStack(spacing:24) {
            HStack(spacing:7) { ForEach(0..<4) { index in Capsule().fill(index == step ? Color.accentColor : .secondary.opacity(0.15)).frame(width:24,height:4) } }.padding(.top,30)
            Spacer(minLength:0)
            switch step {
            case 0:
                VStack(spacing:12) {
                    Text("Your trackpad has more to give.").font(.system(size:28,weight:.semibold))
                    Text("Switch tabs, close them, and open sidebars.\nAlready set up for the apps you use.").font(.system(size:14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                GesturePreview(gesture:.rotate,pinchFingerCount:model.pinchFingerCount,isActive:model.settingsVisible)
            case 1:
                Image(systemName: model.permission ? "checkmark.shield.fill" : "hand.raised.circle.fill").font(.system(size:52)).foregroundStyle(model.permission ? .green : .blue)
                Text(model.permission ? "You’re all set." : "A small permission. More possibilities.").font(.system(size:25,weight:.semibold))
                Text("Accessibility lets Even More Gestures activate commands in the app you’re using. Everything stays on your Mac.").font(.system(size:14)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth:440)
                Button(model.permission ? "Accessibility allowed" : "Allow Accessibility") { model.requestPermission() }.buttonStyle(.borderedProminent).disabled(model.permission)
                Text("Return here after enabling the app in System Settings.").font(.caption).foregroundStyle(.secondary)
            case 2:
                VStack(spacing:10) {
                    Text("Give it a little twist.").font(.system(size:27,weight:.semibold))
                    Text("Rotate to switch tabs. Pinch with \(model.pinchFingerCount) fingers to close. Spread to bring it back.").foregroundStyle(.secondary)
                }
                PracticeView(model:model)
                Text(model.permission ? "These are practice tabs. Your other apps stay untouched." : "You can explore the demo below, then enable Accessibility to use your trackpad.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            default:
                Image(systemName:"checkmark.circle.fill").font(.system(size:54)).foregroundStyle(.green)
                Text("Already set up for \(model.apps.count) apps.").font(.system(size:27,weight:.semibold))
                HStack(spacing:10) { ForEach(Array(model.apps.prefix(9))) { app in Image(nsImage:app.icon).resizable().frame(width:36,height:36).help(app.name) } }
                Text("Make it yours in Settings. Pause any time from the menu bar.").font(.callout).foregroundStyle(.secondary)
                Toggle("Launch at login",isOn:$login).toggleStyle(.checkbox).fixedSize()
            }
            Spacer(minLength:0)
            if !model.conflicts.isEmpty && step == 1 { Text(model.conflicts.joined(separator:"\n")).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center) }
            HStack {
                Button(step == 0 ? "Skip setup" : "Back") { if step == 0 { model.finishOnboarding() } else { step -= 1; model.practice = step == 2 } }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button(step == 3 ? "Let’s go" : step == 1 && !model.permission ? "Try the demo" : "Continue") {
                    if step == 3 { if login { model.setLogin(true) }; model.finishOnboarding() }
                    else { step += 1; model.practice = step == 2 }
                }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            }.padding(.bottom,12)
        }.padding(.horizontal,40).padding(.bottom,20).onDisappear { model.practice = false }
    }
}
struct PracticeView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:5) {
                ForEach(Array(model.practiceTabs.enumerated()),id:\.offset) { index, tab in
                    Text(tab).font(.system(size:11,weight:index == model.practiceIndex ? .medium : .regular)).lineLimit(1).padding(.horizontal,10).padding(.vertical,9)
                        .frame(maxWidth:.infinity).background(index == model.practiceIndex ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05),in:RoundedRectangle(cornerRadius:6))
                }
                if model.practiceTabs.isEmpty { Text("All clear. Spread to open a tab.").font(.caption).foregroundStyle(.secondary).padding(8) }
            }.padding(10)
            Divider()
            VStack(spacing:9) {
                Image(systemName:"sparkles").font(.system(size:25)).foregroundStyle(.blue)
                Text(model.practiceTabs.isEmpty ? "Room for a fresh start." : model.practiceTabs[min(model.practiceIndex,model.practiceTabs.count-1)]).font(.system(size:17,weight:.medium))
                Text(model.lastEvent).font(.system(size:10)).foregroundStyle(.secondary)
            }.frame(maxWidth:.infinity).padding(.vertical,24)
            Divider()
            HStack(spacing:12) {
                Text("Demo controls").font(.system(size:10)).foregroundStyle(.secondary)
                Button { model.practiceEvent(.rotateCounterclockwise) } label:{ Image(systemName:"arrow.counterclockwise") }.help("Previous tab")
                Button { model.practiceEvent(.rotateClockwise) } label:{ Image(systemName:"arrow.clockwise") }.help("Next tab")
                Button("Pinch") { model.practiceEvent(.pinchIn) }
                Button("Spread") { model.practiceEvent(.pinchOut) }
                Spacer()
            }.buttonStyle(.borderless).font(.system(size:11)).padding(12)
        }.background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(.secondary.opacity(0.15),lineWidth:1))
    }
}
