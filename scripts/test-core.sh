#!/bin/bash
# Direct XCTest runner for environments where SwiftPM cannot start its manifest helper.
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/aero-core-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
sdk_path=$(xcrun --sdk macosx --show-sdk-path)
platform_path=$(xcrun --sdk macosx --show-sdk-platform-path)
framework_path="$platform_path/Developer/Library/Frameworks"
swiftc -module-cache-path "$test_dir/cache" -sdk "$sdk_path" \
  -emit-library -emit-module -enable-testing -module-name AeroCore \
  Aero/Core/PasswordOriginPolicy.swift Aero/Core/UpdatePolicy.swift Aero/Browser/SessionStore.swift \
  -emit-module-path "$test_dir/AeroCore.swiftmodule" -o "$test_dir/libAeroCore.dylib"
swiftc -module-cache-path "$test_dir/cache" -sdk "$sdk_path" \
  -I "$platform_path/Developer/usr/lib" -L "$platform_path/Developer/usr/lib" -I "$test_dir" -L "$test_dir" -lAeroCore -F "$framework_path" \
  -Xlinker -rpath -Xlinker "$test_dir" -Xlinker -rpath -Xlinker "$framework_path" -Xlinker -rpath -Xlinker "$platform_path/Developer/usr/lib" \
  Tests/AeroCoreTests/*.swift Tests/Runner/main.swift -o "$test_dir/AeroCoreTests"
"$test_dir/AeroCoreTests"
