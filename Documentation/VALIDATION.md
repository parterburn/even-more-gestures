# Validation — 2026-09-21

## Automated

- Root Swift package: **8 passing XCTest tests** for presets, signed remote defaults, shortcut parsing, and safe fallback behavior.
- Gesture/app state package: **3 passing XCTest tests** for pause and undo behavior.
- GestureKit: **19 passing XCTest tests**.
- Total: **30 tests, zero failures**.
- Release app successfully compiled for macOS 14 with Xcode 27 / Swift 6.4.
- `codesign --verify --deep --strict` and stapler validation pass on the `0.2.15 (18)` Developer ID-signed bundle with hardened runtime and secure timestamps, including the embedded Sparkle framework.
- `Info.plist` declares `LSUIElement = true`, so the app stays out of the Dock, plus a Sparkle appcast URL and public update key.
- The signed defaults feed was generated from the bundled presets and verified with Sparkle’s signing tool. Feed-parser tests reject tampering, unknown actions, and future-only builds.

## Product and UI checks

- The current app build opens with the Accessibility requirement above its Gestures / Apps / General tabs. It has no ambiguous “Setup needed” pill.
- Its menu-bar menu sends a person without permission to the setup screen instead of trying to pause inactive gestures.
- The setup steps explain the macOS-owned toggle and open the exact Accessibility pane. They do not promise the app can grant its own permission.
- The Gestures screen provides the requested two- or three-finger pinch/spread choice below Haptic feedback.
- ChatGPT, Maps, and Chrome defaults are present: `⌘B` / `⌘⌥B`, `⌘⌃S`, and `⌘⇧L` respectively.
- The General screen describes Sparkle updates and signed daily defaults rather than a local-development preview.
- The public landing page was visually checked at desktop size and a 390 px phone viewport. Its product images are captures of the current app build.

## Distribution status

- The `0.2.15` build was accepted by Apple’s Notary service and stapled. Its GitHub Release archive is Sparkle-signed and listed in the repository appcast.
- The repository includes a public appcast and signed defaults feed. The app reads those exact files over GitHub's raw HTTPS content service; GitHub Pages is an optional human-readable mirror.
- The Gumroad product page uses its native fair-price checkout, with the copy and exact image files documented in `Documentation/GUMROAD.md`.

## Limits needing real-device validation

- Built-in and Magic Trackpad calibration, false-trigger rate, and sensitivity across slow/fast gestures, palms, typing, sleep/wake, and multiple displays.
- Current macOS and Intel runtime coverage; the current build was exercised on Apple silicon macOS 27.
- Live verification of every bundled menu path as app versions change.
- Idle CPU, memory, latency, and energy measurements.

The private multitouch framework and assistive Accessibility API make this a direct-download app, not a Mac App Store app. The test suite establishes deterministic recognition behavior; it does not synthesize physical trackpad input.
