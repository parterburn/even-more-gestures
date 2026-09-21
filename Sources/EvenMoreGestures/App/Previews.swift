import SwiftUI
import GestureCore

enum PreviewGesture: String, CaseIterable {
    case rotate, pinch, spread, left, right
    var title: String {
        switch self { case .rotate: return "A twist. A different tab."; case .pinch: return "Pinch it closed."; case .spread: return "Make room for something new."; case .left: return "Your sidebar, within reach."; case .right: return "A little space on the right." }
    }
    var instruction: String {
        switch self { case .rotate: return "Rotate with two fingers"; case .pinch: return "Pinch with three fingers"; case .spread: return "Spread with three fingers"; case .left: return "Swipe left with four fingers"; case .right: return "Swipe right with four fingers" }
    }
}

extension GestureAction {
    func gestureInstruction(pinchFingerCount: Int = 3) -> String {
        switch self {
        case .nextTab: return "Rotate right · two fingers"
        case .previousTab: return "Rotate left · two fingers"
        case .closeTab: return "Pinch in · \(pinchFingerCount) fingers"
        case .newTab, .reopenClosedTab: return "Spread out · \(pinchFingerCount) fingers"
        case .toggleLeftSidebar: return "Swipe left · four fingers"
        case .toggleRightSidebar: return "Swipe right · four fingers"
        }
    }
}

struct ActionGestureCue: View {
    let action: GestureAction
    var pinchFingerCount = 3
    var isActive = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !isActive)) { context in
            let phase = reduceMotion ? 0.6 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.6) / 2.6
            cueCanvas(progress: 0.15 + 0.85 * sin(phase * .pi))
        }
        .frame(width: 46, height: 46)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(action.gestureInstruction(pinchFingerCount: pinchFingerCount))
    }

    private func cueCanvas(progress: Double) -> some View {
        Canvas { context, size in
                let pad = CGRect(x: 1, y: 1, width: size.width - 2, height: size.height - 2)
                context.fill(Path(roundedRect: pad, cornerRadius: 11), with: .color(.accentColor.opacity(0.09)))
                context.stroke(Path(roundedRect: pad, cornerRadius: 11), with: .color(.accentColor.opacity(0.22)), lineWidth: 1)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)

                switch action {
                case .nextTab, .previousTab:
                    let clockwise = action == .nextTab
                    let start = clockwise ? -2.30 : 0.84
                    let end = clockwise ? 0.84 : -2.30
                    var arc = Path()
                    arc.addArc(center: center, radius: 13, startAngle: .radians(start), endAngle: .radians(start + (end - start) * progress), clockwise: !clockwise)
                    context.stroke(arc, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    let angle = start + (end - start) * progress
                    let arrowPoint = CGPoint(x: center.x + cos(angle) * 13, y: center.y + sin(angle) * 13)
                    context.fill(Path(ellipseIn: CGRect(x: arrowPoint.x - 3.5, y: arrowPoint.y - 3.5, width: 7, height: 7)), with: .color(.accentColor))
                    for direction in [-1.0, 1.0] {
                        let finger = CGPoint(x: center.x + direction * cos(angle) * 7, y: center.y + direction * sin(angle) * 7)
                        context.fill(Path(ellipseIn: CGRect(x: finger.x - 3.2, y: finger.y - 3.2, width: 6.4, height: 6.4)), with: .color(.primary.opacity(0.78)))
                    }
                case .closeTab, .newTab, .reopenClosedTab:
                    let spreading = action != .closeTab
                    let distance = spreading ? 5 + progress * 9 : 14 - progress * 9
                    for index in 0..<pinchFingerCount {
                        let angle = Double(index) * (2 * .pi / Double(pinchFingerCount)) - .pi / 2
                        let point = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
                        context.fill(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)), with: .color(.accentColor))
                        context.stroke(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)), with: .color(.white.opacity(0.65)), lineWidth: 0.7)
                    }
                case .toggleLeftSidebar, .toggleRightSidebar:
                    let left = action == .toggleLeftSidebar
                    let offset = (progress - 0.5) * 17 * (left ? -1 : 1)
                    let arrow = left ? "‹" : "›"
                    context.draw(Text(arrow).font(.system(size: 27, weight: .medium)).foregroundStyle(Color.accentColor), at: CGPoint(x: center.x + (left ? -11 : 11), y: center.y - 1))
                    for index in 0..<4 {
                        let point = CGPoint(x: center.x + CGFloat(index - 1) * 5 + offset, y: center.y + CGFloat(abs(index - 1)) * 1.8)
                        context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(.primary.opacity(0.8)))
                    }
                }
            }
    }
}

