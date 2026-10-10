import AppKit
import Combine
import IOKit
import GestureKit
import TouchBridge

enum ThreeFingerClickAction: String, CaseIterable {
    case middleClick, optionClick
    var title: String { self == .middleClick ? "Middle click" : "Option-click" }
}

final class ThreeFingerContactState {
    private let lock = NSLock()
    private var activeDevices = Set<UInt>()
    func update(device: UInt, count: Int) {
        lock.lock(); defer { lock.unlock() }
        if count == 3 { activeDevices.insert(device) } else { activeDevices.remove(device) }
    }
    func reset() { lock.lock(); activeDevices.removeAll(); lock.unlock() }
    func hasThreeFingerContacts() -> Bool { lock.lock(); defer { lock.unlock() }; return !activeDevices.isEmpty }
}

final class FrameProcessor {
    private var engines: [UInt: GestureEngine] = [:]
    private var tapRecognizers: [UInt: ThreeFingerTapRecognizer] = [:]
    private var lastGeneration: UInt64 = 0
    private var down = Set<UInt>()
    private var blocked = Set<UInt>()
    private let threeFingerContacts: ThreeFingerContactState
    var deliver: ((GestureEvent, UInt64) -> Void)?
    var deliverTap: ((UInt64) -> Void)?
    init(threeFingerContacts: ThreeFingerContactState) { self.threeFingerContacts = threeFingerContacts }
    func process(device: UInt, contacts: UnsafePointer<EMGContact>?, count: Int32, timestamp: Double, generation: UInt64, rotation: Double, pinchFingers: Int32) {
        if generation != lastGeneration {
            blocked.formUnion(down)
            engines.removeAll(keepingCapacity: true); tapRecognizers.removeAll(keepingCapacity: true); threeFingerContacts.reset(); lastGeneration = generation
        }
        if count == 0 { down.remove(device); blocked.remove(device) }
        else { down.insert(device) }
        guard !blocked.contains(device) else { return }
        let engine: GestureEngine
        if let existing = engines[device] { engine = existing }
        else { engine = GestureEngine(configuration: .init(rotationStepDegrees: rotation, pinchFingerCount: Int(pinchFingers))); engines[device] = engine }
        let events = withUnsafeTemporaryAllocation(of: TouchContact.self, capacity: 5) { buffer -> [GestureEvent] in
            let n = min(5, max(0, Int(count)))
            var validContacts = true
            for i in 0..<n {
                let point = contacts![i]
                if !point.x.isFinite || !point.y.isFinite || !(0...1).contains(point.x) || !(0...1).contains(point.y) {
                    validContacts = false
                }
                for j in 0..<i where contacts![j].id == point.id { validContacts = false }
                buffer.initializeElement(at: i, to: TouchContact(id: point.id, x: point.x, y: point.y))
            }
            defer { buffer.baseAddress?.deinitialize(count: n) }
            threeFingerContacts.update(device: device, count: validContacts ? n : 0)
            let tapRecognizer: ThreeFingerTapRecognizer
            if let existing = tapRecognizers[device] { tapRecognizer = existing }
            else { tapRecognizer = ThreeFingerTapRecognizer(); tapRecognizers[device] = tapRecognizer }
            let points = UnsafeBufferPointer(start: buffer.baseAddress, count: n)
            let tapped = tapRecognizer.process(contacts: points, timestamp: timestamp)
            let events = engine.process(contacts: points, timestamp: timestamp)
            if !events.isEmpty { tapRecognizer.cancel() }
            if tapped && events.isEmpty { deliverTap?(generation) }
            return events
        }
        for event in events { deliver?(event, generation) }
    }
}
@MainActor final class TouchInputController: ObservableObject {
    @Published private(set) var status = "Accessibility permission needed"
    @Published private(set) var deviceCount = 0
    @Published private(set) var isRunning = false
    var onGesture: ((GestureEvent) -> Void)?
    var onThreeFingerTap: (() -> Void)?
    var shouldHandleClick: () -> Bool = { !NSApp.isActive && AXIsProcessTrusted() } {
        didSet { clickController.shouldHandle = shouldHandleClick }
    }
    private var rotation = 30.0
    private var pinchFingers: Int32 = 3
    private let threeFingerContacts = ThreeFingerContactState()
    private lazy var processor = FrameProcessor(threeFingerContacts: threeFingerContacts)
    private lazy var clickController = ThreeFingerClickController(threeFingerContacts: threeFingerContacts)
    private var threeFingerClickEnabled = false
    private var threeFingerTapEnabled = false
    private var threeFingerClickAction: ThreeFingerClickAction = .middleClick
    private var observers: [NSObjectProtocol] = []
    private var port: IONotificationPortRef?
    private var added: io_iterator_t = 0
    private var removed: io_iterator_t = 0
    private var reconnect: DispatchWorkItem?
    private var suspended = false
    init() {
        clickController.shouldHandle = { [weak self] in self?.shouldHandleClick() ?? false }
        clickController.onPhysicalClick = { [weak self] in self?.resetGestureSessions() }
        processor.deliver = { [weak self] event, generation in
            DispatchQueue.main.async {
                guard EMGGeneration() == generation, let self, self.isRunning else { return }
                self.onGesture?(event)
            }
        }
        processor.deliverTap = { [weak self] generation in
            DispatchQueue.main.async {
                guard EMGGeneration() == generation, let self, self.isRunning else { return }
                self.onThreeFingerTap?()
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
        guard !suspended else { return }
        guard AXIsProcessTrusted() else { stop(); status = "Accessibility permission needed"; return }
        clickController.stop()
        threeFingerContacts.reset()
        EMGReset(rotation, pinchFingers)
        let count = EMGStart({ device, contacts, count, time, generation, rotation, pinchFingers, context in
            guard let context else { return }
            Unmanaged<FrameProcessor>.fromOpaque(context).takeUnretainedValue().process(device: device, contacts: contacts, count: count, timestamp: time, generation: generation, rotation: rotation, pinchFingers: pinchFingers)
        }, Unmanaged.passUnretained(processor).toOpaque())
        deviceCount = max(0, Int(count)); isRunning = count > 0
        status = String(cString: EMGError())
        updateClickMonitoring()
    }
    func stop() { clickController.stop(); EMGStop(); threeFingerContacts.reset(); isRunning = false; deviceCount = 0 }
    func suspend() { suspended = true; reconnect?.cancel(); stop() }
    func resume() { suspended = false; start() }
    func resetGestureSessions() { EMGReset(rotation, pinchFingers); threeFingerContacts.reset() }
    func setRotationStep(_ degrees: Double) { rotation = degrees; resetGestureSessions() }
    func setPinchFingers(_ count: Int) { pinchFingers = count == 2 ? 2 : 3; resetGestureSessions() }
    func setThreeFingerClick(enabled: Bool, action: ThreeFingerClickAction) {
        threeFingerClickEnabled = enabled
        threeFingerClickAction = action
        clickController.action = action
        clickController.remapEnabled = enabled
        updateClickMonitoring()
    }
    func setThreeFingerTap(enabled: Bool) {
        threeFingerTapEnabled = enabled
        resetGestureSessions()
        updateClickMonitoring()
    }
    private func updateClickMonitoring() {
        // Even tap-only mode must observe physical clicks so they cannot also fire a tap.
        if isRunning && (threeFingerClickEnabled || threeFingerTapEnabled) { clickController.start() }
        else { clickController.stop() }
    }
    @discardableResult func performThreeFingerTap() -> Bool { clickController.perform(action: threeFingerClickAction) }
    func scheduleReconnect() {
        guard !suspended else { return }
        reconnect?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.start() }
        reconnect = item; DispatchQueue.main.asyncAfter(deadline: .now()+0.8, execute: item)
    }
}

final class ThreeFingerClickController {
    private static let syntheticEventMarker: Int64 = 0x454D47
    var action: ThreeFingerClickAction = .middleClick
    var remapEnabled = true
    var shouldHandle: () -> Bool = { !NSApp.isActive && AXIsProcessTrusted() }
    var onPhysicalClick: (() -> Void)?
    var cursorLocation: () -> CGPoint? = { CGEvent(source: nil)?.location }
    var postEvent: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }
    private let threeFingerContacts: ThreeFingerContactState
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private struct PendingClick {
        let action: ThreeFingerClickAction
        var location: CGPoint
        let flags: CGEventFlags
        let clickCount: Int64
    }
    private var pending: PendingClick?
    init(threeFingerContacts: ThreeFingerContactState) { self.threeFingerContacts = threeFingerContacts }
    deinit { stop() }

