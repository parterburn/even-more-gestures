import Foundation

/// Undo belongs to the process that actually closed the tab, never just an app name.
public struct UndoWindow {
    private var pending: (pid: Int32, deadline: Date)?
    public init() {}
    public mutating func didClose(pid: Int32, supportsReopen: Bool, now: Date = Date()) {
        pending = supportsReopen ? (pid, now.addingTimeInterval(3)) : nil
    }
    public func shouldReopen(pid: Int32, now: Date = Date()) -> Bool {
        guard let pending else { return false }
        return pending.pid == pid && now < pending.deadline
    }
    public mutating func clear() { pending = nil }
}

public struct PauseState {
    public var indefinitely = false
    public var until: Date?
    public init() {}
    public func isPaused(at date: Date = Date()) -> Bool {
        indefinitely || (until.map { date < $0 } ?? false)
    }
    public mutating func pauseForHour(now: Date = Date()) {
        indefinitely = false
        until = now.addingTimeInterval(3600)
    }
    public mutating func toggle(now: Date = Date()) {
        indefinitely = !isPaused(at: now)
        until = nil
    }
    public mutating func resume() { indefinitely = false; until = nil }
}
