import XCTest
@testable import AppLogic

final class SafetyStateTests: XCTestCase {
    func testUndoIsProcessScopedAndExpiresAtThreeSeconds() {
        var state = UndoWindow()
        let start = Date(timeIntervalSince1970: 100)
        state.didClose(pid: 12, supportsReopen: true, now: start)
        XCTAssertTrue(state.shouldReopen(pid: 12, now: start.addingTimeInterval(2.999)))
        XCTAssertFalse(state.shouldReopen(pid: 13, now: start))
        XCTAssertFalse(state.shouldReopen(pid: 12, now: start.addingTimeInterval(3)))
        state.clear()
        XCTAssertFalse(state.shouldReopen(pid: 12, now: start))
    }
    func testUnsupportedCloseClearsExistingUndo() {
        var state = UndoWindow()
        state.didClose(pid: 12, supportsReopen: true)
        state.didClose(pid: 12, supportsReopen: false)
        XCTAssertFalse(state.shouldReopen(pid: 12))
    }
    func testTimedPauseExpiresAndTogglingResumesImmediately() {
        var state = PauseState()
        let start = Date(timeIntervalSince1970: 100)
        state.pauseForHour(now: start)
        XCTAssertTrue(state.isPaused(at: start.addingTimeInterval(3599)))
        XCTAssertEqual(state.remainingTime(at: start.addingTimeInterval(3570)), 30)
        XCTAssertFalse(state.isPaused(at: start.addingTimeInterval(3600)))
        XCTAssertNil(state.remainingTime(at: start.addingTimeInterval(3600)))
        state.toggle(now: start)
        XCTAssertFalse(state.isPaused(at: start))
        state.toggle(now: start)
        XCTAssertTrue(state.isPaused(at: start.addingTimeInterval(99999)))
    }
}