struct GesturePreview: View {
    let gesture: PreviewGesture
    var pinchFingerCount = 3
    var isActive = true
    private var instruction: String {
        switch gesture {
        case .pinch: return "Pinch with \(pinchFingerCount) fingers"
        case .spread: return "Spread with \(pinchFingerCount) fingers"
        default: return gesture.instruction
        }
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/30, paused: reduceMotion || !isActive)) { context in
            let phase = reduceMotion ? 0.65 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.5) / 3.5
            let progress = min(1, max(0, (phase - 0.12)/0.68))
            HStack(spacing: 16) {
                VStack(spacing: 13) {
                    Canvas { ctx, size in
                        let pad = CGRect(x: 16, y: 8, width: size.width-32, height: size.height-16)
                        ctx.fill(Path(roundedRect: pad, cornerRadius: 15), with: .linearGradient(Gradient(colors: [Color(nsColor: .controlBackgroundColor), Color(nsColor: .separatorColor).opacity(0.14)]), startPoint: .zero, endPoint: CGPoint(x: 0,y:size.height)))
                        ctx.stroke(Path(roundedRect: pad, cornerRadius: 15), with: .color(.secondary.opacity(0.4)), lineWidth: 1)
                        let cx = size.width/2, cy = size.height/2
                        let scale = min(size.width,size.height)
                        var points: [CGPoint] = []
                        switch gesture {
                        case .rotate:
                            let angle = -0.6 + progress*1.65
                            for sign in [-1.0,1.0] { points.append(CGPoint(x:cx+sign*cos(angle)*scale*0.20,y:cy+sign*sin(angle)*scale*0.20)) }
                            var arc = Path(); arc.addArc(center: CGPoint(x:cx,y:cy), radius: scale*0.2, startAngle:.radians(-0.6),endAngle:.radians(angle),clockwise:false)
                            ctx.stroke(arc,with:.color(.accentColor.opacity(0.3)),style:StrokeStyle(lineWidth:3,lineCap:.round))
                        case .pinch, .spread:
                            let radius = scale*(gesture == .pinch ? 0.28-progress*0.15 : 0.12+progress*0.17)
                            for i in 0..<pinchFingerCount { let a = Double(i)*2*Double.pi/Double(pinchFingerCount)-Double.pi/2; points.append(CGPoint(x:cx+cos(a)*radius,y:cy+sin(a)*radius)) }
                        case .left, .right:
                            let offset = (progress-0.5)*scale*0.45*(gesture == .left ? -1 : 1)
                            for i in 0..<4 { points.append(CGPoint(x:cx+Double(i-2)*19+9+offset,y:cy+Double(abs(i-1))*4)) }
                        }
                        for point in points {
                            ctx.fill(Path(ellipseIn:CGRect(x:point.x-13,y:point.y-13,width:26,height:26)),with:.color(.accentColor.opacity(0.12)))
                            ctx.fill(Path(ellipseIn:CGRect(x:point.x-8,y:point.y-8,width:16,height:16)),with:.color(.accentColor.opacity(0.85)))
                            ctx.stroke(Path(ellipseIn:CGRect(x:point.x-8,y:point.y-8,width:16,height:16)),with:.color(.white.opacity(0.65)),lineWidth:1)
                        }
                    }.frame(height: 133)
                    Text(instruction).font(.system(size:12)).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity)
                VStack(spacing:13) {
                    MiniWindow(gesture: gesture, progress: progress).frame(height:133)
                    Text(gesture.title).font(.system(size:12)).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity)
            }
        }.padding(20).background(.quaternary.opacity(0.35),in:RoundedRectangle(cornerRadius:16))
        .accessibilityElement(children:.ignore).accessibilityLabel(instruction + ". " + gesture.title)
    }
}
private struct MiniWindow: View {
    let gesture: PreviewGesture
    let progress: Double
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:4) {
                ForEach([Color.red.opacity(0.65),.yellow.opacity(0.75),.green.opacity(0.6)],id:\.self) { color in Circle().fill(color).frame(width:6,height:6) }
                Spacer()
                Image(systemName:"sidebar.left").font(.system(size:10)).foregroundStyle(.secondary)
            }.padding(.horizontal,10).frame(height:25).background(.quaternary.opacity(0.4))
            HStack(spacing:3) {
                ForEach(0..<3) { index in
                    RoundedRectangle(cornerRadius:4).fill(index == (progress > 0.5 ? 1 : 0) ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.07))
                        .overlay(Text(["Explore","Ideas","Notes"][index]).font(.system(size:9)).foregroundStyle(.secondary))
                        .opacity(gesture == .pinch && index == 1 ? 1-progress : 1)
                }
                if gesture == .spread { Image(systemName:"plus").font(.system(size:10)).opacity(progress) }
            }.padding(5).frame(height:27)
            HStack(spacing:0) {
                if gesture == .left { sidebar.frame(width:progress*58) }
                VStack(alignment:.leading,spacing:7) {
                    RoundedRectangle(cornerRadius:3).fill(Color.accentColor.opacity(0.2)).frame(width:70,height:8)
                    RoundedRectangle(cornerRadius:3).fill(.quaternary).frame(height:5)
                    RoundedRectangle(cornerRadius:3).fill(.quaternary).frame(width:95,height:5)
                    Spacer(minLength:0)
                }.padding(15).frame(maxWidth:.infinity,alignment:.leading)
                if gesture == .right { sidebar.frame(width:progress*58) }
            }.clipped()
        }.background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:9))
            .clipShape(RoundedRectangle(cornerRadius:9)).overlay(RoundedRectangle(cornerRadius:9).stroke(.secondary.opacity(0.23),lineWidth:1))
            .padding(.horizontal,9).padding(.vertical,8)
    }
    private var sidebar: some View {
        VStack(alignment:.leading,spacing:9) { ForEach(0..<3) { _ in Capsule().fill(Color.accentColor.opacity(0.18)).frame(height:4) }; Spacer(minLength:0) }.padding(10).background(Color.accentColor.opacity(0.04))
    }
}
