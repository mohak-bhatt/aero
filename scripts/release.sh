#!/bin/bash
# Package locally. Publishing is separate and requires an existing tested tag.
set -euo pipefail
cd "$(dirname "$0")/.."
version=${1:-}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Usage: scripts/release.sh VERSION [--publish]'; exit 1; }
mode=${2:-}
[[ -z "$mode" || "$mode" == --publish ]] || { echo 'Unknown option'; exit 1; }
out="$PWD/build/releases/$version"
mkdir -p "$out"
xcodebuild -project Aero.xcodeproj -scheme Aero -configuration Release \
  -derivedDataPath "$PWD/build/ReleasePackage" ARCHS=arm64 \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
  MARKETING_VERSION="$version" build
app="$PWD/build/ReleasePackage/Build/Products/Release/Aero.app"
actual=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
[[ "$actual" == "$version" ]] || { echo 'Version mismatch'; exit 1; }
codesign --verify --deep --strict "$app"
staging=$(mktemp -d "${TMPDIR:-/tmp}/aero-dmg.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/Aero.app"
ln -s /Applications "$staging/Applications"
ditto -c -k --keepParent "$app" "$out/Aero.zip"
hdiutil create -volname Aero -srcfolder "$staging" -ov -format UDZO "$out/Aero.dmg"
(cd "$out" && shasum -a 256 Aero.zip Aero.dmg > SHA256SUMS)
if [[ "$mode" == --publish ]]; then
  [[ -z "$(git status --porcelain --untracked-files=no)" ]] || { echo 'Commit tracked changes before publishing'; exit 1; }
  [[ "$(git rev-parse HEAD)" == "$(git rev-list -n 1 "v$version")" ]] || { echo 'Tag must match HEAD'; exit 1; }
  gh release create "v$version" "$out/Aero.zip" "$out/Aero.dmg" "$out/SHA256SUMS" \
    --repo mohak-bhatt/aero --verify-tag --prerelease --title "Aero $version" --notes-file CHANGELOG.md
fi
printf 'Packaged %s\n' "$out"
