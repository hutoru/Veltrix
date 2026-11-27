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
test "$(/usr/libexec/PlistBuddy -c 'Print :UILaunchStoryboardName' "$app/Info.plist")" = "LaunchScreen"
test -n "$(find "$app" -type d -name LaunchScreen.storyboardc -print -quit)"
test "$(xcrun lipo -archs "$executable")" = "arm64"
test "$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$app/Info.plist")" = "16.0"
version="$(sed -n 's/^[[:space:]]*MARKETING_VERSION: "\([0-9.]*\)".*/\1/p' project.yml)"
test -n "$version"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist")" = "$version"
build_number="$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION: \([0-9][0-9]*\).*/\1/p' project.yml)"
test -n "$build_number"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist")" = "$build_number"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")" = "app.veltrix.simulation"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName' "$app/Info.plist")" = "AppIcon"
test -s "$app/Assets.car"
for icon in VXWhite VXMidnight VXTitanium VXCarbon VXGold VXOcean VXMono; do
  /usr/libexec/PlistBuddy -c "Print :CFBundleIcons:CFBundleAlternateIcons:$icon" "$app/Info.plist" >/dev/null
done
widget="$app/PlugIns/VeltrixWidgets.appex"
test "$(xcrun lipo -archs "$widget/VeltrixWidgets")" = "arm64"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$widget/Info.plist")" = "app.veltrix.simulation.widgets"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$widget/Info.plist")" = "$build_number"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$widget/Info.plist")" = "$version"
source_icon="$PWD/Veltrix/Resources/Assets.xcassets/AppIcon.appiconset/VeltrixIcon.png"
compiled_icon="$(find "$app" -maxdepth 1 -name 'AppIcon*.png' -size +0c -print -quit)"
test -n "$compiled_icon"
xcrun swift - "$source_icon" "$app"/AppIcon*.png <<'SWIFT'
import AppKit

for (index, filename) in CommandLine.arguments.dropFirst().enumerated() {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: filename)),
          let bitmap = NSBitmapImageRep(data: data) else {
        fatalError("Cannot decode \(filename)")
    }
    if index == 0 {
        precondition(bitmap.pixelsWide == 1024 && bitmap.pixelsHigh == 1024)
    }
    let step = max(1, bitmap.pixelsWide / 80)
    var whiteSeen = false
    for y in stride(from: 0, to: bitmap.pixelsHigh, by: step) {
        for x in stride(from: 0, to: bitmap.pixelsWide, by: step) {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                fatalError("Cannot read icon color")
            }
            precondition(abs(color.redComponent - color.greenComponent) < 0.02)
            precondition(abs(color.redComponent - color.blueComponent) < 0.02)
            if x == 0 || y == 0 { precondition(color.redComponent < 0.02) }
            if color.redComponent > 0.95 { whiteSeen = true }
        }
    }
    precondition(whiteSeen, "Missing white icon mark")
    print("Verified monochrome app icon: \(filename)")
}
SWIFT
build_metadata="$(xcrun vtool -show-build "$executable")"
grep -Eq 'platform[[:space:]]+IOS([[:space:]]|$)' <<< "$build_metadata"
grep -Eq 'minos[[:space:]]+16\.0([[:space:]]|$)' <<< "$build_metadata"
test ! -e "$app/embedded.mobileprovision"
test ! -d "$app/_CodeSignature"

staging="$(mktemp -d "$build/ipa.XXXXXXXX")"
trap 'rm -rf -- "$staging"' EXIT
ipa="VELTRIX-$version-Experience.ipa"
mkdir "$staging/Payload"
/usr/bin/ditto "$app" "$staging/Payload/Veltrix.app"
(cd "$staging" && /usr/bin/zip -qry "$ipa" Payload)
/usr/bin/unzip -tq "$staging/$ipa"
/usr/bin/unzip -p "$staging/$ipa" Payload/Veltrix.app/Info.plist > "$staging/Info.plist"
/usr/bin/plutil -lint "$staging/Info.plist"
/usr/bin/unzip -p "$staging/$ipa" Payload/Veltrix.app/Veltrix > "$staging/Veltrix"
cmp "$executable" "$staging/Veltrix"
mv -f "$staging/$ipa" "$build/$ipa"
(cd "$build" && shasum -a 256 "$ipa" > "$ipa.sha256")
