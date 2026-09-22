import Foundation

/// Recognizes a short, stationary three-finger touch. It never emits until all
/// contacts lift, so pinches, drags, and four-finger gestures keep their normal
/// behavior. Call it from the same serial owner as `GestureEngine`.
public final class ThreeFingerTapRecognizer {
    private enum State { case idle, landing, tracking, cancelled }
    private var state: State = .idle
    private var firstTimestamp = 0.0
    private var lastTimestamp: Double?
    private var first = TouchContact(id: 0, x: 0, y: 0)
    private var second = TouchContact(id: 0, x: 0, y: 0)
    private var third = TouchContact(id: 0, x: 0, y: 0)

    private static let landingGrace = 0.100
    private static let maximumDuration = 0.300
    private static let maximumTravel = 0.025

    public init() {}

    public func reset() {
        state = .idle
        lastTimestamp = nil
    }

    public func process(contacts: [TouchContact], timestamp: Double) -> Bool {
        contacts.withUnsafeBufferPointer { process(contacts: $0, timestamp: timestamp) }
    }

    public func process(contacts: UnsafeBufferPointer<TouchContact>, timestamp: Double) -> Bool {
        guard timestamp.isFinite, lastTimestamp.map({ timestamp >= $0 }) ?? true else {
            state = .cancelled
            return false
        }
        lastTimestamp = timestamp

        if contacts.isEmpty {
            defer { reset() }
            return state == .tracking && timestamp - firstTimestamp <= Self.maximumDuration
        }

        guard contacts.count <= 3 else { state = .cancelled; return false }
        switch state {
        case .idle:
            firstTimestamp = timestamp
            state = contacts.count == 3 ? .tracking : .landing
            if contacts.count == 3 { capture(contacts) }
        case .landing:
            guard timestamp - firstTimestamp <= Self.landingGrace, contacts.count == 3 else {
                state = .cancelled
                return false
            }
            capture(contacts)
            state = .tracking
        case .tracking:
            guard timestamp - firstTimestamp <= Self.maximumDuration, isStationary(contacts) else {
                state = .cancelled
                return false
            }
        case .cancelled:
            return false
        }
        return false
    }

    private func capture(_ contacts: UnsafeBufferPointer<TouchContact>) {
        first = contacts[0]
        second = contacts[1]
        third = contacts[2]
    }

    private func isStationary(_ contacts: UnsafeBufferPointer<TouchContact>) -> Bool {
        guard contacts.count == 3 else { return false }
        for expected in [first, second, third] {
            guard let current = contacts.first(where: { $0.id == expected.id }),
                  hypot(current.x - expected.x, current.y - expected.y) <= Self.maximumTravel else { return false }
        }
        return true
    }
}