    func start() {
        guard eventTap == nil, AXIsProcessTrusted() else { return }
        let types = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(types), callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<ThreeFingerClickController>.fromOpaque(context).takeUnretainedValue().handle(type: type, event: event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let pending {
            post(action: pending.action, type: pending.action == .middleClick ? .otherMouseUp : .leftMouseUp,
                 location: pending.location, flags: pending.flags, clickCount: pending.clickCount)
            self.pending = nil
        }
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        runLoopSource = nil
        eventTap = nil
    }

    @discardableResult func perform(action: ThreeFingerClickAction) -> Bool {
        guard shouldHandle(), pending == nil, let location = cursorLocation() else { return false }
        guard post(action: action, type: action == .middleClick ? .otherMouseDown : .leftMouseDown, location: location) else { return false }
        return post(action: action, type: action == .middleClick ? .otherMouseUp : .leftMouseUp, location: location)
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }
        switch type {
        case .leftMouseDown:
            guard threeFingerContacts.hasThreeFingerContacts() else { return Unmanaged.passUnretained(event) }
            // Reset the touch generation before routing, including when click remapping is off.
            onPhysicalClick?()
            guard remapEnabled, shouldHandle(),
                  post(action: action, type: action == .middleClick ? .otherMouseDown : .leftMouseDown,
                       location: event.location, flags: event.flags, clickCount: event.getIntegerValueField(.mouseEventClickState)) else {
                return Unmanaged.passUnretained(event)
            }
            pending = PendingClick(action: action, location: event.location, flags: event.flags, clickCount: event.getIntegerValueField(.mouseEventClickState))
            return nil
        case .leftMouseDragged:
            guard var pending else { return Unmanaged.passUnretained(event) }
            pending.location = event.location
            self.pending = pending
            post(action: pending.action, type: pending.action == .middleClick ? .otherMouseDragged : .leftMouseDragged,
                 location: event.location, flags: pending.flags, clickCount: pending.clickCount)
            return nil
        case .leftMouseUp:
            guard let pending else { return Unmanaged.passUnretained(event) }
            self.pending = nil
            post(action: pending.action, type: pending.action == .middleClick ? .otherMouseUp : .leftMouseUp,
                 location: event.location, flags: pending.flags, clickCount: pending.clickCount)
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    @discardableResult private func post(action: ThreeFingerClickAction, type: CGEventType, location: CGPoint, flags: CGEventFlags = [], clickCount: Int64 = 1) -> Bool {
        guard let source = CGEventSource(stateID: .privateState) else { return false }
        let button: CGMouseButton = action == .middleClick ? .center : .left
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: button) else { return false }
        event.flags = flags
        if action == .optionClick { event.flags.insert(.maskAlternate) }
        event.setIntegerValueField(.mouseEventClickState, value: clickCount)
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
        postEvent(event)
        return true
    }
}
