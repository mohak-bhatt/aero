# Aero roadmap after 0.2.1

## Update recovery — current priority
Cause confirmed: 0.2.0/0.2.1's Update Now opens a release page; it does not install.
Sparkle 2.10.1 is now integrated locally with an embedded public verification key,
a signed seed appcast and Keychain-held private key. Debug build and 147 regression
checks pass; independent signature testing accepts the original ZIP and rejects a
modified archive. Disposable renamed-app installation and isolated relaunch passed; modified archives were rejected. Migration build 0.2.2 is prepared. The user’s AeroX has not been replaced.

Remaining acceptance gates: interrupted downloads, permission failures and real browser session/preferences restoration. Then publish a migration build and signed feed together. Old
0.2.0/0.2.1 installations need one manual migration; do not promise the broken updater
can bootstrap itself. Resume browser/Engine milestones after this gate.

## 1. Stabilise the shipping vertical browser
Gate: hardware acceptance of swipe menu, pull-to-refresh, both history directions,
Force Touch, fullscreen traffic lights and resizing; no double haptics, wrong-arrow
animation, cancelled-gesture action or tab/media state loss. Cover ordinary, pinned,
favourite and split tabs. Test installed AeroX separately from the Xcode build.
Record OS, hardware, reproduction steps and results. Do not call automated tests
proof of physical feedback.

## 2. Establish the beta security boundary
Audit credential origin matching, imports, script messaging, downloads and update
verification. Migrate to App Sandbox with explicit file access; obtain Developer ID
signing and notarization. Validate WebAuthn/passkeys against real relying parties.
Investigate extension APIs with a capability spike before promising Safari extension
compatibility. Gate: documented threat model, regression coverage and external review.

## 3. Finish Live Activities as one component
Use stable IDs, explicit lifecycle, editing/dismissal and restoration rules. Complete
media reliability and multiple simultaneous activities first. Meetings need dedicated
provider adapters for mic, camera and leave actions, never generic video commands.
AI completion/usage indicators must use supported, verifiable signals; unavailable
usage remains unavailable. Gate: provider failure, navigation and tab-close tests.

## 4. Build Aero Engine around the real browser
First formalise layout schema, versioned persistence, constraints, undo/reset and
accessible keyboard editing. Support classic/compact vertical and left/right docks.
Then implement in-place drag/drop customization with valid targets, overflow handling,
minimum sizes and safe escape/reset. Keep horizontal code experimental until feature
parity is verified. Gate: every preset survives resize, fullscreen and relaunch without
losing access to navigation, tabs or activities.

## 5. Rebuild onboarding around that working Engine
One focused feature per immersive page, actual captured demonstrations, reduced-motion
alternatives and skip/replay. Let users choose a preset and edit the actual browser.
Imports must explain real supported data and permissions, never promise silent password
access. Gate: fresh-install and returning-user tests; no forced repeat onboarding.

## 6. Aero Intelligence after the platform is stable
Agree explicit jobs and privacy boundaries before implementation. Begin with opt-in
page summarization and user-approved actions, provider/key management and clear costs.
Treat webpage content as untrusted; isolate secrets and require confirmation for
external side effects. Gate: adversarial page tests, cancellation and data-deletion flows.

Release discipline: small tested patches, green CI, matching in-app notes, signed
artifacts when available, and explicit distinction between automated and hardware QA.
