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
