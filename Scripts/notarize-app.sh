#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$PWD/build/Even More Gestures.app"
UPLOAD_ARCHIVE="$PWD/build/Even More Gestures-upload.zip"
ARCHIVE="$PWD/build/Even More Gestures.zip"
RESULT="$PWD/build/notarization-submission.plist"
PROFILE="${NOTARY_PROFILE:-EvenMoreGestures}"

if [ ! -d "$APP" ]; then
  echo "error: build the app first with REQUIRE_DEVELOPER_ID=1 ./Scripts/build-app.sh" >&2
  exit 1
fi

codesign --verify --deep --strict "$APP"
TEAM_ID="$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
if [ "$TEAM_ID" != "B79A4CAS56" ]; then
  echo "error: expected a Developer ID signature for Dabble Dev LLC (B79A4CAS56)" >&2
  exit 1
fi
SIGNATURE_DETAILS="$(codesign -dv --verbose=4 "$APP" 2>&1)"
if [[ "$SIGNATURE_DETAILS" != *'Authority=Developer ID Application: Dabble Dev LLC (Co) (B79A4CAS56)'* ]]; then
  echo "error: app is not signed with the Dabble Dev LLC Developer ID Application certificate" >&2
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$PROFILE" --output-format plist >/dev/null; then
  echo "error: configure a valid Notary service Keychain profile named $PROFILE first" >&2
  exit 1
fi

rm -f "$UPLOAD_ARCHIVE" "$ARCHIVE"
ditto -c -k --keepParent --sequesterRsrc "$APP" "$UPLOAD_ARCHIVE"
xcrun notarytool submit "$UPLOAD_ARCHIVE" --keychain-profile "$PROFILE" --wait --output-format plist > "$RESULT"
STATUS="$(plutil -extract status raw -o - "$RESULT")"
if [ "$STATUS" != "Accepted" ]; then
  echo "error: notarization status is $STATUS; see $RESULT" >&2
  exit 1
fi

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict "$APP"
spctl --assess --type execute --verbose=4 "$APP"

# Package the stapled app for distribution; the upload archive is not a release.
ditto -c -k --keepParent --sequesterRsrc "$APP" "$ARCHIVE"
rm "$UPLOAD_ARCHIVE"
echo "Notarized app: $APP"
echo "Distribution archive: $ARCHIVE"
