import AppKit
import Combine
import IOKit
import GestureKit
import TouchBridge

private final class FrameProcessor {
    private var engines: [UInt: GestureEngine] = [:]
    private var lastGeneration: UInt64 = 0
    private var down = Set<UInt>()
    private var blocked = Set<UInt>()
    var deliver: ((GestureEvent, UInt64) -> Void)?
    func process(device: UInt, contacts: UnsafePointer<EMGContact>?, count: Int32, timestamp: Double, generation: UInt64, rotation: Double, pinchFingers: Int32) {
        if generation != lastGeneration {
            blocked.formUnion(down)
            engines.removeAll(keepingCapacity: true); lastGeneration = generation
        }
        if count == 0 { down.remove(device); blocked.remove(device) }
        else { down.insert(device) }
        guard !blocked.contains(device) else { return }
        let engine: GestureEngine
        if let existing = engines[device] { engine = existing }
        else { engine = GestureEngine(configuration: .init(rotationStepDegrees: rotation, pinchFingerCount: Int(pinchFingers))); engines[device] = engine }
        let events = withUnsafeTemporaryAllocation(of: TouchContact.self, capacity: 5) { buffer -> [GestureEvent] in
            let n = min(5, max(0, Int(count)))
            for i in 0..<n {
                let point = contacts![i]
                buffer.initializeElement(at: i, to: TouchContact(id: point.id, x: point.x, y: point.y))
            }
            defer { buffer.baseAddress?.deinitialize(count: n) }
            return engine.process(contacts: UnsafeBufferPointer(start: buffer.baseAddress, count: n), timestamp: timestamp)
        }
        for event in events { deliver?(event, generation) }
    }
}
@MainActor final class TouchInputController: ObservableObject {
    @Published private(set) var status = "Accessibility permission needed"
    @Published private(set) var deviceCount = 0
    @Published private(set) var isRunning = false
    var onGesture: ((GestureEvent) -> Void)?
    private var rotation = 30.0
    private var pinchFingers: Int32 = 3
    private let processor = FrameProcessor()
    private var observers: [NSObjectProtocol] = []
    private var port: IONotificationPortRef?
    private var added: io_iterator_t = 0
    private var removed: io_iterator_t = 0
    private var reconnect: DispatchWorkItem?
    init() {
        processor.deliver = { [weak self] event, generation in
            DispatchQueue.main.async {
                guard EMGGeneration() == generation, let self, self.isRunning else { return }
                self.onGesture?(event)
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReconnect() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        })
        port = IONotificationPortCreate(kIOMainPortDefault)
        if let port {
            IONotificationPortSetDispatchQueue(port, .main)
            let context = Unmanaged.passUnretained(self).toOpaque()
            for kind in [kIOFirstMatchNotification, kIOTerminatedNotification] {
                var iterator: io_iterator_t = 0
                IOServiceAddMatchingNotification(port, kind, IOServiceMatching("AppleMultitouchDevice"), { context, iterator in
                    while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
                    guard let context else { return }
                    DispatchQueue.main.async {
                        Unmanaged<TouchInputController>.fromOpaque(context).takeUnretainedValue().scheduleReconnect()
                    }
                }, context, &iterator)
                while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
                if kind == kIOFirstMatchNotification { added = iterator } else { removed = iterator }
            }
        }
    }
    func start() {
        guard AXIsProcessTrusted() else { status = "Accessibility permission needed"; return }
        EMGReset(rotation, pinchFingers)
        let count = EMGStart({ device, contacts, count, time, generation, rotation, pinchFingers, context in
            guard let context else { return }
            Unmanaged<FrameProcessor>.fromOpaque(context).takeUnretainedValue().process(device: device, contacts: contacts, count: count, timestamp: time, generation: generation, rotation: rotation, pinchFingers: pinchFingers)
        }, Unmanaged.passUnretained(processor).toOpaque())
        deviceCount = max(0, Int(count)); isRunning = count > 0
        status = String(cString: EMGError())
    }
    func stop() { EMGStop(); isRunning = false; deviceCount = 0 }
    func resetGestureSessions() { EMGReset(rotation, pinchFingers) }
    func setRotationStep(_ degrees: Double) { rotation = degrees; resetGestureSessions() }
    func setPinchFingers(_ count: Int) { pinchFingers = count == 2 ? 2 : 3; resetGestureSessions() }
    func scheduleReconnect() {
        reconnect?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.start() }
        reconnect = item; DispatchQueue.main.asyncAfter(deadline: .now()+0.8, execute: item)
    }
}
