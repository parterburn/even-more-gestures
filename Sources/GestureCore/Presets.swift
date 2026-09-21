import AppKit
import Combine

public enum GestureAction: String, Codable, CaseIterable, Identifiable {
    case nextTab, previousTab, closeTab, newTab, reopenClosedTab, toggleLeftSidebar, toggleRightSidebar
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .nextTab: return "Next tab"
        case .previousTab: return "Previous tab"
        case .closeTab: return "Close tab"
        case .newTab: return "New tab / Quick Open"
        case .reopenClosedTab: return "Reopen closed tab"
        case .toggleLeftSidebar: return "Left sidebar"
        case .toggleRightSidebar: return "Right sidebar"
        }
    }
}
public struct PresetAction: Codable, Equatable {
    public var menuPaths: [[String]]
    public var shortcut: String?
    public init(_ paths: [[String]] = [], keys: String? = nil) { menuPaths = paths; shortcut = keys }
}
public struct AppPreset: Codable, Identifiable {
    public var bundleIdentifier: String
    public var name: String
    public var actions: [String: PresetAction]
    public var rotateEnabled: Bool
    public var closeEnabled: Bool
    public var id: String { bundleIdentifier }
}
public enum ActionOverride: Codable, Equatable {
    case useDefault, off, custom(String)
}
public struct AppOverride: Codable {
    public var name: String?
    public var enabled = true
    public var actions: [String: ActionOverride] = [:]
    public init(name: String? = nil) { self.name = name }
}
public typealias ActionPlan = PresetAction

@MainActor public final class PresetStore: ObservableObject {
    @Published public private(set) var presets: [AppPreset] = []
    @Published public private(set) var overrides: [String: AppOverride] = [:]
    @Published public private(set) var error: String?
    private let file: URL
    private let cacheFile: URL
    private var currentRevision = 0
    private let feedURL = URL(string: "https://parterburn.github.io/even-more-gestures/defaults/stable.json")!
    private let signatureURL = URL(string: "https://parterburn.github.io/even-more-gestures/defaults/stable.sig")!
    public init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Even More Gestures/overrides.json")
        cacheFile = self.file.deletingLastPathComponent().appendingPathComponent("presets-cache.json")
        do {
            let url = Bundle.module.url(forResource: "presets", withExtension: "json")!
            presets = try JSONDecoder().decode([AppPreset].self, from: Data(contentsOf: url))
            if FileManager.default.fileExists(atPath: self.file.path) {
                overrides = try JSONDecoder().decode([String: AppOverride].self, from: Data(contentsOf: self.file))
            }
        } catch { self.error = "Could not load settings: \(error.localizedDescription)" }
        if let cache = try? JSONDecoder().decode(CachedPresetFeed.self, from: Data(contentsOf: cacheFile)),
           let feed = try? verify(cache.payload, signature: cache.signature) {
            presets = feed.presets
            currentRevision = feed.revision
        }
    }
    private func verify(_ payload: Data, signature: Data) throws -> PresetFeed {
        guard let encodedKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let publicKey = Data(base64Encoded: encodedKey) else {
            throw PresetFeedError.invalidSignature
        }
        let build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
        return try PresetFeedVerifier.verify(payload: payload, signature: signature, publicKey: publicKey, currentBuild: build)
    }
    public func refreshDefaultsIfNeeded(force: Bool = false) async {
        let defaults = UserDefaults.standard
        let now = Date()
        let lastAttempt = defaults.object(forKey: "presetsLastAttempt") as? Date ?? .distantPast
        let lastSuccess = defaults.object(forKey: "presetsLastSuccess") as? Date ?? .distantPast
        guard force || now.timeIntervalSince(lastAttempt) >= 3600 && now.timeIntervalSince(lastSuccess) >= 86400 else { return }
        defaults.set(now, forKey: "presetsLastAttempt")
        do {
            async let payload = download(feedURL, maximumBytes: 512_000)
            async let signature = download(signatureURL, maximumBytes: 1024)
            let receivedPayload = try await payload
            let receivedSignature = try await signature
            let feed = try verify(receivedPayload, signature: receivedSignature)
            if feed.revision > currentRevision {
                let cache = CachedPresetFeed(payload: receivedPayload, signature: receivedSignature)
                try FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(cache).write(to: cacheFile, options: .atomic)
                presets = feed.presets
                currentRevision = feed.revision
            }
            defaults.set(Date(), forKey: "presetsLastSuccess")
        } catch {
            // Retain the last verified cache, or the bundle's offline defaults.
        }
    }
    private func download(_ url: URL, maximumBytes: Int) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= maximumBytes else {
            throw PresetFeedError.unsupportedFeed
        }
        return data
    }
    public func isEnabled(bundleIdentifier: String) -> Bool { overrides[bundleIdentifier]?.enabled ?? true }
    public func setEnabled(_ enabled: Bool, bundleIdentifier: String) {
        var item = overrides[bundleIdentifier] ?? .init(); item.enabled = enabled
        overrides[bundleIdentifier] = item; save()
    }
    public func addApp(bundleIdentifier: String, name: String) {
        if overrides[bundleIdentifier] == nil { overrides[bundleIdentifier] = .init(name: name); save() }
    }
    public func overrideMode(action: GestureAction, bundleIdentifier: String) -> ActionOverride {
        overrides[bundleIdentifier]?.actions[action.rawValue] ?? .useDefault
    }
    public func setOverride(_ value: ActionOverride, action: GestureAction, bundleIdentifier: String) {
        var item = overrides[bundleIdentifier] ?? .init()
        item.actions[action.rawValue] = value; overrides[bundleIdentifier] = item; save()
    }
    public func preset(for bundle: String) -> AppPreset? { presets.first { $0.id == bundle } }
    public func plan(action: GestureAction, bundleIdentifier: String) -> ActionPlan? {
        guard isEnabled(bundleIdentifier: bundleIdentifier) else { return nil }
        switch overrideMode(action: action, bundleIdentifier: bundleIdentifier) {
        case .off: return nil
        case .custom(let keys): return KeyShortcut.parse(keys) == nil ? nil : PresetAction(keys: keys)
        case .useDefault: break
        }
        if let preset = preset(for: bundleIdentifier) {
            if [.nextTab, .previousTab].contains(action), !preset.rotateEnabled { return nil }
            if action == .closeTab, !preset.closeEnabled { return nil }
            return preset.actions[action.rawValue]
        }
        // Only menu-backed, native tab navigation is safe for unknown apps.
        switch action {
        case .nextTab: return PresetAction([["Window", "Show Next Tab"]])
        case .previousTab: return PresetAction([["Window", "Show Previous Tab"]])
        default: return nil
        }
    }
    public var resolvedPlans: [String: [GestureAction: ActionPlan]] {
        var result: [String: [GestureAction: ActionPlan]] = [:]
        for bundle in Set(presets.map(\.id) + Array(overrides.keys)) {
            result[bundle] = Dictionary(uniqueKeysWithValues: GestureAction.allCases.compactMap { action in
                plan(action: action, bundleIdentifier: bundle).map { (action, $0) }
            })
        }
        return result
    }
    private func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(overrides).write(to: file, options: .atomic); error = nil
        } catch { self.error = "Could not save settings: \(error.localizedDescription)" }
    }
}
