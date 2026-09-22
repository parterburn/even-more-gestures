# Releasing Even More Gestures

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

Do not commit the Sparkle private key, an Apple app-specific password, a Notary credential, or a stapled ZIP. Every release archive gets its own Sparkle signature, so altering or recompressing it after appcast generation invalidates the update.
