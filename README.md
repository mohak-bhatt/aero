# Aero

A native macOS browser built with SwiftUI, AppKit and WebKit — Liquid Glass, horizontal or vertical tabs,
pinned tabs, favorites, bookmarks, address-bar suggestions, per-site zoom, and in-app updates.

## Install (no Xcode needed)
1. Go to the **[Releases](../../releases)** page and download **Aero.dmg** from the latest release.
2. Open the DMG and drag **Aero** onto the **Applications** shortcut.
3. Eject the DMG, then open **Aero** from Applications.
4. The first launch is blocked because this alpha isn't notarized by Apple. Do **one** of these:
   - **macOS 15 or later:** try to open Aero, click *Done*, then open **System Settings → Privacy & Security**,
     scroll down and click **Open Anyway** next to "Aero", then confirm.
   - **Older macOS:** right-click Aero → **Open** → **Open**.
   - **Or in Terminal:** `xattr -dr com.apple.quarantine /Applications/Aero.app`
5. Follow the short welcome tour. Aero updates itself: when a blue **Update Now** button appears in the
   sidebar, click it. You can also use **Aero → About Aero → Check for Updates**.

**Requirements:** macOS 13 or later (the Liquid Glass look needs macOS 26).

## Build from source (developers only)
1. Open `Aero.xcodeproj` in Xcode and press ⌘R.
2. Signing & Capabilities → App Sandbox: enable Outgoing Connections (Client), Downloads Folder (Read/Write)
   and User Selected File (Read/Write) — or turn the sandbox off for personal alpha builds.

## Releasing an update
See [docs/RELEASING.md](docs/RELEASING.md).
