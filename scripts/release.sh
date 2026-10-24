#!/bin/sh
# Usage: ./scripts/release.sh 0.1.1
# Builds Aero, makes Aero.dmg (for people) and Aero.zip (used by the in-app updater),
# and publishes them as a GitHub pre-release. Safe to re-run for an existing version.
set -e
VERSION="$1"
[ -z "$VERSION" ] && { echo "usage: $0 <version>"; exit 1; }

xcodebuild -scheme Aero -configuration Release -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO MARKETING_VERSION="$VERSION" clean build

APP="build/Build/Products/Release/Aero.app"

# Zip for the updater
rm -f Aero.zip
ditto -c -k --keepParent "$APP" Aero.zip

# DMG with a drag-to-Applications shortcut
rm -rf dmg-staging Aero.dmg
mkdir dmg-staging
cp -R "$APP" dmg-staging/
ln -s /Applications dmg-staging/Applications
hdiutil create -volname "Aero" -srcfolder dmg-staging -ov -format UDZO Aero.dmg
rm -rf dmg-staging

if gh release view "v$VERSION" >/dev/null 2>&1; then
  gh release upload "v$VERSION" Aero.zip Aero.dmg --clobber
else
  gh release create "v$VERSION" Aero.dmg Aero.zip --prerelease --title "Aero $VERSION" --generate-notes
fi
echo "Published v$VERSION"
