# Changelog

## 0.2.0 — 2026-11-23 (preview)

### Added and improved
- Compact Vertical: a 52-point rail, vertical native window controls, bidirectional
  resize snapping and a press-and-hold layout menu.
- Interactive hover previews with titles and close controls for open normal, pinned
  and favourite tabs; shared tab menus and split-pane numbering.
- Favourite-to-tab split actions and blue mute badges for detected HTML media.
- A compact, opaque swipe menu for timers, clocks, history, bookmarks, downloads
  and settings; distinct feedback for menu settling, navigation and reload.
- Compact Live Activity indicators with hover expansion, media transport, artwork,
  progress, dismissal and stale-tab cleanup.
- Pull-to-refresh at the page top with threshold feedback, plus favicon-preserving
  tab loading rings and a smoother reload/stop transition.
- Appearance-aware website tinting and quieter split-pane framing.
- In-app What's New for this version; horizontal layouts hidden from shipping menus.

### Reliability and repository foundations
- Credential origin checks and Keychain-backed password storage.
- Verified repository release links instead of silent executable replacement.
- Core/integration regression suites, macOS CI, contribution and private security
  reporting guidance, ownership and dependency update configuration.

### Known limitations
This is an ad-hoc signed, non-notarized Apple Silicon preview requiring macOS 26.5+.
App Sandbox migration, full extension/passkey support, provider-specific meeting/AI
activities, and the complete Engine editor are not finished. Physical haptics,
Force Touch and fullscreen transitions need hardware acceptance. Web Audio muting
and protected media are not guaranteed. See README.md and SECURITY.md.
