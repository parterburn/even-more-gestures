import AppKit
let identifier = "app.evenmoregestures.mac"
let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
for app in running {
    let policy: String
    switch app.activationPolicy { case .accessory: policy = "accessory (no Dock icon)"; case .regular: policy = "regular (Dock icon)"; default: policy = "prohibited" }
    print("\(app.localizedName ?? identifier): pid=\(app.processIdentifier), policy=\(policy)")
    print("Bundle: \(app.bundleURL?.path ?? "unknown")")
}
if running.isEmpty { print("App is not running"); exit(1) }
if running.contains(where: { $0.activationPolicy != .accessory }) { exit(2) }
