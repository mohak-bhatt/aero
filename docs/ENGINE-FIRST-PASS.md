# Aero Engine — first pass (0.3.0)

Open **Aero → Customise Browser…** in the actual browser. Engine is opt-in; existing
installations keep the original sidebar until they choose it. Settings → Engine →
Return to original sidebar is the escape hatch.

## Delivered
- Seventeen stable elements: layout, back, forward, address, reload/stop, page menu,
  favourites, pins, tabs, new tab, Live Activities, downloads, bookmarks, share,
  history, settings and updates.
- Drag elements to left/right/top/bottom edges or before another element. A picker
  and move-earlier/later buttons provide a non-drag alternative.
- Standard and compact edge presets, optional-element hiding, larger controls,
  reset, undo/redo and Cancel. Changes persist; Cancel restores the edit-session
  starting configuration. Address, tabs and layout remain reachable.
- The same native/glass controls render in both orientations. Tab rows and tiles,
  navigation arrows, page menu, address field and utilities reuse existing views.
- Existing tab context menus, split numbering, media controls and tab dragging
  remain connected to the browser model. Actual page bounds inform split dragging.
- The welcome tour now selects Engine presets and opens the live editor, with
  skip/replay and reduced-motion support inherited from the tour.

## Why this layout
Edge-only placement prevents controls covering webpage content. Controls wrap or
scroll when space is short, with a reserved page-width budget. Stable IDs and a
validated schema prevent duplicate controls or an unusable empty navigation area.
Editing temporarily intercepts control clicks to prevent accidental navigation.
The bottom tray leaves the live browser visible rather than replacing it with a
mock customization page. Collections such as tabs and activities remain semantic
components; their changing internal contents are not arbitrary toolbar elements.

## Validation and limits
The Debug and Release builds pass. Automated checks cover configuration recovery,
duplicate IDs, essential controls, independent movement, persistence, undo/redo,
cancel and every docking edge, alongside existing browser regressions.

This is a functional first pass, not completed interaction/visual acceptance.
Hardware gesture feel and every narrow/fullscreen layout need hands-on iteration.
Cross-window live synchronization, export/import, nested grouping, external themes,
resizable element widths and comprehensive keyboard drag equivalents are deferred.
Onboarding videos and a complete visual redesign are deferred; this pass connects
onboarding to the real Engine instead of presenting an inert customization screen.

## Release signing correction
0.2.2 used ad-hoc signatures with hardened library validation and could fail before
startup when loading Sparkle. Packaging now requires a certificate identity and
executes a launch check in addition to signature verification. The 0.3.0 DMG's
app and framework use the same development team; this remains a non-notarized
preview, not a Developer ID production distribution. Production beta still needs
Developer ID signing, notarization and the security gates in NEXT-STEPS.md.
