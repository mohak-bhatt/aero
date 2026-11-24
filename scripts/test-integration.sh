#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/IntegrationTests
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(find Aero -name '*.swift' ! -name AeroApp.swift)
xcodebuild -resolvePackageDependencies -project Aero.xcodeproj -scheme Aero -derivedDataPath build/Updater >/dev/null
sparkle_framework=$(find build/Updater/SourcePackages/artifacts -type d -name Sparkle.framework -print -quit)
[[ -n "$sparkle_framework" ]] || { echo 'Sparkle framework missing'; exit 1; }
framework_dir=$(dirname "$sparkle_framework")
sdk_path=$(xcrun --sdk macosx --show-sdk-path)
swiftc -swift-version 5 -default-isolation MainActor -parse-as-library \
  -target arm64-apple-macosx26.5 -sdk "$sdk_path" -module-cache-path build/IntegrationTests/cache \
  -F "$framework_dir" -framework Sparkle -Xlinker -rpath -Xlinker "$framework_dir" \
  "${sources[@]}" Tests/Integration/BrowserRegression.swift -o build/IntegrationTests/BrowserRegression
build/IntegrationTests/BrowserRegression
