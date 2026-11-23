#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/IntegrationTests
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(find Aero -name '*.swift' ! -name AeroApp.swift)
sdk_path=$(xcrun --sdk macosx --show-sdk-path)
swiftc -swift-version 5 -default-isolation MainActor -parse-as-library \
  -target arm64-apple-macosx26.5 -sdk "$sdk_path" -module-cache-path build/IntegrationTests/cache \
  "${sources[@]}" Tests/Integration/BrowserRegression.swift -o build/IntegrationTests/BrowserRegression
build/IntegrationTests/BrowserRegression
