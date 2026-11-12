#!/usr/bin/env bash
# Build a reproducible unsigned IPA on a Mac. SideStore performs device signing.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-1}"
command -v xcodegen >/dev/null || { echo 'xcodegen fehlt (brew install xcodegen)' >&2; exit 2; }
command -v xcodebuild >/dev/null || { echo 'Xcode und seine Command Line Tools werden benötigt' >&2; exit 2; }
cd "$ROOT/ios"
xcodegen generate
xcodebuild -project Klar.xcodeproj -scheme Klar -configuration Release \
  -destination 'generic/platform=iOS' -sdk iphoneos \
  -derivedDataPath "$ROOT/.build/DerivedData" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  CODE_SIGNING_ALLOWED=NO build
APP="$ROOT/.build/DerivedData/Build/Products/Release-iphoneos/Klar.app"
[[ -d "$APP" ]] || { echo 'Klar.app nicht im erwarteten Pfad gefunden' >&2; exit 3; }
STAGING="$ROOT/.build/ipa-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING/Payload" "$ROOT/dist"
cp -R "$APP" "$STAGING/Payload/Klar.app"
OUTPUT="$ROOT/dist/Klar-$VERSION-build$BUILD.ipa"
rm -f "$OUTPUT"
(cd "$STAGING" && /usr/bin/zip -qr "$OUTPUT" Payload)
[[ -s "$OUTPUT" ]] || { echo 'IPA konnte nicht erstellt werden' >&2; exit 4; }
echo "Fertig gebaut: $OUTPUT"
echo 'WICHTIG: IPA muss vor dem Ausliefern über SideStore signiert und auf dem iPhone 12 getestet werden.'
