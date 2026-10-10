import XCTest
@testable import GestureKit

final class ThreeFingerTapTests: XCTestCase {
    private let points = [
        TouchContact(id: 1, x: 0.3, y: 0.4),
        TouchContact(id: 2, x: 0.5, y: 0.6),
        TouchContact(id: 3, x: 0.7, y: 0.4)
    ]

    func testStaggeredLandingAndLiftingRecognizesOnce() {
        let tap = ThreeFingerTapRecognizer()
        XCTAssertFalse(tap.process(contacts: Array(points.prefix(1)), timestamp: 0))
        XCTAssertFalse(tap.process(contacts: Array(points.prefix(1)), timestamp: 0.01))
        XCTAssertFalse(tap.process(contacts: Array(points.prefix(2)), timestamp: 0.03))
        XCTAssertFalse(tap.process(contacts: points, timestamp: 0.06))
        XCTAssertFalse(tap.process(contacts: Array(points.suffix(2)), timestamp: 0.12))
        XCTAssertFalse(tap.process(contacts: Array(points.suffix(1)), timestamp: 0.14))
        XCTAssertTrue(tap.process(contacts: [], timestamp: 0.16))
        XCTAssertFalse(tap.process(contacts: [], timestamp: 0.17))
    }

    func testInvalidContactsCannotBecomeATapOnLift() {
        for invalid in [
            [points[0], points[0], points[2]],
            [TouchContact(id: 1, x: .nan, y: 0.4), points[1], points[2]],
            [TouchContact(id: 1, x: 1.1, y: 0.4), points[1], points[2]]
        ] {
            let tap = ThreeFingerTapRecognizer()
            XCTAssertFalse(tap.process(contacts: invalid, timestamp: 0))
            XCTAssertFalse(tap.process(contacts: [], timestamp: 0.1))
        }
    }

    func testLiftingCannotAddAContactBackOrReplaceIt() {
        for returning in [points, [points[1], TouchContact(id: 9, x: 0.7, y: 0.4)]] {
            let tap = ThreeFingerTapRecognizer()
            _ = tap.process(contacts: points, timestamp: 0)
            _ = tap.process(contacts: Array(points.suffix(2)), timestamp: 0.1)
            _ = tap.process(contacts: returning, timestamp: 0.12)
            XCTAssertFalse(tap.process(contacts: [], timestamp: 0.16))
        }
    }
}
