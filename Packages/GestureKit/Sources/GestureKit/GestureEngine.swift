import Foundation

/// A contact in normalized trackpad coordinates, with positive y pointing up.
public struct TouchContact: Codable, Equatable, Sendable {
    public let id: Int32
    public let x: Double
    public let y: Double

    public init(id: Int32, x: Double, y: Double) {
        self.id = id
        self.x = x
        self.y = y
    }
}

public enum GestureEvent: String, Codable, Equatable, Sendable {
    case rotateClockwise
    case rotateCounterclockwise
    case pinchIn
    case pinchOut
    case swipeLeft
    case swipeRight
}

public struct GestureConfiguration: Codable, Equatable, Sendable {
    /// Degrees between rotation actions, clamped to the supported 20–45° range.
    public var rotationStepDegrees: Double {
        didSet { rotationStepDegrees = Self.clamped(rotationStepDegrees) }
    }

    public var pinchFingerCount: Int {
        didSet { pinchFingerCount = pinchFingerCount == 2 ? 2 : 3 }
    }

    public init(rotationStepDegrees: Double = 30, pinchFingerCount: Int = 3) {
        self.rotationStepDegrees = Self.clamped(rotationStepDegrees)
        self.pinchFingerCount = pinchFingerCount == 2 ? 2 : 3
    }

    private static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(45, max(20, value)) : 30
    }

    private enum CodingKeys: String, CodingKey { case rotationStepDegrees, pinchFingerCount }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(rotationStepDegrees: try container.decode(Double.self, forKey: .rotationStepDegrees),
                  pinchFingerCount: try container.decodeIfPresent(Int.self, forKey: .pinchFingerCount) ?? 3)
    }
}

/// A reusable recognizer. Call it from one serial owner, using monotonic seconds.
///
/// A session begins on the first contact and ends only after every contact lifts.
/// It permits fingers to land during an initial 100 ms grace period, requiring
/// the final contact set to remain stable for 50 ms. Motion during that period is
/// measured from the last additional finger's landing. Once armed, changing IDs
/// or contact count cancels the session. The caller should omit lifted contacts
/// and cancel/reset when its input source stops or changes devices.
///
/// State uses four inline contact slots; processing allocates only emitted events.
public final class GestureEngine {
    public var configuration: GestureConfiguration {
        didSet {
            // A settings change must not turn an in-progress touch into an action.
            if configuration != oldValue, state != .idle { state = .cancelled }
        }
    }

    private enum State { case idle, landing, tracking, rotating, consumed, cancelled }
    private var state: State = .idle
    private var baseline = ContactFrame()
    private var lastFrame = ContactFrame()
    private var firstTimestamp = 0.0
    private var stableTimestamp = 0.0
    private var lastTimestamp: Double?
    private var totalRotation = 0.0
    private var rotationRemainder = 0.0
    private var centroidTravel = 0.0
    private var spreadTravel = 0.0

    private static let landingGrace = 0.100
    private static let stableGrace = 0.050
    private static let rotationLock = 12.0 * Double.pi / 180
    private static let epsilon = 1e-12

    public init(configuration: GestureConfiguration = .init()) {
        self.configuration = configuration
    }

    public func reset() {
        state = .idle
        baseline = ContactFrame()
        lastFrame = ContactFrame()
        lastTimestamp = nil
        totalRotation = 0
        rotationRemainder = 0
        centroidTravel = 0
        spreadTravel = 0
    }

    public func process(contacts: [TouchContact], timestamp: Double) -> [GestureEvent] {
        contacts.withUnsafeBufferPointer { process(contacts: $0, timestamp: timestamp) }
    }

