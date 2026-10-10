import Foundation

/// Recognizes a short, stationary three-finger touch after every contact lifts.
/// Fingers may land and lift over multiple frames. Call it from the same serial
/// owner as `GestureEngine`.
public final class ThreeFingerTapRecognizer {
    private enum State { case idle, landing, tracking, lifting, cancelled }
    private var state: State = .idle
    private var firstTimestamp = 0.0
    private var lastTimestamp: Double?
    private var baseline = ContactFrame()
    private var lastFrame = ContactFrame()

    private static let landingGrace = 0.100
    private static let maximumDuration = 0.300
    private static let maximumTravel = 0.025

    public init() {}

    /// Consume this touch until every finger lifts when another gesture has fired.
    public func cancel() { state = .cancelled }

    public func reset() {
        state = .idle
        lastTimestamp = nil
        baseline = ContactFrame()
        lastFrame = ContactFrame()
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
            return (state == .tracking || state == .lifting) && timestamp - firstTimestamp <= Self.maximumDuration
        }
        guard contacts.count <= 3, let current = ContactFrame(contacts) else {
            state = .cancelled
            return false
        }

        switch state {
        case .idle:
            firstTimestamp = timestamp
            baseline = current
            state = current.count == 3 ? .tracking : .landing
        case .landing:
            guard timestamp - firstTimestamp <= Self.landingGrace,
                  current.containsIDs(of: baseline), isStationary(current, relativeTo: baseline) else {
                state = .cancelled
                return false
            }
            if current.count > baseline.count { baseline = landingFrame(current) }
            if current.count == 3 { state = .tracking }
        case .tracking, .lifting:
            guard timestamp - firstTimestamp <= Self.maximumDuration,
                  lastFrame.containsIDs(of: current), isStationary(current, relativeTo: baseline) else {
                state = .cancelled
                return false
            }
            if current.count < 3 { state = .lifting }
        case .cancelled:
            return false
        }
        lastFrame = current
        return false
    }

    private func landingFrame(_ current: ContactFrame) -> ContactFrame {
        // Retain each finger's initial position as others arrive.
        var merged = current
        for i in 0..<current.count {
            for j in 0..<baseline.count where baseline[j].id == current[i].id {
                switch i {
                case 0: merged.first = baseline[j]
                case 1: merged.second = baseline[j]
                default: merged.third = baseline[j]
                }
            }
        }
        return merged
    }

    private func isStationary(_ current: ContactFrame, relativeTo baseline: ContactFrame) -> Bool {
        for i in 0..<current.count {
            let contact = current[i]
            for j in 0..<baseline.count where baseline[j].id == contact.id {
                if hypot(contact.x - baseline[j].x, contact.y - baseline[j].y) > Self.maximumTravel { return false }
            }
        }
        return true
    }
}
