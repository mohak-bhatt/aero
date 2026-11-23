# Aero

A native macOS browser built with SwiftUI, AppKit and WebKit.

[![Build and tests](https://github.com/mohak-bhatt/aero/actions/workflows/ci.yml/badge.svg)](https://github.com/mohak-bhatt/aero/actions/workflows/ci.yml)

## Status

**0.2.0 is a preview release, not the production beta.** It ships normal and compact
vertical sidebars, split panes, tab previews, bookmarks and Live Activities.
Horizontal layouts remain in development and are disabled in the shipping UI.

The source is publicly viewable but is **not open source**. See [LICENSE](LICENSE).
The intended beta distribution is proprietary.

## Requirements and installation

- macOS **26.5 or later**; the current release artifact targets Apple Silicon.
- Download `Aero.dmg` from [Releases](https://github.com/mohak-bhatt/aero/releases).
- Open it and drag Aero to Applications. Preview builds are ad-hoc signed and are
  **not Apple-notarized**; macOS may block launch. Do not disable system-wide security
  protections. Building from source in Xcode is another way to evaluate the app.
- Checksums are included with each packaged release. They detect corruption;
  they are not a substitute for Developer ID signing and notarization.

Update checks open Aero's verified GitHub release page for manual installation.
The app shows What's New after a version change, once onboarding is complete.

## Build and test

Use Xcode 26.5 or newer with the macOS SDK. Open `Aero.xcodeproj`, select Aero / My Mac,
and run. Keep the existing signing configuration for local development.

```sh
xcodebuild -project Aero.xcodeproj -scheme Aero -configuration Debug build
bash scripts/test-core.sh
bash scripts/test-integration.sh
```

Core tests cover credential-origin, update-link and session policies. Integration
checks exercise WebKit/media, persistence, split tabs, activities and native controls.
CI runs these on macOS. Physical Force Touch, haptics, protected streaming and real
provider flows still need manual testing; a green build does not prove every feature.

## Structure

| Directory | Responsibility |
| --- | --- |
| `Aero/Browser` | Tab, session, history, credential and media models |
| `Aero/Core` | Small policies and layout persistence |
| `Aero/WebKit` | Web content hosting, navigation and event bridges |
| `Aero/UI`, `Aero/Window` | Native controls, windows and SwiftUI layouts |
| `Tests` | Core and integration regressions |
| `scripts` | Local verification and packaging |

## Known boundaries

- Full Safari extension compatibility and arbitrary-site passkeys are unfinished.
- Meeting/assistant integrations and the complete Aero Engine editor are unfinished.
- Media controls depend on website behaviour. Tab mute covers detected HTML media;
  Web Audio and protected playback are not guaranteed.
- The app process currently runs without App Sandbox; WebKit uses its own web-content
  processes. App sandbox migration and Developer ID notarization remain release blockers
  for a production beta. Do not treat this preview as security-audited.

Read the [changelog](CHANGELOG.md), [security policy](SECURITY.md),
[contribution guide](CONTRIBUTING.md) and [release procedure](docs/RELEASING.md).
