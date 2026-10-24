# Aero

A native macOS browser built with SwiftUI, AppKit and WebKit — Liquid Glass, horizontal or vertical tabs,
pinned tabs, favorites, bookmarks, address-bar suggestions, per-site zoom, and in-app updates.

**Requirements:** macOS 13+ (Liquid Glass effects need macOS 26 and Xcode 26), Xcode to build.

## Build
1. Open `Aero.xcodeproj` in Xcode and press ⌘R.
2. Signing & Capabilities → App Sandbox: enable Outgoing Connections (Client), Downloads Folder (Read/Write)
   and User Selected File (Read/Write) — or turn the sandbox off for personal alpha builds.

## Releasing an update
See [docs/RELEASING.md](docs/RELEASING.md).
