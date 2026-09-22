import XCTest
@testable import GestureKit

final class GestureEngineTests: XCTestCase {
    func pair(_ degrees: Double, radius: Double = 0.15, x: Double = 0.5, y: Double = 0.5) -> [TouchContact] {
        let a = degrees * .pi / 180
        return [.init(id:1,x:x+cos(a)*radius,y:y+sin(a)*radius),.init(id:2,x:x-cos(a)*radius,y:y-sin(a)*radius)]
    }
    func cluster(_ n: Int, scale: Double = 1, x: Double = 0.5, y: Double = 0.5) -> [TouchContact] {
        (0..<n).map { i in let a = Double(i)*2 * .pi / Double(n); return .init(id:Int32(i+1),x:x+cos(a)*0.12*scale,y:y+sin(a)*0.12*scale) }
    }
    func arm(_ engine: GestureEngine, _ points: [TouchContact]) {
        XCTAssertEqual(engine.process(contacts:points,timestamp:0),[])
        XCTAssertEqual(engine.process(contacts:points,timestamp:0.11),[])
    }
    func testClockwiseAndCounterclockwiseDetentsAndReverse() {
        let e = GestureEngine(); arm(e,pair(0))
        XCTAssertEqual(e.process(contacts:pair(-30),timestamp:0.2),[.rotateClockwise])
        XCTAssertEqual(e.process(contacts:pair(-90),timestamp:0.3),[.rotateClockwise,.rotateClockwise])
        XCTAssertEqual(e.process(contacts:pair(-60),timestamp:0.4),[.rotateCounterclockwise])
    }
    func testAngleWrapAndContactOrder() {
        let e = GestureEngine(); arm(e,pair(170))
        XCTAssertEqual(e.process(contacts:pair(200).reversed(),timestamp:0.2),[.rotateCounterclockwise])
    }
    func testBothPinchesFireOnce() {
        for (scale,event) in [(0.75,GestureEvent.pinchIn),(1.30,.pinchOut)] {
            let e = GestureEngine(); arm(e,cluster(3))
            XCTAssertEqual(e.process(contacts:cluster(3,scale:scale),timestamp:0.2),[event])
            XCTAssertEqual(e.process(contacts:cluster(3,scale:scale),timestamp:0.3),[])
        }
    }
    func testBothHorizontalSwipesFireOnce() {
        for (x,event) in [(0.32,GestureEvent.swipeLeft),(0.68,.swipeRight)] {
            let e = GestureEngine(); arm(e,cluster(4))
            XCTAssertEqual(e.process(contacts:cluster(4,x:x),timestamp:0.2),[event])
            XCTAssertEqual(e.process(contacts:cluster(4,x:x),timestamp:0.3),[])
        }
    }
    func testScrollAndZoomNeverRotate() {
        let e = GestureEngine(); arm(e,pair(0))
        XCTAssertEqual(e.process(contacts:pair(0,x:0.7),timestamp:0.2),[])
        XCTAssertEqual(e.process(contacts:pair(5,radius:0.25,x:0.7),timestamp:0.3),[])
    }
    func testThreeFingerTranslationCancelsPinch() {
        let e = GestureEngine(); arm(e,cluster(3))
        XCTAssertEqual(e.process(contacts:cluster(3,x:0.59),timestamp:0.2),[])
        XCTAssertEqual(e.process(contacts:cluster(3,scale:0.5),timestamp:0.3),[])
    }
    func testVerticalSwipeCannotTurnIntoSidebar() {
        let e = GestureEngine(); arm(e,cluster(4))
        XCTAssertEqual(e.process(contacts:cluster(4,y:0.7),timestamp:0.2),[])
        XCTAssertEqual(e.process(contacts:cluster(4,x:0.75),timestamp:0.3),[])
    }
    func testFourFingerSpreadCancelsSidebar() {
        let e = GestureEngine(); arm(e,cluster(4))
        XCTAssertEqual(e.process(contacts:cluster(4,scale:1.2),timestamp:0.2),[])
        XCTAssertEqual(e.process(contacts:cluster(4,x:0.75),timestamp:0.3),[])
    }
    func testFourthFingerCancelsPinchUntilCompleteLift() {
        let e = GestureEngine(); arm(e,cluster(3))
        XCTAssertEqual(e.process(contacts:cluster(4),timestamp:0.2),[])
        XCTAssertEqual(e.process(contacts:cluster(3,scale:0.5),timestamp:0.3),[])
        XCTAssertEqual(e.process(contacts:[],timestamp:0.4),[])
        XCTAssertEqual(e.process(contacts:cluster(3),timestamp:0.5),[])
        XCTAssertEqual(e.process(contacts:cluster(3,scale:0.5),timestamp:0.7),[.pinchIn])
    }
    func testStaggeredFingerLandingIsAllowedOnlyBeforeArming() {
        let e = GestureEngine(); let points = cluster(3)
        XCTAssertEqual(e.process(contacts:Array(points.prefix(1)),timestamp:0),[])
        XCTAssertEqual(e.process(contacts:Array(points.prefix(2)),timestamp:0.03),[])
        XCTAssertEqual(e.process(contacts:points,timestamp:0.07),[])
        XCTAssertEqual(e.process(contacts:cluster(3,scale:0.7),timestamp:0.14),[.pinchIn])
    }
    func testIdentityReplacementAndPalmsCancel() {
        let e = GestureEngine(); arm(e,pair(0))
        let replacement = [TouchContact(id:4,x:0.65,y:0.5),TouchContact(id:2,x:0.35,y:0.5)]
        XCTAssertEqual(e.process(contacts:replacement,timestamp:0.2),[])
        XCTAssertEqual(e.process(contacts:pair(40),timestamp:0.3),[])
        let palm = GestureEngine(); XCTAssertEqual(palm.process(contacts:cluster(5),timestamp:0),[])
        XCTAssertEqual(palm.process(contacts:cluster(3,scale:0.5),timestamp:0.2),[])
    }
    func testInvalidInputAndConfigurationFailClosed() {
        let e = GestureEngine(); arm(e,pair(0))
        XCTAssertEqual(e.process(contacts:[.init(id:1,x:.nan,y:0),.init(id:2,x:0.4,y:0.4)],timestamp:0.2),[])
        XCTAssertEqual(e.process(contacts:pair(50),timestamp:0.3),[])
        XCTAssertEqual(GestureConfiguration(rotationStepDegrees: .infinity).rotationStepDegrees,30)
        XCTAssertEqual(GestureConfiguration(rotationStepDegrees: 4).rotationStepDegrees,20)
        XCTAssertEqual(GestureConfiguration(rotationStepDegrees: 50).rotationStepDegrees,45)
    }
    func testConfigurationChangeCancelsInFlightSession() {
        let e = GestureEngine(); arm(e,pair(0))
        e.configuration.rotationStepDegrees = 20
        XCTAssertEqual(e.process(contacts:pair(40),timestamp:0.2),[])
    }
    func testTwoFingerPinchAndSpreadAreOptIn() {
        for (radius,event) in [(0.11,GestureEvent.pinchIn),(0.20,.pinchOut)] {
            let enabled = GestureEngine(configuration:.init(pinchFingerCount:2)); arm(enabled,pair(0))
            XCTAssertEqual(enabled.process(contacts:pair(0,radius:radius),timestamp:0.2),[event])
            XCTAssertEqual(enabled.process(contacts:pair(0,radius:radius),timestamp:0.3),[])
            let standard = GestureEngine(); arm(standard,pair(0))
            XCTAssertEqual(standard.process(contacts:pair(0,radius:radius),timestamp:0.2),[])
        }
    }
    func testThreeFingerTapRecognizesOnlyAQuickStationaryTouch() {
        let tap = ThreeFingerTapRecognizer()
        let points = cluster(3)
        XCTAssertFalse(tap.process(contacts: points, timestamp: 0))
        XCTAssertFalse(tap.process(contacts: points, timestamp: 0.12))
        XCTAssertTrue(tap.process(contacts: [], timestamp: 0.18))

        XCTAssertFalse(tap.process(contacts: points, timestamp: 1))
        XCTAssertFalse(tap.process(contacts: cluster(3, x: 0.56), timestamp: 1.12))
        XCTAssertFalse(tap.process(contacts: [], timestamp: 1.18))

        XCTAssertFalse(tap.process(contacts: points, timestamp: 2))
        XCTAssertFalse(tap.process(contacts: points, timestamp: 2.35))
        XCTAssertFalse(tap.process(contacts: [], timestamp: 2.36))
    }
    func testThreeFingerPinchIsDisabledInTwoFingerMode() {
        let e = GestureEngine(configuration:.init(pinchFingerCount:2)); arm(e,cluster(3))
        XCTAssertEqual(e.process(contacts:cluster(3,scale:0.5),timestamp:0.2),[])
    }
    func testTwoFingerRotationWinsOnceLocked() {
        let e = GestureEngine(configuration:.init(pinchFingerCount:2)); arm(e,pair(0))
        XCTAssertEqual(e.process(contacts:pair(15),timestamp:0.2),[])
        XCTAssertEqual(e.process(contacts:pair(30,radius:0.1),timestamp:0.3),[.rotateCounterclockwise])
    }
    func testTwoFingerScrollAndAddedContactCancelPinch() {
        let scroll = GestureEngine(configuration:.init(pinchFingerCount:2)); arm(scroll,pair(0))
        XCTAssertEqual(scroll.process(contacts:pair(0,x:0.65),timestamp:0.2),[])
        XCTAssertEqual(scroll.process(contacts:pair(0,radius:0.09,x:0.65),timestamp:0.3),[])
        let extra = GestureEngine(configuration:.init(pinchFingerCount:2)); arm(extra,pair(0))
        XCTAssertEqual(extra.process(contacts:cluster(3),timestamp:0.2),[])
        XCTAssertEqual(extra.process(contacts:pair(0,radius:0.09),timestamp:0.3),[])
    }
    func testChangingPinchCountCancelsAndOldConfigurationDecodes() throws {
        let e = GestureEngine(); arm(e,pair(0)); e.configuration.pinchFingerCount = 2
        XCTAssertEqual(e.process(contacts:pair(0,radius:0.09),timestamp:0.2),[])
        let old = try JSONDecoder().decode(GestureConfiguration.self,from:Data(#"{"rotationStepDegrees":30}"#.utf8))
        XCTAssertEqual(old.pinchFingerCount,3)
    }
    func testSyntheticFixtureReplay() throws {
        struct Frame: Decodable { let timestamp:Double; let contacts:[TouchContact] }
        struct Fixture: Decodable { let frames:[Frame]; let expected:[GestureEvent] }
        let url = try XCTUnwrap(Bundle.module.url(forResource:"clockwise",withExtension:"json"))
        let f = try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:url)); let e = GestureEngine()
        XCTAssertEqual(f.frames.flatMap { e.process(contacts:$0.contacts,timestamp:$0.timestamp) },f.expected)
    }
}
