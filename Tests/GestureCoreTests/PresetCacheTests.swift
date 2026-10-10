import CryptoKit
import XCTest
@testable import GestureCore

final class PresetCacheTests: XCTestCase {
    @MainActor func testAppUpdateKeepsBundledDefaultsAcrossRepeatedLaunches() throws {
        let suite = "PresetCacheTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = Curve25519.Signing.PrivateKey()
        let payload = Data(#"{"schemaVersion":1,"revision":7,"minimumBuild":3,"presets":[{"bundleIdentifier":"com.example.old","name":"Old defaults","actions":{},"rotateEnabled":true,"closeEnabled":true}]}"#.utf8)
        let signature = Data(try key.signature(for: payload).base64EncodedString().utf8)
        let cache = try JSONSerialization.data(withJSONObject: [
            "payload": payload.base64EncodedString(), "signature": signature.base64EncodedString(), "build": 3
        ])
        try cache.write(to: directory.appendingPathComponent("presets-cache.json"))
        defaults.set(3, forKey: "presetsCacheBuild")
        let file = directory.appendingPathComponent("overrides.json")

        // The verified cache works on the build that downloaded it.
        let original = PresetStore(file: file, appBuild: 3, publicKey: key.publicKey.rawRepresentation, defaults: defaults)
        XCTAssertNotNil(original.preset(for: "com.example.old"))
        // An update must not restore the stale cache on its second launch.
        for _ in 0..<2 {
            let updated = PresetStore(file: file, appBuild: 4, publicKey: key.publicKey.rawRepresentation, defaults: defaults)
            XCTAssertNil(updated.preset(for: "com.example.old"))
            XCTAssertNotNil(updated.preset(for: "com.apple.Safari"))
        }
    }
}
