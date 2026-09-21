import CryptoKit
import XCTest
@testable import GestureCore

final class PresetFeedTests: XCTestCase {
    private let payload = Data(#"{"schemaVersion":1,"revision":7,"minimumBuild":3,"presets":[{"bundleIdentifier":"com.example.app","name":"Example","actions":{"nextTab":{"menuPaths":[["Window","Show Next Tab"]],"shortcut":null}},"rotateEnabled":true,"closeEnabled":false}]}"#.utf8)

    func testSignedFeedAcceptsDataButRejectsTamperingAndFutureBuilds() throws {
        let key = Curve25519.Signing.PrivateKey()
        let signature = try key.signature(for: payload).base64EncodedString().data(using: .utf8)!

        let feed = try PresetFeedVerifier.verify(payload: payload, signature: signature, publicKey: key.publicKey.rawRepresentation, currentBuild: 3)
        XCTAssertEqual(feed.revision, 7)
        XCTAssertEqual(feed.presets.first?.bundleIdentifier, "com.example.app")

        var tampered = payload
        tampered.append(32)
        XCTAssertThrowsError(try PresetFeedVerifier.verify(payload: tampered, signature: signature, publicKey: key.publicKey.rawRepresentation, currentBuild: 3))
        XCTAssertThrowsError(try PresetFeedVerifier.verify(payload: payload, signature: signature, publicKey: key.publicKey.rawRepresentation, currentBuild: 2))
    }

    func testSignedFeedRejectsUnknownActions() throws {
        let key = Curve25519.Signing.PrivateKey()
        let bad = Data(String(decoding: payload, as: UTF8.self).replacingOccurrences(of: "nextTab", with: "runScript").utf8)
        let signature = try key.signature(for: bad).base64EncodedString().data(using: .utf8)!
        XCTAssertThrowsError(try PresetFeedVerifier.verify(payload: bad, signature: signature, publicKey: key.publicKey.rawRepresentation, currentBuild: 3))
    }
}
