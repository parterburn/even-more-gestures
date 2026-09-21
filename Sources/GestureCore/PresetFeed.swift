import CryptoKit
import Foundation

public struct PresetFeed: Decodable {
    public let schemaVersion: Int
    public let revision: Int
    public let minimumBuild: Int
    public let presets: [AppPreset]
}

struct CachedPresetFeed: Codable {
    let payload: Data
    let signature: Data
}

public enum PresetFeedVerifier {
    public static func verify(
        payload: Data,
        signature: Data,
        publicKey: Data,
        currentBuild: Int
    ) throws -> PresetFeed {
        guard payload.count <= 512_000,
              let signatureText = String(data: signature, encoding: .utf8),
              let signatureBytes = Data(base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              key.isValidSignature(signatureBytes, for: payload) else {
            throw PresetFeedError.invalidSignature
        }

        let feed = try JSONDecoder().decode(PresetFeed.self, from: payload)
        guard feed.schemaVersion == 1,
              feed.revision > 0,
              feed.minimumBuild <= currentBuild,
              (1...200).contains(feed.presets.count) else {
            throw PresetFeedError.unsupportedFeed
        }
        var identifiers = Set<String>()
        for preset in feed.presets {
            guard (1...160).contains(preset.bundleIdentifier.count),
                  identifiers.insert(preset.bundleIdentifier).inserted,
                  (1...100).contains(preset.name.count),
                  preset.actions.count <= GestureAction.allCases.count else {
                throw PresetFeedError.invalidPreset
            }
            for (name, action) in preset.actions {
                guard GestureAction(rawValue: name) != nil,
                      action.menuPaths.count <= 8,
                      action.menuPaths.allSatisfy({ path in
                          (1...8).contains(path.count) && path.allSatisfy { (1...100).contains($0.count) }
                      }),
                      action.shortcut.map({ KeyShortcut.parse($0) != nil }) ?? true else {
                    throw PresetFeedError.invalidPreset
                }
            }
        }
        return feed
    }
}

public enum PresetFeedError: Error {
    case invalidSignature
    case unsupportedFeed
    case invalidPreset
}
