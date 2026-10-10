import AppKit
import GestureKit
import TouchBridge
import XCTest
@testable import EvenMoreGestures

final class ClickInputTests: XCTestCase {
    private func event(_ type: CGEventType, at location: CGPoint = CGPoint(x: 200, y: 300)) -> CGEvent {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: .left)!
        event.flags = [.maskShift]
        event.setIntegerValueField(.mouseEventClickState, value: 2)
        return event
    }

    func testDisabledAppPassesPhysicalClickThroughAndBlocksTap() {
        let contacts = ThreeFingerContactState()
        contacts.update(device: 1, count: 3)
        let controller = ThreeFingerClickController(threeFingerContacts: contacts)
        controller.shouldHandle = { false }
        var posted: [CGEvent] = []
        controller.postEvent = { posted.append($0) }
        XCTAssertNotNil(controller.handle(type: .leftMouseDown, event: event(.leftMouseDown)))
        XCTAssertNotNil(controller.handle(type: .leftMouseUp, event: event(.leftMouseUp)))
        XCTAssertFalse(controller.perform(action: .middleClick))
        XCTAssertTrue(posted.isEmpty)
    }

    func testTapUsesQuartzCursorLocationForBothEvents() {
        let controller = ThreeFingerClickController(threeFingerContacts: ThreeFingerContactState())
        controller.shouldHandle = { true }
        let location = CGPoint(x: -300, y: 1200)
        controller.cursorLocation = { location }
        var posted: [CGEvent] = []
        controller.postEvent = { posted.append($0) }
        XCTAssertTrue(controller.perform(action: .middleClick))
        XCTAssertEqual(posted.map(\.type), [.otherMouseDown, .otherMouseUp])
        XCTAssertEqual(posted.map(\.location), [location, location])
    }

    func testClickKeepsOriginalButtonAndModifiersAcrossSettingsChangesAndDrags() {
        let contacts = ThreeFingerContactState()
        contacts.update(device: 1, count: 3)
        let controller = ThreeFingerClickController(threeFingerContacts: contacts)
        controller.shouldHandle = { true }
        var posted: [CGEvent] = []
        controller.postEvent = { posted.append($0) }
        XCTAssertNil(controller.handle(type: .leftMouseDown, event: event(.leftMouseDown)))
        controller.action = .optionClick
        controller.remapEnabled = false
        controller.shouldHandle = { false }
        contacts.reset()
        XCTAssertNil(controller.handle(type: .leftMouseDragged, event: event(.leftMouseDragged, at: CGPoint(x: 220, y: 310))))
        XCTAssertNil(controller.handle(type: .leftMouseUp, event: event(.leftMouseUp)))
        XCTAssertEqual(posted.map(\.type), [.otherMouseDown, .otherMouseDragged, .otherMouseUp])
        XCTAssertTrue(posted.allSatisfy { $0.flags == .maskShift })
        XCTAssertTrue(posted.allSatisfy { $0.getIntegerValueField(.mouseEventClickState) == 2 })
    }

    func testStoppingInputReleasesAnInterceptedButton() {
        let contacts = ThreeFingerContactState()
        contacts.update(device: 1, count: 3)
        let controller = ThreeFingerClickController(threeFingerContacts: contacts)
        controller.shouldHandle = { true }
        controller.action = .optionClick
        var posted: [CGEvent] = []
        controller.postEvent = { posted.append($0) }
        XCTAssertNil(controller.handle(type: .leftMouseDown, event: event(.leftMouseDown)))
        controller.stop()
        controller.stop()
        XCTAssertEqual(posted.map(\.type), [.leftMouseDown, .leftMouseUp])
        XCTAssertTrue(posted.allSatisfy { $0.flags.contains([.maskShift, .maskAlternate]) })
    }

    func testPhysicalClickCancelsTapEvenWhenClickRemappingIsOff() {
        let contacts = ThreeFingerContactState()
        let processor = FrameProcessor(threeFingerContacts: contacts)
        let controller = ThreeFingerClickController(threeFingerContacts: contacts)
        controller.remapEnabled = false
        var generation: UInt64 = 1
        var taps = 0
        processor.deliverTap = { _ in taps += 1 }
        controller.onPhysicalClick = { generation += 1 }
        let points = [
            EMGContact(id: 1, x: 0.3, y: 0.4),
            EMGContact(id: 2, x: 0.5, y: 0.6),
            EMGContact(id: 3, x: 0.7, y: 0.4)
        ]
        func frame(_ points: [EMGContact], time: Double) {
            points.withUnsafeBufferPointer {
                processor.process(device: 1, contacts: $0.baseAddress, count: Int32($0.count), timestamp: time,
                                  generation: generation, rotation: 30, pinchFingers: 2)
            }
        }
        frame(points, time: 0)
        XCTAssertNotNil(controller.handle(type: .leftMouseDown, event: event(.leftMouseDown)))
        frame([], time: 0.1)
        XCTAssertEqual(taps, 0)
        frame(points, time: 1)
        frame([], time: 1.1)
        XCTAssertEqual(taps, 1)
    }

    func testSyntheticOptionClickDoesNotInterceptItself() {
        let contacts = ThreeFingerContactState()
        contacts.update(device: 1, count: 3)
        let controller = ThreeFingerClickController(threeFingerContacts: contacts)
        controller.shouldHandle = { true }
        controller.action = .optionClick
        controller.postEvent = { [weak controller] synthetic in
            XCTAssertNotNil(controller?.handle(type: synthetic.type, event: synthetic))
        }
        XCTAssertNil(controller.handle(type: .leftMouseDown, event: event(.leftMouseDown)))
        XCTAssertNil(controller.handle(type: .leftMouseUp, event: event(.leftMouseUp)))
    }

    func testSmallThreeFingerPinchCannotAlsoBecomeATap() {
        let processor = FrameProcessor(threeFingerContacts: ThreeFingerContactState())
        var gestures: [GestureEvent] = []
        var taps = 0
        processor.deliver = { gesture, _ in gestures.append(gesture) }
        processor.deliverTap = { _ in taps += 1 }
        func frame(radius: Double?, time: Double) {
            let points: [EMGContact] = radius.map { r in
                [EMGContact(id: 1, x: 0.5 - r, y: 0.5), EMGContact(id: 2, x: 0.5 + r, y: 0.5), EMGContact(id: 3, x: 0.5, y: 0.5 + r)]
            } ?? []
            points.withUnsafeBufferPointer {
                processor.process(device: 1, contacts: $0.baseAddress, count: Int32($0.count), timestamp: time,
                                  generation: 1, rotation: 30, pinchFingers: 3)
            }
        }
        frame(radius: 0.05, time: 0)
        frame(radius: 0.035, time: 0.1)
        frame(radius: nil, time: 0.15)
        XCTAssertEqual(gestures, [.pinchIn])
        XCTAssertEqual(taps, 0)
    }

    func testMalformedThreeFingerFrameCannotRemapAClick() {
        let contacts = ThreeFingerContactState()
        let processor = FrameProcessor(threeFingerContacts: contacts)
        let points = [EMGContact(id: 1, x: .nan, y: 0.4), EMGContact(id: 2, x: 0.5, y: 0.6), EMGContact(id: 3, x: 0.7, y: 0.4)]
        points.withUnsafeBufferPointer {
            processor.process(device: 1, contacts: $0.baseAddress, count: 3, timestamp: 0,
                              generation: 1, rotation: 30, pinchFingers: 2)
        }
        XCTAssertFalse(contacts.hasThreeFingerContacts())
    }
}
