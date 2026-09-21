# Releasing Even More Gestures

1. Set the marketing version and monotonically increasing build number.
2. Create brief Markdown release notes.
3. Run the following from a clean checkout:

   ```sh
   APP_VERSION=0.2.0 BUILD_NUMBER=3 RELEASE_NOTES_FILE=release-notes.md ./Scripts/prepare-release.sh
   ```

   The script builds with Developer ID, submits to the configured Notary profile, staples and Gatekeeper-checks the app, creates a versioned ZIP, and generates a signed Sparkle appcast using the private key in the local Keychain.

4. Create GitHub release `v0.2.0`, then upload the ZIP from `build/release/`.
5. Commit and push the generated `docs/appcast.xml`.
6. Wait for GitHub Pages and verify the published appcast plus the release-asset URL. Use the app’s “Check for Updates…” item from an older build to test the full path.

Do not commit the Sparkle private key, an Apple app-specific password, a Notary credential, or a stapled ZIP. Every release archive gets its own Sparkle signature, so altering or recompressing it after appcast generation invalidates the update.
