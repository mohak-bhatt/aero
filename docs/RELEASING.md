# Release procedure

1. Review the complete diff for user data, credentials, generated binaries and unrelated changes.
2. Update MARKETING_VERSION / CURRENT_PROJECT_VERSION, CHANGELOG.md and WhatsNew.release.
3. Build Debug and Release; run both test scripts and targeted UI acceptance.
4. Publish only after maintainer authorization. Tag the tested commit; never force-move a tag.
5. Package the Release app as Aero.zip and Aero.dmg; include SHA256SUMS.
6. Publish explicit release notes and supported OS/architecture/signing limitations.
7. Verify the remote tag, artifacts and CI. Keep preview releases marked prerelease.

Production beta additionally requires App Sandbox review, Developer ID signing,
notarization, verified update delivery and independent security review. Do not claim
these are satisfied by a successful build or checksums.

## Signed update feed
The Xcode target pins Sparkle 2.10.1. Its Ed25519 private signing key lives in the
release Mac's Keychain; never export it into the repository or logs. The public
key is embedded in Info.plist. Use Sparkle's `sign_update` on the exact published
ZIP and add its signature, byte length, build number and HTTPS release URL to
`appcast.xml`. Publish the release asset before updating the feed. Never mutate
an already published archive without signing and testing the replacement.

Versions 0.2.0 and 0.2.1 open a release page instead of running an installer. They
require one manual migration to a Sparkle-enabled build. Preserve the installed
bundle's location (including AeroX.app) and user data. Do not call the migration
complete until a disposable installed copy has successfully updated and relaunched,
and a tampered archive is rejected. Signing an archive does not notarize the app.
