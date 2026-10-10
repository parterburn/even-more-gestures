# Releasing Even More Gestures

## Configure API authentication for notarization

In [App Store Connect](https://appstoreconnect.apple.com/access/integrations/api), select the Dabble Dev LLC team and create a Team API key under Users and Access → Integrations → App Store Connect API. Download its `.p8` private key and record the Key ID and Issuer ID. The key can be downloaded only once; keep it securely outside this repository.

Store and validate the credentials in the local macOS Keychain:

```sh
xcrun notarytool store-credentials "EvenMoreGestures-API" \
  --key "/absolute/path/to/AuthKey_YOUR_KEY_ID.p8" \
  --key-id "YOUR_KEY_ID" \
  --issuer "YOUR_ISSUER_ID"
xcrun notarytool history --keychain-profile "EvenMoreGestures-API"
```

The release scripts use `EvenMoreGestures-API` by default. Set `NOTARY_PROFILE` to use another configured profile. No Apple ID or app-specific password is needed. This authenticates notarization for Developer ID distribution; it does not publish the app to the Mac App Store.

See Apple's [API key setup](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api) and [notarytool guidance](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool).

## Prepare and publish a release

1. Set the marketing version and monotonically increasing build number.
2. Create brief Markdown release notes.
3. Run the following from a clean checkout:

   ```sh
   APP_VERSION=0.2.0 BUILD_NUMBER=3 RELEASE_NOTES_FILE=release-notes.md ./Scripts/prepare-release.sh
   ```

   The script builds with Developer ID, submits to the configured Notary profile, staples and Gatekeeper-checks the app, creates a versioned ZIP, and generates a signed Sparkle appcast using the private key in the local Keychain.

4. Create GitHub release `v0.2.0`, then upload the versioned ZIP from `build/release/` for Sparkle and an identical copy named `Even-More-Gestures.zip` for the public download link. Upload the generated DMG and an identical copy named `Even-More-Gestures.dmg` for the drag-to-Applications installer. The stable URLs are `https://github.com/parterburn/even-more-gestures/releases/latest/download/Even-More-Gestures.zip` and `https://github.com/parterburn/even-more-gestures/releases/latest/download/Even-More-Gestures.dmg`.
5. Commit and push the generated `docs/appcast.xml`.
6. Verify the public raw GitHub appcast plus the release-asset URL. Use the app’s “Check for Updates…” item from an older build to test the full path.

Do not commit an App Store Connect `.p8` private key, the Sparkle private key, an Apple app-specific password, a Notary credential, or a stapled ZIP. Every release archive gets its own Sparkle signature, so altering or recompressing it after appcast generation invalidates the update.
