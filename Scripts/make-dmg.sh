#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 APP_PATH OUTPUT_DMG" >&2
  exit 1
fi

APP="$1"
OUTPUT="$2"
STAGING="$(mktemp -d /private/tmp/even-more-gestures-dmg.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "$STAGING/Even More Gestures"
ditto "$APP" "$STAGING/Even More Gestures/Even More Gestures.app"
ln -s /Applications "$STAGING/Even More Gestures/Applications"
hdiutil create -volname "Even More Gestures" -srcfolder "$STAGING/Even More Gestures" -format UDZO -ov "$OUTPUT"
