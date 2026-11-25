#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
command -v xcodebuild >/dev/null
if [[ ! -d Veltrix.xcodeproj ]]; then
  command -v xcodegen >/dev/null
  xcodegen generate --spec project.yml
fi

build="$PWD/build"
mkdir -p "$build"
derived="$build/ReleaseDerived"
xcodebuild build -project Veltrix.xcodeproj -scheme Veltrix -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$derived" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""

app="$derived/Build/Products/Release-iphoneos/Veltrix.app"
executable="$app/Veltrix"
/usr/bin/plutil -lint "$app/Info.plist"
test "$(xcrun lipo -archs "$executable")" = "arm64"
test "$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$app/Info.plist")" = "16.0"
build_metadata="$(xcrun vtool -show-build "$executable")"
grep -Eq 'platform[[:space:]]+IOS([[:space:]]|$)' <<< "$build_metadata"
grep -Eq 'minos[[:space:]]+16\.0([[:space:]]|$)' <<< "$build_metadata"
test ! -e "$app/embedded.mobileprovision"
test ! -d "$app/_CodeSignature"

staging="$(mktemp -d "$build/ipa.XXXXXXXX")"
trap 'rm -rf -- "$staging"' EXIT
mkdir "$staging/Payload"
/usr/bin/ditto "$app" "$staging/Payload/Veltrix.app"
(cd "$staging" && /usr/bin/zip -qry Veltrix.ipa Payload)
/usr/bin/unzip -tq "$staging/Veltrix.ipa"
/usr/bin/unzip -p "$staging/Veltrix.ipa" Payload/Veltrix.app/Info.plist > "$staging/Info.plist"
/usr/bin/plutil -lint "$staging/Info.plist"
/usr/bin/unzip -p "$staging/Veltrix.ipa" Payload/Veltrix.app/Veltrix > "$staging/Veltrix"
cmp "$executable" "$staging/Veltrix"
mv -f "$staging/Veltrix.ipa" "$build/Veltrix.ipa"
(cd "$build" && shasum -a 256 Veltrix.ipa > Veltrix.ipa.sha256)
