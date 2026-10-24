#!/bin/sh
# Usage: ./scripts/release.sh 0.1.1
set -e
VERSION="$1"
[ -z "$VERSION" ] && { echo "usage: $0 <version>"; exit 1; }

xcodebuild -scheme Aero -configuration Release -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO MARKETING_VERSION="$VERSION" clean build

rm -f Aero.zip
ditto -c -k --keepParent build/Build/Products/Release/Aero.app Aero.zip
gh release create "v$VERSION" Aero.zip --prerelease --title "Aero $VERSION" --generate-notes
echo "Published v$VERSION"
