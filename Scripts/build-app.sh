#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${CONFIGURATION:-release}"
APP_VERSION="${APP_VERSION:-0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-3}"
swift build -c "$CONFIG" --disable-sandbox --cache-path .build/cache --scratch-path .build
BIN_DIR="$(swift build -c "$CONFIG" --disable-sandbox --cache-path .build/cache --scratch-path .build --show-bin-path)"
APP="$PWD/build/Even More Gestures.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/EvenMoreGestures" "$APP/Contents/MacOS/EvenMoreGestures"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
SPARKLE_FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$SPARKLE_FRAMEWORK"
for bundle in "$BIN_DIR"/*.bundle; do
  if [ -d "$bundle" ]; then cp -R "$bundle" "$APP/Contents/Resources/"; fi
done
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.evenmoregestures.mac</string>
<key>CFBundleName</key><string>Even More Gestures</string>
<key>CFBundleDisplayName</key><string>Even More Gestures</string>
<key>CFBundleExecutable</key><string>EvenMoreGestures</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>SUFeedURL</key><string>https://parterburn.github.io/even-more-gestures/appcast.xml</string>
<key>SUPublicEDKey</key><string>RoSrowPtFb/PhBMWEDZC1VrMl2hIedfWpqBVSL5XwIE=</string>
<key>SUEnableAutomaticChecks</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026. All rights reserved.</string>
</dict></plist>
PLIST
plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
# Prefer an explicit identity, then automatically use an installed Developer ID.
# Set REQUIRE_DEVELOPER_ID=1 for release jobs so they cannot silently fall back
# to an ad-hoc signature.
IDENTITY="${SIGNING_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application:/ { print $2; exit }')"
fi

if [ -n "$IDENTITY" ]; then
  for nested in "$SPARKLE_FRAMEWORK/Versions/Current/Autoupdate" \
                "$SPARKLE_FRAMEWORK/Versions/Current/Updater.app" \
                "$SPARKLE_FRAMEWORK/Versions/Current/XPCServices/Downloader.xpc" \
                "$SPARKLE_FRAMEWORK/Versions/Current/XPCServices/Installer.xpc"; do
    codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$IDENTITY" "$nested"
  done
  codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$IDENTITY" "$SPARKLE_FRAMEWORK"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
  echo "Signed with: $IDENTITY"
elif [ "${REQUIRE_DEVELOPER_ID:-0}" = "1" ]; then
  echo "error: no Developer ID Application identity is installed in the login keychain" >&2
  exit 1
else
  codesign --force --deep --sign - "$SPARKLE_FRAMEWORK"
  codesign --force --sign - "$APP"
  echo "Signed ad hoc (local development only)"
fi
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
