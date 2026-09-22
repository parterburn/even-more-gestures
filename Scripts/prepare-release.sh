#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${APP_VERSION:?Set APP_VERSION, for example 0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:?Set BUILD_NUMBER, for example 3}"
APP_NAME="Even-More-Gestures-${VERSION}.zip"
DMG_NAME="Even-More-Gestures-${VERSION}.dmg"
ARCHIVE_DIR="$PWD/build/release/$VERSION"
ARCHIVE="$ARCHIVE_DIR/$APP_NAME"
DMG="$ARCHIVE_DIR/$DMG_NAME"
APPCAST="$ARCHIVE_DIR/appcast.xml"
APPCAST_INPUT="$(mktemp -d /private/tmp/even-more-gestures-appcast.XXXXXX)"
GENERATOR="$PWD/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
DOWNLOAD_PREFIX="https://github.com/parterburn/even-more-gestures/releases/download/v${VERSION}/"
trap 'rm -rf "$APPCAST_INPUT"' EXIT

REQUIRE_DEVELOPER_ID=1 APP_VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" ./Scripts/build-app.sh
./Scripts/notarize-app.sh

if [ -e "$ARCHIVE" ] || [ -e "$DMG" ] || [ -e "$APPCAST" ]; then
  echo "error: release artifacts for $VERSION already exist" >&2
  exit 1
fi

mkdir -p "$ARCHIVE_DIR"
ditto "$PWD/build/Even More Gestures.zip" "$ARCHIVE"
bash ./Scripts/make-dmg.sh "$PWD/build/Even More Gestures.app" "$DMG"

if [ -n "${RELEASE_NOTES_FILE:-}" ]; then
  cp "$RELEASE_NOTES_FILE" "${ARCHIVE%.zip}.md"
fi

cp "$ARCHIVE" "$APPCAST_INPUT/$APP_NAME"
if [ -n "${RELEASE_NOTES_FILE:-}" ]; then
  cp "$RELEASE_NOTES_FILE" "$APPCAST_INPUT/${APP_NAME%.zip}.md"
fi

"$GENERATOR" \
  --versions "$BUILD_NUMBER" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --link "https://paularterburn.com/even-more-gestures/" \
  --embed-release-notes \
  -o "$APPCAST" \
  "$APPCAST_INPUT"

cp "$APPCAST" docs/appcast.xml

cat <<EOF
Release prepared.

1. Create GitHub release v$VERSION and upload:
   $ARCHIVE
   $DMG
2. Commit and push docs/appcast.xml.
3. Check https://raw.githubusercontent.com/parterburn/even-more-gestures/main/docs/appcast.xml.

The appcast references the GitHub release asset and carries the Sparkle signature.
EOF