    public func process(contacts: UnsafeBufferPointer<TouchContact>, timestamp: Double) -> [GestureEvent] {
        if contacts.isEmpty {
            reset()
            return []
        }
        guard state != .cancelled, state != .consumed else { return [] }
        guard timestamp.isFinite, lastTimestamp.map({ timestamp >= $0 }) ?? true,
              let current = ContactFrame(contacts) else {
            state = .cancelled
            return []
        }
        lastTimestamp = timestamp

        if state == .idle {
            state = .landing
            firstTimestamp = timestamp
            stableTimestamp = timestamp
            baseline = current
            lastFrame = current
            return []
        }

        if state == .landing {
            if !current.hasSameIDs(as: baseline) {
                // Only additional fingers during initial landing are permissible.
                guard timestamp - firstTimestamp <= Self.landingGrace + Self.epsilon,
                      current.count > baseline.count,
                      current.containsIDs(of: baseline) else {
                    state = .cancelled
                    return []
                }
                baseline = current
                lastFrame = current
                stableTimestamp = timestamp
            }
            guard timestamp - firstTimestamp >= Self.landingGrace - Self.epsilon,
                  timestamp - stableTimestamp >= Self.stableGrace - Self.epsilon else { return [] }
            guard baseline.count >= 2, baseline.radius >= 0.015 else {
                state = .cancelled
                return []
            }
            state = .tracking
        }

        guard current.hasSameIDs(as: baseline), current.radius >= 0.005 else {
            state = .cancelled
            return []
        }

        let center = current.center
        let previousCenter = lastFrame.center
        centroidTravel += hypot(center.x - previousCenter.x, center.y - previousCenter.y)
        spreadTravel += abs(current.radius - lastFrame.radius)

        var events: [GestureEvent] = []
        switch baseline.count {
        case 2:
            let previousVector = lastFrame.vector(from: baseline.first.id, to: baseline.second.id)
            let vector = current.vector(from: baseline.first.id, to: baseline.second.id)
            // atan2(cross, dot) handles the -π/+π seam and contact reordering.
            let delta = atan2(previousVector.x * vector.y - previousVector.y * vector.x,
                              previousVector.x * vector.x + previousVector.y * vector.y)
            totalRotation += delta
            rotationRemainder += delta
            if state == .tracking, configuration.pinchFingerCount == 2 {
                guard centroidTravel < 0.08 - Self.epsilon else {
                    state = .cancelled
                    return []
                }
                let ratio = current.radius / baseline.radius
                let radialTravel = abs(current.radius - baseline.radius)
                let angularTravel = abs(totalRotation) * baseline.radius
                if radialTravel > 2 * angularTravel,
                   ratio <= 0.75 + Self.epsilon || ratio >= 1.30 - Self.epsilon {
                    state = .consumed
                    return [ratio < 1 ? .pinchIn : .pinchOut]
                }
            }
            if state == .tracking,
               abs(totalRotation) >= Self.rotationLock - Self.epsilon,
               abs(totalRotation) * baseline.radius + Self.epsilon >= 2 * max(centroidTravel, spreadTravel) {
                state = .rotating
            }
            if state == .rotating {
                let step = configuration.rotationStepDegrees * .pi / 180
                while rotationRemainder >= step - Self.epsilon {
                    events.append(.rotateCounterclockwise)
                    rotationRemainder -= step
                }
                while rotationRemainder <= -step + Self.epsilon {
                    events.append(.rotateClockwise)
                    rotationRemainder += step
                }
            }
        case 3:
            guard configuration.pinchFingerCount == 3 else { state = .cancelled; return [] }
            guard centroidTravel < 0.08 - Self.epsilon else {
                state = .cancelled
                return []
            }
            let ratio = current.radius / baseline.radius
            if ratio <= 0.75 + Self.epsilon {
                events.append(.pinchIn)
                state = .consumed
            } else if ratio >= 1.30 - Self.epsilon {
                events.append(.pinchOut)
                state = .consumed
            }
        case 4:
            let ratio = current.radius / baseline.radius
            guard ratio >= 0.85 - Self.epsilon, ratio <= 1.15 + Self.epsilon else {
                state = .cancelled
                return []
            }
            let start = baseline.center
            let dx = center.x - start.x
            let dy = center.y - start.y
            if abs(dy) >= 0.08, abs(dy) > abs(dx) {
                state = .cancelled
                return []
            }
            if abs(dx) >= 0.18 - Self.epsilon, abs(dx) + Self.epsilon >= 2 * abs(dy) {
                events.append(dx < 0 ? .swipeLeft : .swipeRight)
                state = .consumed
            }
        default:
            state = .cancelled
        }
        lastFrame = current
        return events
    }
}

private struct Point {
    var x: Double
    var y: Double
}

/// Inline storage avoids allocating/retaining framework buffers on the hot path.
private struct ContactFrame {
    private static let empty = TouchContact(id: 0, x: 0, y: 0)
    var first = Self.empty
    var second = Self.empty
    var third = Self.empty
    var fourth = Self.empty
    var count = 0

    init() {}

    init?(_ contacts: UnsafeBufferPointer<TouchContact>) {
        guard (1...4).contains(contacts.count) else { return nil }
        count = contacts.count
        for i in 0..<count {
            let contact = contacts[i]
            guard contact.x.isFinite, contact.y.isFinite,
                  (0...1).contains(contact.x), (0...1).contains(contact.y) else { return nil }
            for j in 0..<i where contacts[j].id == contact.id { return nil }
            switch i {
            case 0: first = contact
            case 1: second = contact
            case 2: third = contact
            default: fourth = contact
            }
        }
    }

    subscript(_ index: Int) -> TouchContact {
        switch index {
        case 0: return first
        case 1: return second
        case 2: return third
        default: return fourth
        }
    }

    var center: Point {
        var x = 0.0
        var y = 0.0
        for i in 0..<count {
            x += self[i].x
            y += self[i].y
        }
        return Point(x: x / Double(count), y: y / Double(count))
    }

    /// Root mean square radius treats asymmetric three-finger arrangements evenly.
    var radius: Double {
        let center = center
        var squared = 0.0
        for i in 0..<count {
            let point = self[i]
            squared += pow(point.x - center.x, 2) + pow(point.y - center.y, 2)
        }
        return sqrt(squared / Double(count))
    }

    func containsIDs(of other: ContactFrame) -> Bool {
        for i in 0..<other.count {
            var found = false
            for j in 0..<count where self[j].id == other[i].id { found = true }
            if !found { return false }
        }
        return true
    }

    func hasSameIDs(as other: ContactFrame) -> Bool {
        count == other.count && containsIDs(of: other)
    }

    func vector(from firstID: Int32, to secondID: Int32) -> Point {
        var a = Self.empty
        var b = Self.empty
        for i in 0..<count {
            if self[i].id == firstID { a = self[i] }
            if self[i].id == secondID { b = self[i] }
        }
        return Point(x: b.x - a.x, y: b.y - a.y)
    }
}
